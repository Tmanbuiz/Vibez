import hmac
import logging
import os
import queue
import random
import shutil
import sqlite3
import sys
import threading
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import librosa
import numpy as np
import soundfile as sf
import torch
from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse

SOULX_ROOT = Path(os.environ.get("SOULX_ROOT", "/opt/SoulX-Singer")).resolve()
DATA_ROOT = Path(os.environ.get("SINGING_DATA_DIR", "/data/jobs")).resolve()
DB_PATH = DATA_ROOT / "jobs.sqlite3"
PROMPT_MAX_SECONDS = 30
TARGET_MAX_SECONDS = 600
SAMPLE_RATE = 44100
PROMPT_MAX_BYTES = 25 * 1024 * 1024
TARGET_MAX_BYTES = 40 * 1024 * 1024
ALLOWED_SUFFIXES = {".wav", ".mp3", ".m4a", ".flac"}
LOG = logging.getLogger("vibez-singing-service")
DB_LOCK = threading.RLock()
WORK_QUEUE: queue.Queue[str] = queue.Queue(maxsize=1000)
MODEL_STATE = None

sys.path.insert(0, str(SOULX_ROOT))
os.chdir(SOULX_ROOT)

from cli.inference_svc import build_model, process as svc_process
from preprocess.pipeline import PreprocessPipeline
from soulxsinger.utils.file_utils import load_config


def _connect():
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    return conn


def _init_db():
    with DB_LOCK, _connect() as conn:
        conn.execute(
            """create table if not exists jobs (
                id text primary key,
                status text not null,
                directory text not null,
                output_path text,
                error text,
                created integer not null
            )"""
        )
        conn.execute("update jobs set status='QUEUED' where status='PROCESSING'")
        conn.commit()
        rows = conn.execute("select id from jobs where status='QUEUED' order by created").fetchall()
    for row in rows:
        try:
            WORK_QUEUE.put_nowait(row["id"])
        except queue.Full:
            LOG.error("The singing job queue is full; some saved jobs were not requeued.")


def _job(job_id: str):
    with DB_LOCK, _connect() as conn:
        row = conn.execute("select * from jobs where id=?", (job_id,)).fetchone()
        return dict(row) if row else None


def _set_job(job_id: str, status: str, output_path: Optional[str] = None, error: Optional[str] = None):
    with DB_LOCK, _connect() as conn:
        conn.execute(
            "update jobs set status=?, output_path=coalesce(?, output_path), error=? where id=?",
            (status, output_path, error, job_id),
        )
        conn.commit()


class ModelState:
    def __init__(self):
        self.device = os.environ.get("SINGING_DEVICE", "cuda:0")
        if self.device.startswith("cuda") and not torch.cuda.is_available():
            raise RuntimeError("A CUDA GPU is required. Set SINGING_DEVICE=cpu only for a slow local test.")
        self.use_fp16 = self.device.startswith("cuda") and os.environ.get("SINGING_FP16", "true").lower() == "true"
        self.config = load_config("soulxsinger/config/soulxsinger.yaml")
        self.preprocess = PreprocessPipeline(
            device=self.device,
            language="Mandarin",
            save_dir=str(DATA_ROOT / "_preprocess"),
            vocal_sep=True,
            max_merge_duration=60000,
            midi_transcribe=False,
        )
        self.model = build_model(
            model_path=str(SOULX_ROOT / "pretrained_models/SoulX-Singer/model-svc.pt"),
            config=self.config,
            device=self.device,
            use_fp16=self.use_fp16,
        )


def _normalize_audio(source: Path, destination: Path, max_seconds: int):
    destination.parent.mkdir(parents=True, exist_ok=True)
    audio, _ = librosa.load(str(source), sr=SAMPLE_RATE, mono=True)
    audio = audio[: max_seconds * SAMPLE_RATE]
    if audio.size == 0:
        raise ValueError("The uploaded audio contains no usable sound.")
    sf.write(str(destination), audio, SAMPLE_RATE)


def _preprocess(state: ModelState, source: Path, output_dir: Path, separate_vocals: bool):
    output_dir.mkdir(parents=True, exist_ok=True)
    state.preprocess.save_dir = str(output_dir)
    state.preprocess.run(
        audio_path=str(source),
        vocal_sep=separate_vocals,
        max_merge_duration=60000,
        language="Mandarin",
    )
    vocal = output_dir / "vocal.wav"
    f0 = output_dir / "vocal_f0.npy"
    if not vocal.exists() or not f0.exists():
        raise RuntimeError("SoulX preprocessing did not produce vocal and pitch files.")
    return vocal, f0


def _convert(job_id: str):
    global MODEL_STATE
    row = _job(job_id)
    if not row:
        return
    root = Path(row["directory"])
    try:
        _set_job(job_id, "PROCESSING")
        audio_dir = root / "audio"
        prompt_upload = next(root.glob("prompt.*"))
        target_upload = next(root.glob("target.*"))
        prompt_raw = audio_dir / "prompt.wav"
        target_raw = audio_dir / "target.wav"
        _normalize_audio(prompt_upload, prompt_raw, PROMPT_MAX_SECONDS)
        _normalize_audio(target_upload, target_raw, TARGET_MAX_SECONDS)

        prompt_wav, prompt_f0 = _preprocess(
            MODEL_STATE, prompt_raw, root / "processed" / "prompt", separate_vocals=False
        )
        target_wav, target_f0 = _preprocess(
            MODEL_STATE, target_raw, root / "processed" / "target", separate_vocals=True
        )

        torch.manual_seed(42)
        np.random.seed(42)
        random.seed(42)
        output_dir = root / "generated"
        output_dir.mkdir(parents=True, exist_ok=True)

        class Args:
            pass

        args = Args()
        args.device = MODEL_STATE.device
        args.prompt_wav_path = str(prompt_wav)
        args.target_wav_path = str(target_wav)
        args.prompt_f0_path = str(prompt_f0)
        args.target_f0_path = str(target_f0)
        args.save_dir = str(output_dir)
        args.auto_shift = True
        args.pitch_shift = 0
        args.n_steps = 32
        args.cfg = 1.0
        args.use_fp16 = MODEL_STATE.use_fp16
        with torch.inference_mode():
            svc_process(args, MODEL_STATE.config, MODEL_STATE.model)

        generated = output_dir / "generated.wav"
        if not generated.exists():
            raise RuntimeError("SoulX conversion did not produce an audio file.")

        accompaniment = root / "processed" / "target" / "acc.wav"
        if accompaniment.exists():
            vocal, _ = librosa.load(str(generated), sr=SAMPLE_RATE, mono=True)
            backing, _ = librosa.load(str(accompaniment), sr=SAMPLE_RATE, mono=True)
            length = min(len(vocal), len(backing))
            mixed = vocal[:length] + backing[:length]
            peak = float(np.max(np.abs(mixed))) if mixed.size else 0.0
            if peak > 0.98:
                mixed = mixed * (0.98 / peak)
            final_path = output_dir / "song-in-my-voice.wav"
            sf.write(str(final_path), mixed, SAMPLE_RATE)
        else:
            final_path = generated

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        _set_job(job_id, "DONE", output_path=str(final_path))
    except Exception:
        LOG.exception("Singing conversion failed for job %s", job_id)
        _set_job(job_id, "FAILED", error="Conversion failed. Check the singing service logs.")
        if torch.cuda.is_available():
            torch.cuda.empty_cache()


def _worker_loop():
    while True:
        job_id = WORK_QUEUE.get()
        try:
            _convert(job_id)
        finally:
            WORK_QUEUE.task_done()


async def _authorize(authorization: Optional[str] = Header(default=None)):
    expected = os.environ.get("SINGING_SERVICE_TOKEN", "")
    token = (authorization or "").removeprefix("Bearer ").strip()
    if not expected:
        raise HTTPException(status_code=503, detail="Singing service authentication is not configured.")
    if not token or not hmac.compare_digest(token, expected):
        raise HTTPException(status_code=401, detail="Unauthorized")


@asynccontextmanager
async def lifespan(app: FastAPI):
    global MODEL_STATE
    if not os.environ.get("SINGING_SERVICE_TOKEN"):
        raise RuntimeError("Set SINGING_SERVICE_TOKEN before starting this service.")
    _init_db()
    MODEL_STATE = ModelState()
    threading.Thread(target=_worker_loop, daemon=True, name="soulx-svc-worker").start()
    yield


app = FastAPI(title="Vibez Singing Voice Service", version="1.0.0", lifespan=lifespan)


async def _save_upload(upload: UploadFile, destination: Path, maximum: int):
    suffix = Path(upload.filename or "").suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(status_code=415, detail="Use WAV, MP3, M4A, or FLAC audio.")
    total = 0
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        with destination.open("wb") as stream:
            while True:
                chunk = await upload.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > maximum:
                    raise HTTPException(status_code=413, detail="Audio upload is too large.")
                stream.write(chunk)
    finally:
        await upload.close()
    if total == 0:
        raise HTTPException(status_code=400, detail="The uploaded audio file is empty.")


@app.get("/health")
async def health():
    return {"ok": True, "service": "vibez-soulx-singer-svc", "model_loaded": MODEL_STATE is not None}


@app.post("/v1/jobs", dependencies=[Depends(_authorize)])
async def create_job(
    prompt_audio: UploadFile = File(...),
    target_audio: UploadFile = File(...),
):
    if WORK_QUEUE.full():
        raise HTTPException(status_code=429, detail="The singing service queue is full. Try again shortly.")
    job_id = str(uuid.uuid4())
    root = DATA_ROOT / job_id
    prompt_suffix = Path(prompt_audio.filename or "").suffix.lower()
    target_suffix = Path(target_audio.filename or "").suffix.lower()
    prompt_path = root / ("prompt" + prompt_suffix)
    target_path = root / ("target" + target_suffix)
    try:
        await _save_upload(prompt_audio, prompt_path, PROMPT_MAX_BYTES)
        await _save_upload(target_audio, target_path, TARGET_MAX_BYTES)
        with DB_LOCK, _connect() as conn:
            conn.execute(
                "insert into jobs (id,status,directory,created) values (?,?,?,?)",
                (job_id, "QUEUED", str(root), int(time.time())),
            )
            conn.commit()
        WORK_QUEUE.put_nowait(job_id)
    except queue.Full:
        shutil.rmtree(root, ignore_errors=True)
        raise HTTPException(status_code=429, detail="The singing service queue is full. Try again shortly.")
    except Exception:
        shutil.rmtree(root, ignore_errors=True)
        raise
    return {"id": job_id, "status": "QUEUED"}


@app.get("/v1/jobs/{job_id}", dependencies=[Depends(_authorize)])
async def get_job(job_id: str):
    row = _job(job_id)
    if not row:
        raise HTTPException(status_code=404, detail="Job not found.")
    return {"id": row["id"], "status": row["status"], "error": row["error"]}


@app.get("/v1/jobs/{job_id}/audio", dependencies=[Depends(_authorize)])
async def get_job_audio(job_id: str):
    row = _job(job_id)
    if not row or row["status"] != "DONE" or not row["output_path"]:
        raise HTTPException(status_code=409, detail="The converted song is not ready.")
    path = Path(row["output_path"]).resolve()
    if not path.is_relative_to(DATA_ROOT) or not path.is_file():
        raise HTTPException(status_code=404, detail="Converted audio not found.")
    return FileResponse(path, media_type="audio/wav", filename="vibez-song-in-my-voice.wav")


@app.delete("/v1/jobs/{job_id}", dependencies=[Depends(_authorize)])
async def delete_job(job_id: str):
    row = _job(job_id)
    if not row:
        return {"ok": True}
    if row["status"] in {"QUEUED", "PROCESSING"}:
        raise HTTPException(status_code=409, detail="A running job cannot be deleted.")
    with DB_LOCK, _connect() as conn:
        conn.execute("delete from jobs where id=?", (job_id,))
        conn.commit()
    shutil.rmtree(Path(row["directory"]), ignore_errors=True)
    return {"ok": True}

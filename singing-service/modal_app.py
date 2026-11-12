"""
Deploy the Vibez singing service (SoulX-Singer) on Modal.

    pip install modal
    modal setup
    modal secret create vibez-singing SINGING_SERVICE_TOKEN=<long random token>
    modal deploy singing-service/modal_app.py

It scales to zero when idle, so you only pay while a song is being converted.
"""
import os
from pathlib import Path

import modal

HERE = Path(__file__).parent
SOULX_ROOT = "/opt/SoulX-Singer"

app = modal.App("vibez-singing")
models = modal.Volume.from_name("vibez-singing-models", create_if_missing=True)

image = (
    modal.Image.from_registry("pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime")
    .env(
        {
            "DEBIAN_FRONTEND": "noninteractive",
            "SOULX_ROOT": SOULX_ROOT,
            # Job files are temporary, so keep them on the container's own disk.
            "SINGING_DATA_DIR": "/tmp/jobs",
            "HF_HOME": "/models/hf",
            "PYTHONUNBUFFERED": "1",
        }
    )
    .apt_install("git", "ffmpeg", "libsndfile1")
    .run_commands(
        f"git clone --depth 1 https://github.com/Soul-AILab/SoulX-Singer.git {SOULX_ROOT}",
        f"cd {SOULX_ROOT} && pip install --no-cache-dir -r requirements.txt",
        "pip install --no-cache-dir fastapi uvicorn python-multipart huggingface_hub",
    )
    .add_local_file(str(HERE / "app.py"), "/srv/app.py")
)


def _prepare_models():
    """Download the SoulX checkpoints into the volume (fast after the first run)."""
    from huggingface_hub import snapshot_download

    for repo, name in [
        ("Soul-AILab/SoulX-Singer", "SoulX-Singer"),
        ("Soul-AILab/SoulX-Singer-Preprocess", "SoulX-Singer-Preprocess"),
    ]:
        dest = f"/models/{name}"
        snapshot_download(repo_id=repo, local_dir=dest)
        link = f"{SOULX_ROOT}/pretrained_models/{name}"
        os.makedirs(os.path.dirname(link), exist_ok=True)
        if not os.path.lexists(link):
            os.symlink(dest, link)
    models.commit()


@app.function(
    image=image,
    gpu="L4",
    volumes={"/models": models},
    secrets=[modal.Secret.from_name("vibez-singing")],
    timeout=3600,
    scaledown_window=600,  # stay warm 10 min after the last request
    max_containers=1,  # the job queue lives inside one container
)
@modal.concurrent(max_inputs=16)
@modal.asgi_app()
def web():
    import sys

    _prepare_models()
    sys.path.insert(0, "/srv")
    from app import app as fastapi_app

    return fastapi_app

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    SOULX_ROOT=/opt/SoulX-Singer \
    SINGING_DATA_DIR=/data/jobs \
    HF_HOME=/data/hf \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends git ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 https://github.com/Soul-AILab/SoulX-Singer.git

WORKDIR /opt/SoulX-Singer
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir fastapi uvicorn python-multipart

COPY app.py /srv/app.py
COPY entrypoint.sh /srv/entrypoint.sh
RUN mkdir -p /data/jobs /data/models

EXPOSE 8080
CMD ["bash", "/srv/entrypoint.sh"]

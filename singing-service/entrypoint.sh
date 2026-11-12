#!/usr/bin/env bash
set -euo pipefail

cd /opt/SoulX-Singer
mkdir -p /data/models/SoulX-Singer /data/models/SoulX-Singer-Preprocess pretrained_models
hf download Soul-AILab/SoulX-Singer --local-dir /data/models/SoulX-Singer
hf download Soul-AILab/SoulX-Singer-Preprocess --local-dir /data/models/SoulX-Singer-Preprocess
ln -sfn /data/models/SoulX-Singer pretrained_models/SoulX-Singer
ln -sfn /data/models/SoulX-Singer-Preprocess pretrained_models/SoulX-Singer-Preprocess

exec uvicorn app:app --app-dir /srv --host 0.0.0.0 --port 8080

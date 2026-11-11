# Vibez singing voice service

This GPU service wraps the official SoulX-Singer-SVC inference and preprocessing pipeline. The Flutter app and Cloudflare Worker call it; the Worker keeps the service token private.

## What it does

- Receives a clean singing reference clip and a generated song.
- Separates the target song's vocal and accompaniment, then converts the vocal timbre to the reference singer.
- Mixes the converted vocal back with the accompaniment.
- Returns a job ID so the Worker can poll while conversion runs.

The reference should be your own clean singing, preferably without accompaniment. The service uses at most 30 seconds of it. The generated target can contain music and vocals. SoulX's maintainers note that full songs with wide pitch ranges may be less stable; converting shorter sections can help.

## Host requirements

Use a Linux host with an NVIDIA GPU and enough disk for the SoulX-Singer and preprocessing checkpoints. This is a separate service because the model does not run inside a Cloudflare Worker. The app feature stays disabled until this service is deployed and configured.

## Build and run

From the repository root:

~~~sh
docker build -t vibez-singing-service ./singing-service

# Use a long random token and store the same value as a Cloudflare Worker secret.
docker run --rm --gpus all \
  -p 8080:8080 \
  -e SINGING_SERVICE_TOKEN='replace-with-a-long-random-secret' \
  -v vibez-singing-data:/data \
  vibez-singing-service
~~~

The first startup downloads public SoulX model checkpoints into the mounted volume, then loads the model. Keep the service behind HTTPS when it is reachable from the internet. The unauthenticated /health endpoint reports readiness only; all job endpoints require a bearer token.

## Connect the Cloudflare Worker

Set SINGING_SERVICE_URL in worker/wrangler.jsonc to the HTTPS base URL of the GPU service, then add the same secret used above:

~~~sh
cd worker
npx wrangler secret put SINGING_SERVICE_TOKEN
npx wrangler deploy
~~~

Apply the singers table to your existing database with `npx wrangler d1 execute tmanvibez --remote --file schema.sql` from the `worker/` directory. Do not put either service token in the Flutter app or a committed file.

## API contract

- POST /v1/jobs — multipart fields prompt_audio and target_audio; returns an ID and QUEUED status.
- GET /v1/jobs/{id} — returns QUEUED, PROCESSING, DONE, or FAILED.
- GET /v1/jobs/{id}/audio — streams the finished WAV.
- DELETE /v1/jobs/{id} — removes finished job files.

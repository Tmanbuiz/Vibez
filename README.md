# TmanVibez AI

Personal AI studio: **voice clone · music · image · video**, powered by Venice AI.
Backend = one Cloudflare Worker (+ D1 library, R2 storage). App = Flutter (web, iOS, Android) — next step.

## Deploy the backend

```bash
cd worker
npm install
npx wrangler login

npx wrangler d1 create tmanvibez          # copy the database_id into wrangler.jsonc
npx wrangler r2 bucket create tmanvibez-media
npx wrangler d1 execute DB --remote --file schema.sql

npx wrangler secret put VENICE_API_KEY    # your Venice key
npx wrangler secret put APP_TOKEN         # any long random string: this is your app login
npx wrangler deploy
```

Your API lives at `https://tmanvibez-ai-api.<your-subdomain>.workers.dev`.

Spend cap: `MAX_JOB_USD` in `wrangler.jsonc` (default `1.00`). Music/video quotes above it are refused.
Images have no quote endpoint, so they are not capped.

## API (all need `Authorization: Bearer <APP_TOKEN>`)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/models?type=music\|image\|video\|tts` | list Venice models |
| POST | `/api/quote` | `{kind, model, duration_seconds / duration, ...}` → price |
| POST | `/api/music` | `{model, prompt, lyrics_prompt?, duration_seconds, force_instrumental?}` |
| POST | `/api/video` | `{model, prompt, duration, resolution?, aspect_ratio?, image_url?}` |
| POST | `/api/image` | `{model, prompt, aspect_ratio?, ...}` (instant) |
| POST | `/api/voices` | multipart `file`, `name` → clone a voice |
| GET | `/api/voices` | saved voices with days left (handles expire after 7 days) |
| POST | `/api/speak` | `{voice, text}` → speech in your voice |
| GET | `/api/jobs/:id` | poll a music/video job; saves to R2 when done |
| GET | `/api/library` | everything you've made |
| GET | `/api/media/:id?token=` | stream a file (Range supported) |

Only clone your own voice, or someone who has clearly agreed.

## The app (Flutter: web, Android, iOS)

Source is in `app/` (`lib/` + `pubspec.yaml`). GitHub Actions (`.github/workflows/build-app.yml`) generates the
platform folders and builds on every push to `main`:

- **Android APK**: Actions tab → latest run → artifact `tmanvibez-ai-apk` → install on your phone
- **Web**: artifact `tmanvibez-ai-web`, or deploy it with `npx wrangler pages deploy build/web --project-name tmanvibez`

First launch: open **Settings** (gear), enter your Worker URL and `APP_TOKEN`, tap *Save & test*.

Screens: Music · Image · Video · Voice · Library. Music and video always show the price and ask before spending.

iOS needs an Apple Developer account for signing, so it is not part of the automatic build yet.

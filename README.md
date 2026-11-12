# Vibez AI Studio

Personal AI studio for music, images, video, speech, and singing voice conversion. The Flutter app runs on Android, iOS, and web; a Cloudflare Worker protects the Venice key and stores the creation library in D1 and R2.

## Deploy the backend

```bash
cd worker
npm install
npx wrangler login

npx wrangler d1 create tmanvibez          # copy the database_id into wrangler.jsonc
npx wrangler r2 bucket create tmanvibez-media
npx wrangler d1 execute tmanvibez --remote --file schema.sql

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
| POST | `/api/voices` | multipart `file`, `name` → clone a speaking voice |
| GET | `/api/voices` | saved speech voices (Venice handles expire after 7 days) |
| POST | `/api/speak` | `{voice, text}` → speech in your voice |
| POST | `/api/singers` | multipart singing sample and name → saved singer profile |
| GET | `/api/singers` | list saved singing profiles |
| DELETE | `/api/singers/:id` | delete a saved singing profile and its audio |
| POST | `/api/revoice` | `{song_id, singer_id}` → convert a generated song to that singer |
| GET | `/api/jobs/:id` | poll a music/video job; saves to R2 when done |
| GET | `/api/library` | everything you've made |
| GET | `/api/media/:id?token=` | stream a file (Range supported) |

Only clone your own voice, or someone who has clearly agreed.

## Sing a generated song in your voice

The Music screen can generate a Venice song, then convert its lead vocal to a saved singer profile with the open-source SoulX-Singer-SVC model. The conversion service separates vocals from the mixed track, converts the singer, and mixes the vocal back with the accompaniment. The 5–10 second Venice speech clone is separate and cannot be used as a singing profile.

Create a singer profile in the Voice screen with a clean 10–30 second singing sample, preferably without backing music. The sample stays in your R2 bucket until you delete it. Conversion runs on a separate NVIDIA GPU host; it cannot run inside Cloudflare Workers. Set the service URL in worker/wrangler.jsonc, set the SINGING_SERVICE_TOKEN secret with Wrangler, and follow [singing-service/README.md](singing-service/README.md). The app warns before using the configured service because the GPU host may charge compute fees.

## The app (Flutter: web, Android, iOS)

Source is in `app/` (`lib/` + `pubspec.yaml`). GitHub Actions (`.github/workflows/build-app.yml`) generates the
platform folders and builds on pushes to `main` and this feature branch, and on pull requests into `main`:

- **Android APK**: Actions tab → latest run → artifact `tmanvibez-ai-apk` → install on your phone
- **Web**: artifact `tmanvibez-ai-web`, or deploy it with `npx wrangler pages deploy build/web --project-name tmanvibez`

First launch: open **Settings** (gear), enter your Worker URL and `APP_TOKEN`, tap *Save & test*.

Screens: Music · Images · Video · Voice · Library. Music and video show a price and ask before spending. A separate singing profile is used for songs; the speech clone remains for spoken audio.

The GitHub Actions workflow builds an APK and web build. It also builds an iOS IPA when Apple signing secrets are configured. Add these repository secrets in GitHub Actions settings: IOS_CERTIFICATE_BASE64 (base64-encoded Apple Distribution .p12), IOS_CERTIFICATE_PASSWORD, IOS_PROVISIONING_PROFILE_BASE64, IOS_TEAM_ID, and IOS_BUNDLE_ID. Without those credentials, the workflow creates an ad-hoc signed IPA package for AltStore to re-sign when you install it; it is not an App Store submission. Do not paste Apple signing secrets into source code or chat.

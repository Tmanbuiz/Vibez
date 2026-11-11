// TmanVibez AI backend — Cloudflare Worker.
// Holds the Venice API key, enforces a per-job spend cap, polls async jobs,
// stores finished media in R2 and the library in D1.

const V = "https://api.venice.ai/api/v1";
const CLONE_MODEL = "tts-chatterbox-hd";
const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization,content-type,range",
  "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
  "access-control-expose-headers": "content-range,accept-ranges,content-length",
};

const json = (o, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { "content-type": "application/json", ...CORS } });
const fail = (msg, s = 400, extra = {}) => json({ error: msg, ...extra }, s);
const vAuth = (env) => ({ authorization: `Bearer ${env.VENICE_API_KEY}` });
const vJson = (env) => ({ ...vAuth(env), "content-type": "application/json" });
const pick = (o, keys) => Object.fromEntries(keys.filter((k) => o[k] !== undefined && o[k] !== "").map((k) => [k, o[k]]));
const ext = (ct) =>
  ({ "audio/mpeg": "mp3", "audio/wav": "wav", "audio/x-wav": "wav", "audio/flac": "flac", "audio/mp4": "m4a",
     "video/mp4": "mp4", "image/webp": "webp", "image/png": "png", "image/jpeg": "jpg" })[ct.split(";")[0]] || "bin";

const FIELDS = {
  music: ["model", "prompt", "duration_seconds", "lyrics_prompt", "force_instrumental", "loop"],
  video: ["model", "prompt", "duration", "resolution", "aspect_ratio", "image_url", "negative_prompt", "audio"],
  image: ["model", "prompt", "negative_prompt", "aspect_ratio", "resolution", "width", "height", "steps",
          "format", "cfg_scale", "seed", "style_preset", "quality", "safe_mode"],
};
const QUOTE_FIELDS = {
  music: ["model", "duration_seconds"],
  video: ["model", "duration", "resolution", "aspect_ratio", "audio"],
};

function authed(req, env, url) {
  const t = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "") || url.searchParams.get("token") || "";
  return env.APP_TOKEN && t === env.APP_TOKEN;
}

export default {
  async fetch(req, env, ctx) {
    if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
    const url = new URL(req.url);
    const path = url.pathname;
    if (path === "/" || path === "/health") return json({ app: "TmanVibez AI", ok: true });
    if (!path.startsWith("/api/")) return fail("Not found", 404);
    if (!authed(req, env, url)) return fail("Unauthorized", 401);
    if (!env.VENICE_API_KEY) return fail("VENICE_API_KEY secret is not set", 500);

    try {
      let m;
      if (req.method === "GET" && path === "/api/models") return await models(env, url);
      if (req.method === "POST" && path === "/api/quote") return await quoteRoute(env, req);
      if (req.method === "POST" && (m = path.match(/^\/api\/(music|video)$/))) return await queueRoute(env, req, m[1]);
      if (req.method === "POST" && path === "/api/image") return await imageRoute(env, req);
      if (req.method === "GET" && path === "/api/voices") return await voicesList(env);
      if (req.method === "POST" && path === "/api/voices") return await voiceCreate(env, req);
      if (req.method === "DELETE" && (m = path.match(/^\/api\/voices\/(.+)$/))) return await voiceDelete(env, m[1]);
      if (req.method === "POST" && path === "/api/speak") return await speak(env, req);
      if (req.method === "GET" && (m = path.match(/^\/api\/jobs\/([\w-]+)$/))) return await pollRoute(env, ctx, m[1]);
      if (req.method === "GET" && path === "/api/library") return await library(env, url);
      if (req.method === "GET" && (m = path.match(/^\/api\/media\/([\w-]+)$/))) return await media(env, req, m[1]);
      if (req.method === "DELETE" && (m = path.match(/^\/api\/library\/([\w-]+)$/))) return await libDelete(env, m[1]);
      return fail("Not found", 404);
    } catch (e) {
      return fail(String(e && e.message || e), 500);
    }
  },
};

// ---------- helpers ----------
async function veniceError(r) {
  const t = await r.text();
  let body; try { body = JSON.parse(t); } catch { body = t.slice(0, 500); }
  return fail(body, r.status);
}

async function getQuote(kind, body) {
  const base = kind === "music" ? "audio" : "video";
  const r = await fetch(`${V}/${base}/quote`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify(pick(body, QUOTE_FIELDS[kind])),
  });
  if (!r.ok) return { err: r };
  return { quote: (await r.json()).quote };
}

async function insertItem(env, it) {
  await env.DB.prepare(
    "insert into items (id,kind,title,prompt,model,status,queue_id,key,mime,cost,created,meta) values (?,?,?,?,?,?,?,?,?,?,?,?)"
  ).bind(it.id, it.kind, it.title || "", it.prompt || "", it.model || "", it.status, it.queue_id || null,
         it.key || null, it.mime || null, it.cost ?? null, Date.now(), JSON.stringify(it.meta || {})).run();
}

// ---------- routes ----------
async function models(env, url) {
  const type = url.searchParams.get("type") || "music";
  const r = await fetch(`${V}/models?type=${encodeURIComponent(type)}`, { headers: vAuth(env) });
  if (!r.ok) return veniceError(r);
  return json(await r.json());
}

async function quoteRoute(env, req) {
  const b = await req.json();
  if (!["music", "video"].includes(b.kind)) return fail("kind must be music or video");
  const q = await getQuote(b.kind, b);
  if (q.err) return veniceError(q.err);
  return json({ quote: q.quote, limit: parseFloat(env.MAX_JOB_USD || "1") });
}

async function queueRoute(env, req, kind) {
  const b = await req.json();
  if (!b.model || !b.prompt) return fail("model and prompt are required");
  const q = await getQuote(kind, b);
  if (q.err) return veniceError(q.err);
  const limit = parseFloat(env.MAX_JOB_USD || "1");
  if (q.quote > limit) return fail(`Quote $${q.quote} is over your $${limit} per-job limit`, 402, { quote: q.quote, limit });

  const base = kind === "music" ? "audio" : "video";
  const r = await fetch(`${V}/${base}/queue`, { method: "POST", headers: vJson(env), body: JSON.stringify(pick(b, FIELDS[kind])) });
  if (!r.ok) return veniceError(r);
  const j = await r.json();
  const id = crypto.randomUUID();
  await insertItem(env, {
    id, kind, title: b.title || b.prompt.slice(0, 60), prompt: b.prompt, model: j.model || b.model,
    status: "PROCESSING", queue_id: j.queue_id, cost: q.quote, meta: { download_url: j.download_url || null },
  });
  return json({ id, status: "PROCESSING", quote: q.quote });
}

async function imageRoute(env, req) {
  const b = await req.json();
  if (!b.model || !b.prompt) return fail("model and prompt are required");
  const r = await fetch(`${V}/image/generate`, {
    method: "POST", headers: vJson(env), body: JSON.stringify({ ...pick(b, FIELDS.image), return_binary: true }),
  });
  if (!r.ok) return veniceError(r);
  const mime = r.headers.get("content-type") || "image/webp";
  const id = crypto.randomUUID();
  const key = `image/${id}.${ext(mime)}`;
  await env.MEDIA.put(key, await r.arrayBuffer(), { httpMetadata: { contentType: mime } });
  await insertItem(env, {
    id, kind: "image", title: b.title || b.prompt.slice(0, 60), prompt: b.prompt, model: b.model, status: "DONE", key, mime,
    meta: { blurred: r.headers.get("x-venice-is-blurred") === "true" },
  });
  return json({ id, status: "DONE" });
}

async function voicesList(env) {
  const { results } = await env.DB.prepare("select * from voices order by created desc").all();
  const now = Date.now();
  return json(results.map((v) => {
    const left = 7 - (now - v.created) / 86400000;
    return { ...v, days_left: Math.max(0, Math.round(left * 10) / 10), expired: left <= 0 };
  }));
}

async function voiceCreate(env, req) {
  const fd = await req.formData();
  const file = fd.get("file");
  if (!file || typeof file === "string") return fail("No audio file");
  const name = String(fd.get("name") || "My voice").slice(0, 60);
  const out = new FormData();
  out.append("model", CLONE_MODEL);
  out.append("file", file, file.name || "sample.wav");
  const r = await fetch(`${V}/audio/voices`, { method: "POST", headers: vAuth(env), body: out });
  if (!r.ok) return veniceError(r);
  const { id } = await r.json();
  await env.DB.prepare("insert into voices (id,name,created) values (?,?,?)").bind(id, name, Date.now()).run();
  return json({ id, name });
}

async function voiceDelete(env, id) {
  await env.DB.prepare("delete from voices where id=?").bind(decodeURIComponent(id)).run();
  return json({ ok: true });
}

async function speak(env, req) {
  const b = await req.json();
  if (!b.voice || !b.text) return fail("voice and text are required");
  const r = await fetch(`${V}/audio/speech`, {
    method: "POST", headers: vJson(env),
    body: JSON.stringify({ model: CLONE_MODEL, voice: b.voice, input: b.text, response_format: "wav" }),
  });
  if (!r.ok) return veniceError(r);
  const mime = r.headers.get("content-type") || "audio/wav";
  const id = crypto.randomUUID();
  const key = `speech/${id}.${ext(mime)}`;
  await env.MEDIA.put(key, await r.arrayBuffer(), { httpMetadata: { contentType: mime } });
  await insertItem(env, { id, kind: "speech", title: b.text.slice(0, 60), prompt: b.text, model: CLONE_MODEL, status: "DONE", key, mime });
  return json({ id, status: "DONE" });
}

async function pollRoute(env, ctx, id) {
  const it = await env.DB.prepare("select * from items where id=?").bind(id).first();
  if (!it) return fail("Job not found", 404);
  if (it.status === "DONE" || it.status === "FAILED") return json(view(it));

  const base = it.kind === "music" ? "audio" : "video";
  const r = await fetch(`${V}/${base}/retrieve`, {
    method: "POST", headers: vJson(env), body: JSON.stringify({ model: it.model, queue_id: it.queue_id }),
  });
  if (!r.ok) {
    if (r.status >= 500 || r.status === 429) return json({ ...view(it), note: "Venice busy, retrying" });
    const msg = (await r.text()).slice(0, 300);
    await env.DB.prepare("update items set status='FAILED', meta=? where id=?")
      .bind(JSON.stringify({ ...JSON.parse(it.meta || "{}"), error: msg }), id).run();
    return json({ ...view(it), status: "FAILED", error: msg });
  }

  let ct = r.headers.get("content-type") || "";
  let buf = null;
  if (ct.includes("application/json")) {
    const j = await r.json();
    if (j.status !== "COMPLETED") {
      return json({ ...view(it), status: "PROCESSING", elapsed_ms: j.execution_duration, expected_ms: j.average_execution_time });
    }
    const dl = JSON.parse(it.meta || "{}").download_url;
    if (!dl) return fail("Job completed but no download URL", 502);
    const f = await fetch(dl); // no auth header, per Venice docs
    if (!f.ok) return fail("Could not download finished file", 502);
    ct = f.headers.get("content-type") || "video/mp4";
    buf = await f.arrayBuffer();
  } else {
    buf = await r.arrayBuffer();
  }

  const key = `${it.kind}/${id}.${ext(ct)}`;
  await env.MEDIA.put(key, buf, { httpMetadata: { contentType: ct } });
  await env.DB.prepare("update items set status='DONE', key=?, mime=? where id=?").bind(key, ct, id).run();
  // free Venice's temporary storage once we've saved our copy
  ctx.waitUntil(fetch(`${V}/${base}/complete`, {
    method: "POST", headers: vJson(env), body: JSON.stringify({ model: it.model, queue_id: it.queue_id }),
  }).catch(() => {}));
  return json(view({ ...it, status: "DONE", key, mime: ct }));
}

const view = (it) => ({
  id: it.id, kind: it.kind, title: it.title, prompt: it.prompt, model: it.model, status: it.status,
  mime: it.mime, cost: it.cost, created: it.created, has_media: !!it.key,
  error: (() => { try { return JSON.parse(it.meta || "{}").error || null; } catch { return null; } })(),
});

async function library(env, url) {
  const kind = url.searchParams.get("kind");
  const stmt = kind
    ? env.DB.prepare("select * from items where kind=? order by created desc limit 200").bind(kind)
    : env.DB.prepare("select * from items order by created desc limit 200");
  const { results } = await stmt.all();
  return json(results.map(view));
}

async function libDelete(env, id) {
  const it = await env.DB.prepare("select key from items where id=?").bind(id).first();
  if (it && it.key) await env.MEDIA.delete(it.key);
  await env.DB.prepare("delete from items where id=?").bind(id).run();
  return json({ ok: true });
}

// Streams media with Range support (needed for audio/video seeking, esp. iOS Safari)
async function media(env, req, id) {
  const it = await env.DB.prepare("select key from items where id=?").bind(id).first();
  if (!it || !it.key) return fail("Not found", 404);
  const wantsRange = req.headers.has("range");
  const obj = await env.MEDIA.get(it.key, wantsRange ? { range: req.headers } : undefined);
  if (!obj) return fail("Not found", 404);
  const h = new Headers(CORS);
  obj.writeHttpMetadata(h);
  h.set("etag", obj.httpEtag);
  h.set("accept-ranges", "bytes");
  h.set("cache-control", "private, max-age=3600");
  let status = 200;
  if (wantsRange && obj.range) {
    const size = obj.size;
    const offset = obj.range.suffix !== undefined ? size - obj.range.suffix : obj.range.offset ?? 0;
    const length = obj.range.suffix !== undefined ? obj.range.suffix : obj.range.length ?? size - offset;
    h.set("content-range", `bytes ${offset}-${offset + length - 1}/${size}`);
    h.set("content-length", String(length));
    status = 206;
  } else {
    h.set("content-length", String(obj.size));
  }
  return new Response(obj.body, { status, headers: h });
}

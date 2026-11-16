import { createClient } from "npm:@supabase/supabase-js@2";

const out = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

function hex(bytes: Uint8Array): string {
  return [...bytes].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return out({ error: "Method not allowed" }, 405);

  const secret = Deno.env.get("CLOUDFLARE_STREAM_WEBHOOK_SECRET");
  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret || !url || !service) return out({ error: "Webhook is not configured" }, 503);

  const declaredLength = Number(req.headers.get("content-length") || "0");
  if (declaredLength > 1_000_000) return out({ error: "Payload too large" }, 413);

  const signature = req.headers.get("Webhook-Signature") || "";
  const parts = Object.fromEntries(signature.split(",").map((part) => {
    const i = part.indexOf("=");
    return i < 0 ? ["", ""] : [part.slice(0, i), part.slice(i + 1)];
  }));
  const stamp = Number(parts.time);
  const sig = String(parts.sig1 || "");
  if (!Number.isFinite(stamp) || Math.abs(Date.now() / 1000 - stamp) > 300 ||
      !/^[a-f0-9]{64}$/i.test(sig)) {
    return out({ error: "Invalid webhook signature" }, 401);
  }

  const raw = await req.text();
  if (raw.length > 1_000_000) return out({ error: "Payload too large" }, 413);

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = hex(new Uint8Array(await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(String(stamp) + "." + raw),
  )));
  if (!safeEqual(expected.toLowerCase(), sig.toLowerCase())) {
    return out({ error: "Invalid webhook signature" }, 401);
  }

  let body: any;
  try { body = JSON.parse(raw); } catch { return out({ error: "Invalid JSON" }, 400); }
  if (typeof body?.uid !== "string" || body.uid.length < 1 || body.uid.length > 200 ||
      typeof body?.status?.state !== "string") {
    return out({ error: "Invalid event" }, 400);
  }

  const state = body.status.state;
  const ready = state === "ready" && body.readyToStream === true &&
    Number(body.status.pctComplete) >= 100;
  const mappedState = ready ? "ready" : state === "error" ? "failed" : "processing";

  const duration = Number(body.duration);
  const width = Number(body.input?.width);
  const height = Number(body.input?.height);
  const db = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await db.rpc("flow_apply_cloudflare_stream_webhook_v1", {
    p_cloudflare_uid: body.uid,
    p_state: mappedState,
    p_duration_seconds: Number.isFinite(duration) && duration > 0 ? duration : null,
    p_width: Number.isInteger(width) && width > 0 ? width : null,
    p_height: Number.isInteger(height) && height > 0 ? height : null,
    p_thumbnail_url: typeof body.thumbnail === "string" ? body.thumbnail.slice(0, 2000) : null,
    p_playback_hls_url: typeof body.playback?.hls === "string" ? body.playback.hls.slice(0, 2000) : null,
    p_playback_dash_url: typeof body.playback?.dash === "string" ? body.playback.dash.slice(0, 2000) : null,
    p_error_code: typeof body.status.errorReasonCode === "string"
      ? body.status.errorReasonCode.slice(0, 80)
      : "PROCESSING_FAILED",
  });

  if (error) return out({ error: "Webhook event could not be applied safely" }, 503);
  if (data === "asset_state_blocked") {
    return out({ ok: true, ignored: true, reason: data });
  }
  return out({ ok: true, result: data });
});

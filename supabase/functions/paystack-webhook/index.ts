import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-paystack-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
async function hmac(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  return hex(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message))));
}
async function validSignature(req: Request, raw: string): Promise<boolean> {
  const signature = req.headers.get("x-paystack-signature");
  const secretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!signature || !secretKey || !/^[0-9a-f]{128}$/i.test(signature)) return false;
  const expected = await hmac(secretKey, raw);
  return constantTimeEqual(expected, signature.toLowerCase());
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  const raw = await req.text();
  if (raw.length > 256_000) return reply({ error: "Payload too large" }, 413);
  if (!await validSignature(req, raw)) return reply({ error: "Invalid webhook signature" }, 401);

  let event: any;
  try { event = JSON.parse(raw); } catch { return reply({ error: "Invalid JSON" }, 400); }
  if (event?.event === "ping") return reply({ ok: true });
  const isCharge = event?.event === "charge.success";
  const isTransfer = ["transfer.success", "transfer.failed", "transfer.reversed"].includes(event?.event);
  if (!isCharge && !isTransfer) return reply({ ok: true, ignored: true });

  const reference = event?.data?.reference;
  if (typeof reference !== "string" || reference.length < 4 || reference.length > 120) {
    return reply({ error: "Invalid transaction reference" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const paystackKey = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!url || !service || !paystackKey) {
    return reply({ error: "Payment verification is not configured" }, 503);
  }

  const db = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });

  if (isTransfer) {
    const { data: withdrawal, error: withdrawalLookupError } = await db
      .from("playam_creator_withdrawal_requests")
      .select("id,amount_minor,currency,status,payout_provider,payout_reference")
      .eq("payout_provider", "paystack")
      .eq("payout_reference", reference)
      .maybeSingle();

    if (withdrawalLookupError) return reply({ error: "Withdrawal lookup unavailable" }, 503);
    if (!withdrawal) return reply({ ok: true, ignored: true });

    const transferVerify = await fetch("https://api.paystack.co/transfer/verify/" + encodeURIComponent(reference), {
      method: "GET",
      headers: { Authorization: "Bearer " + paystackKey, Accept: "application/json" },
    });
    if (!transferVerify.ok) return reply({ error: "Paystack transfer verification temporarily unavailable" }, 503);
    const transferResult: any = await transferVerify.json();
    const transfer = transferResult?.data;

    if (transferResult?.status !== true ||
        transfer?.reference !== reference ||
        Number(transfer?.amount) !== Number(withdrawal.amount_minor) ||
        transfer?.currency !== withdrawal.currency ||
        withdrawal.currency !== "NGN") {
      return reply({ error: "Verified transfer does not match the approved withdrawal" }, 409);
    }

    if (event.event === "transfer.success") {
      if (transfer.status !== "success") return reply({ error: "Transfer is not verified as successful" }, 409);
      const { error } = await db.rpc("playam_mark_creator_withdrawal_paid_v1", {
        p_request_id: withdrawal.id,
        p_provider_reference: reference,
      });
      if (error) return reply({ error: "Verified payout could not be recorded safely" }, 503);
      return reply({ ok: true, result: "withdrawal_paid" });
    }

    if (event.event === "transfer.failed") {
      if (transfer.status !== "failed") return reply({ error: "Transfer is not verified as failed" }, 409);
      const reason = typeof transfer.failures === "string" ? transfer.failures.slice(0, 500) : "Paystack verified transfer failure";
      const { error } = await db.rpc("playam_mark_creator_withdrawal_failed_v1", {
        p_request_id: withdrawal.id,
        p_reason: reason,
      });
      if (error) return reply({ error: "Failed payout could not be reversed safely" }, 503);
      return reply({ ok: true, result: "withdrawal_released" });
    }

    if (event.event === "transfer.reversed") {
      if (transfer.status !== "reversed") return reply({ error: "Transfer reversal is not verified" }, 409);
      const { error } = await db.rpc("playam_record_paystack_transfer_reversal_v1", {
        p_request_id: withdrawal.id,
        p_provider_reference: reference,
        p_transfer_code: transfer.transfer_code ?? null,
      });
      if (error) return reply({ error: "Transfer reversal audit could not be recorded safely" }, 503);
      return reply({ ok: true, result: "reversal_flagged_for_manual_review" });
    }
  }

  const { data: payment, error: lookupError } = await db
    .from("playam_payment_transactions")
    .select("id,provider,provider_transaction_id,status,amount_minor,currency")
    .eq("provider", "paystack")
    .eq("provider_transaction_id", reference)
    .maybeSingle();
  if (lookupError) return reply({ error: "Payment lookup unavailable" }, 503);
  if (!payment) return reply({ ok: true, ignored: true });

  const verify = await fetch("https://api.paystack.co/transaction/verify/" + encodeURIComponent(reference), {
    method: "GET",
    headers: { Authorization: "Bearer " + paystackKey, Accept: "application/json" },
  });
  if (!verify.ok) return reply({ error: "Paystack verification temporarily unavailable" }, 503);
  const verified: any = await verify.json();
  const d = verified?.data;
  if (verified?.status !== true || d?.status !== "success" ||
      d?.reference !== reference || d?.currency !== payment.currency ||
      Number(d?.amount) !== Number(payment.amount_minor) ||
      payment.currency !== "NGN") {
    return reply({ error: "Paystack transaction did not match the pending payment" }, 409);
  }

  const { data: credited, error: creditError } = await db.rpc(
    "playam_confirm_paystack_coin_purchase_v1",
    {
      p_payment_id: payment.id,
      p_provider_transaction_id: reference,
      p_verified_amount_minor: Number(d.amount),
      p_verified_currency: String(d.currency),
    },
  );
  if (creditError) return reply({ error: "Verified payment could not be credited safely" }, 503);
  return reply({ ok: true, result: credited });
});
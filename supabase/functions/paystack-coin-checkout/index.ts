import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://playamcom.github.io", "https://playam-mobile-staging-playam1.vercel.app"]);

function headers(origin: string | null) {
  const allowed = origin && allowedOrigins.has(origin) ? origin : "";
  return {
    ...(allowed ? { "Access-Control-Allow-Origin": allowed, "Vary": "Origin" } : {}),
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  };
}

const reply = (body: unknown, status = 200, origin: string | null = null) =>
  new Response(JSON.stringify(body), { status, headers: headers(origin) });

function validPackageSnapshot(pkg: any) {
  const amount = Number(pkg?.amount_minor);
  const coins = Number(pkg?.coin_amount);
  return Number.isSafeInteger(amount) && amount > 0 &&
    Number.isSafeInteger(coins) && coins > 0 &&
    amount === coins * 10_000 && pkg?.currency === "NGN";
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") {
    if (origin && !allowedOrigins.has(origin)) return new Response("Origin not allowed", { status: 403 });
    return new Response("ok", { headers: headers(origin) });
  }
  if (!origin || !allowedOrigins.has(origin)) return reply({ error: "Origin not allowed" }, 403, origin);
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405, origin);

  // Deliberately disabled until the owner separately authorizes real Paystack checkout activation.
  if (Deno.env.get("PLAYAM_COIN_CHECKOUT_ENABLED") !== "true") {
    return reply({ error: "PLAYAM Coin checkout is not enabled yet. No payment has been started." }, 503, origin);
  }

  const raw = await req.text();
  if (new TextEncoder().encode(raw).byteLength > 12_000) {
    return reply({ error: "Request too large" }, 413, origin);
  }

  let body: any;
  try { body = JSON.parse(raw); } catch {
    return reply({ error: "Invalid JSON" }, 400, origin);
  }

  const packageCode = body?.package_code;
  const idempotencyKey = body?.idempotency_key;
  if (typeof packageCode !== "string" || !/^[a-z0-9_]{2,40}$/.test(packageCode) ||
      typeof idempotencyKey !== "string" || !/^[A-Za-z0-9_-]{16,100}$/.test(idempotencyKey)) {
    return reply({ error: "A valid package_code and idempotency_key are required" }, 400, origin);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token) return reply({ error: "Sign-in required" }, 401, origin);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const paystackKey = Deno.env.get("PAYSTACK_SECRET_KEY");
  const callbackUrl = origin === "https://playam-mobile-staging-playam1.vercel.app"
    ? "https://playam-mobile-staging-playam1.vercel.app/"
    : Deno.env.get("PLAYAM_COIN_CHECKOUT_CALLBACK_URL");
  if (!url || !anonKey || !serviceKey || !paystackKey || !callbackUrl) {
    return reply({ error: "Coin checkout is not configured for this environment" }, 503, origin);
  }
  // Staging is test-mode only. Even if the feature flag is enabled, live Paystack keys are rejected.
  if (Deno.env.get("PAYSTACK_ENVIRONMENT") !== "test" || !paystackKey.startsWith("sk_test_")) {
    return reply({ error: "Staging coin checkout requires Paystack test-mode credentials" }, 503, origin);
  }

  let callback: URL;
  try { callback = new URL(callbackUrl); } catch {
    return reply({ error: "Coin checkout callback URL is invalid" }, 503, origin);
  }
  if (callback.protocol !== "https:" || callback.origin !== origin) {
    return reply({ error: "Coin checkout callback URL is not approved" }, 503, origin);
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: "Bearer " + token } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user?.id || !user.email) {
    return reply({ error: "A valid signed-in account with an email address is required" }, 401, origin);
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: pkg, error: packageError } = await admin
    .from("playam_purchased_coin_packages")
    .select("package_code,display_name,amount_minor,coin_amount,currency,is_active")
    .eq("package_code", packageCode)
    .eq("is_active", true)
    .maybeSingle();

  if (packageError) return reply({ error: "Coin package lookup is temporarily unavailable" }, 503, origin);
  if (!pkg) return reply({ error: "This coin package is not available" }, 404, origin);
  if (!validPackageSnapshot(pkg)) {
    return reply({ error: "This coin package has an invalid price configuration" }, 409, origin);
  }

  const { data: existing, error: existingError } = await admin
    .from("playam_payment_transactions")
    .select("id,provider_transaction_id,status,amount_minor,purchased_coin_amount,metadata")
    .eq("auth_user_id", user.id)
    .eq("provider", "paystack")
    .eq("idempotency_key", idempotencyKey)
    .maybeSingle();

  if (existingError) return reply({ error: "Payment request lookup is temporarily unavailable" }, 503, origin);
  if (existing) {
    if (existing.metadata?.package_code !== pkg.package_code ||
        Number(existing.amount_minor) !== Number(pkg.amount_minor) ||
        Number(existing.purchased_coin_amount) !== Number(pkg.coin_amount)) {
      return reply({ error: "This idempotency key was already used for a different package" }, 409, origin);
    }
    if (existing.status === "successful") {
      return reply({ error: "This payment has already been completed", payment_id: existing.id }, 409, origin);
    }
    if (["failed", "cancelled", "refunded"].includes(existing.status)) {
      return reply({ error: "This payment is no longer active. Start a new checkout request.", payment_id: existing.id }, 409, origin);
    }
    if (typeof existing.metadata?.authorization_url === "string") {
      return reply({
        ok: true, reused: true, payment_id: existing.id,
        reference: existing.provider_transaction_id,
        authorization_url: existing.metadata.authorization_url,
      }, 200, origin);
    }
    return reply({ error: "This payment request is already being prepared. Please check your wallet shortly.", payment_id: existing.id }, 409, origin);
  }

  const reference = "PLAYAM_COIN_" + crypto.randomUUID().replaceAll("-", "");
  const paymentMetadata = {
    package_code: pkg.package_code,
    package_name: pkg.display_name,
    package_amount_minor: Number(pkg.amount_minor),
    package_coin_amount: Number(pkg.coin_amount),
    coin_unit_price_minor: 10_000,
    pricing_version: "ngn-100-per-coin-v1",
    checkout_state: "initializing",
  };

  const { data: payment, error: insertError } = await admin
    .from("playam_payment_transactions")
    .insert({
      auth_user_id: user.id,
      provider: "paystack",
      provider_transaction_id: reference,
      amount_minor: Number(pkg.amount_minor),
      currency: "NGN",
      status: "pending",
      purchased_coin_amount: Number(pkg.coin_amount),
      idempotency_key: idempotencyKey,
      metadata: paymentMetadata,
    })
    .select("id")
    .single();

  if (insertError || !payment) {
    // A concurrent duplicate may have won the unique idempotency-key race.
    if (insertError?.code === "23505") {
      return reply({ error: "This payment request is already being prepared. Please retry shortly." }, 409, origin);
    }
    console.error("Coin checkout payment insert failed", insertError?.code ?? "unknown");
    return reply({ error: "Could not create the payment request" }, 503, origin);
  }

  let paystackResponse: any;
  try {
    const response = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + paystackKey,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: user.email,
        amount: Number(pkg.amount_minor),
        currency: "NGN",
        reference,
        callback_url: callback.toString(),
        metadata: {
          payment_id: payment.id,
          package_code: pkg.package_code,
          package_coin_amount: Number(pkg.coin_amount),
          pricing_version: "ngn-100-per-coin-v1",
        },
      }),
      signal: AbortSignal.timeout(15_000),
    });
    try { paystackResponse = await response.json(); } catch {
      throw new Error("PAYSTACK_UNREADABLE_RESPONSE");
    }
    if (!response.ok || paystackResponse?.status !== true ||
        paystackResponse?.data?.reference !== reference) {
      throw new Error("PAYSTACK_INITIALIZATION_FAILED");
    }
  } catch (error) {
    console.error("Coin checkout initialization did not complete", error instanceof Error ? error.message : "unknown");
    // Keep the pending record and reference for reconciliation; never mark it failed
    // when a network timeout could mean Paystack accepted the initialization.
    await admin.from("playam_payment_transactions").update({
      metadata: { ...paymentMetadata, checkout_state: "initialization_unknown" },
      updated_at: new Date().toISOString(),
    }).eq("id", payment.id);
    return reply({ error: "Paystack checkout could not be confirmed. Do not retry with a new payment request; contact support if this persists.", payment_id: payment.id }, 503, origin);
  }

  const authorizationUrl = paystackResponse?.data?.authorization_url;
  let parsedAuthorizationUrl: URL;
  try { parsedAuthorizationUrl = new URL(authorizationUrl); } catch {
    return reply({ error: "Paystack returned an invalid checkout link. Contact support before retrying.", payment_id: payment.id }, 502, origin);
  }
  if (parsedAuthorizationUrl.protocol !== "https:" || parsedAuthorizationUrl.hostname !== "checkout.paystack.com") {
    return reply({ error: "Paystack returned an unapproved checkout link. Contact support.", payment_id: payment.id }, 502, origin);
  }

  const { error: updateError } = await admin.from("playam_payment_transactions").update({
    metadata: {
      ...paymentMetadata,
      checkout_state: "initialized",
      authorization_url: authorizationUrl,
      access_code: typeof paystackResponse?.data?.access_code === "string" ? paystackResponse.data.access_code : null,
      initialized_at: new Date().toISOString(),
    },
    updated_at: new Date().toISOString(),
  }).eq("id", payment.id);

  if (updateError) {
    console.error("Coin checkout URL could not be saved", updateError.code ?? "unknown");
    return reply({ error: "Checkout was initialized but could not be safely saved. Contact support before retrying.", payment_id: payment.id }, 503, origin);
  }

  return reply({
    ok: true,
    payment_id: payment.id,
    reference,
    authorization_url: authorizationUrl,
  }, 201, origin);
});

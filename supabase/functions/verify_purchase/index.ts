// RaidersGo — vérification d'un achat intégré et crédit côté serveur.
// Entrée (POST, Authorization: Bearer <jeton joueur>) :
//   { store: "apple" | "google" | "simulated", product_id, transaction_id?, purchase_token? }
// Sortie : { ok, gems, entitlements, duplicate, product_id, kind } ou { ok:false, reason }.
// Règles :
//  - le catalogue `products` est la seule source des gemmes / droits accordés ;
//  - premier pack de gemmes du compte : gemmes × FIRST_PURCHASE_MULTIPLIER (défaut 2) ;
//  - "simulated" n'est accepté que si le secret ALLOW_SIMULATED_PURCHASES vaut "true"
//    (jamais sur un projet de production) ;
//  - un reçu rejoué ne crédite pas deux fois (grant_purchase est idempotent).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, json, userIdFrom } from "./shared.ts";
import { verifyAppleTransaction } from "./apple.ts";
import { verifyGooglePurchase } from "./google.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, reason: "method" }, 405);
  const admin = adminClient();
  const userId = await userIdFrom(req, admin);
  if (!userId) return json({ ok: false, reason: "unauthenticated" }, 401);

  let body: Record<string, string>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, reason: "bad_json" }, 400);
  }
  const store = String(body.store ?? "");
  let productId = String(body.product_id ?? "");
  let transactionId = "";
  let raw: Record<string, unknown> = {};

  try {
    if (store === "apple") {
      const tx = await verifyAppleTransaction(String(body.transaction_id ?? ""));
      productId = tx.productId;
      transactionId = tx.transactionId;
      raw = tx.raw;
    } else if (store === "google") {
      const tx = await verifyGooglePurchase(productId, String(body.purchase_token ?? ""));
      transactionId = tx.transactionId;
      raw = tx.raw;
    } else if (store === "simulated") {
      if (Deno.env.get("ALLOW_SIMULATED_PURCHASES") !== "true") {
        return json({ ok: false, reason: "simulated_disabled" }, 403);
      }
      transactionId = "sim-" + crypto.randomUUID();
      raw = { simulated: true, device: body.device ?? null };
    } else {
      return json({ ok: false, reason: "unknown_store" }, 400);
    }
  } catch (e) {
    return json({ ok: false, reason: "verification_failed", detail: String((e as Error).message) }, 402);
  }

  const { data: product, error: pe } = await admin.from("products").select("*")
    .eq("product_id", productId).eq("active", true).maybeSingle();
  if (pe || !product) return json({ ok: false, reason: "unknown_product", product_id: productId }, 400);

  let gems = Number(product.gems ?? 0);
  if (product.kind === "gems") {
    const { count } = await admin.from("purchases").select("id", { count: "exact", head: true })
      .eq("user_id", userId).like("product_id", "gems_%");
    if ((count ?? 0) === 0) gems *= Number(Deno.env.get("FIRST_PURCHASE_MULTIPLIER") ?? "2");
  }

  const { data: granted, error: ge } = await admin.rpc("grant_purchase", {
    p_user: userId,
    p_store: store,
    p_product: productId,
    p_transaction: transactionId,
    p_gems: gems,
    p_entitlements: product.entitlements ?? [],
    p_raw: raw,
  });
  if (ge) return json({ ok: false, reason: "grant_failed", detail: ge.message }, 500);
  if (!granted?.ok) return json({ ok: false, reason: granted?.reason ?? "grant_refused" }, 409);
  return json({
    ok: true,
    duplicate: Boolean(granted.duplicate),
    gems: Number(granted.gems ?? 0),
    entitlements: granted.entitlements ?? [],
    product_id: productId,
    kind: product.kind,
    transaction_id: transactionId,
  });
});

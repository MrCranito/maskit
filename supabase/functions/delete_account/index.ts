// RaidersGo — suppression du compte par le joueur (Apple 5.1.1(v), Google Play « Account deletion »).
// POST, Authorization: Bearer <jeton joueur>. Archive les achats anonymisés (comptabilité) puis
// supprime l'utilisateur : player_saves, purchases, entitlements, wallets, raid_logs partent en cascade.
// TODO quand Sign in with Apple sera configuré : révoquer les jetons Apple de l'utilisateur
// (POST https://appleid.apple.com/auth/revoke, client_id = bundle id, client_secret = JWT Apple).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, json, userIdFrom } from "./shared.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, reason: "method" }, 405);
  const admin = adminClient();
  const userId = await userIdFrom(req, admin);
  if (!userId) return json({ ok: false, reason: "unauthenticated" }, 401);

  const { data: purchases } = await admin.from("purchases")
    .select("id, store, product_id, transaction_id, gems_granted, created_at").eq("user_id", userId);
  if (purchases && purchases.length > 0) {
    const { error } = await admin.from("purchases_archive").upsert(purchases, { onConflict: "id", ignoreDuplicates: true });
    if (error) return json({ ok: false, reason: "archive_failed", detail: error.message }, 500);
  }
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) return json({ ok: false, reason: "delete_failed", detail: error.message }, 500);
  return json({ ok: true });
});

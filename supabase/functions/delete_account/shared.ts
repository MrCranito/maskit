// Outils communs aux Edge Functions RaidersGo : client service-role et identification du joueur
// à partir du jeton envoyé par le jeu (Authorization: Bearer <access_token>).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/** Identifiant du joueur authentifié, ou null. */
export async function userIdFrom(req: Request, admin: SupabaseClient): Promise<string | null> {
  const h = req.headers.get("Authorization") ?? "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : "";
  if (!token) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user.id;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Connection": "keep-alive" },
  });
}

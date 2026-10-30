// Vérification d'un achat Google Play via l'API Android Publisher.
// Secrets : GOOGLE_SERVICE_ACCOUNT_JSON (compte de service avec accès « Afficher les données
// financières » sur l'app dans la Play Console), GOOGLE_PACKAGE_NAME (com.mrcranito.raidersgo).
// Le jeu envoie le productId et le purchaseToken ; on relit l'achat chez Google et on l'acquitte.
import * as jose from "npm:jose@5";

export interface VerifiedTx {
  transactionId: string;
  productId: string;
  environment: string;
  raw: Record<string, unknown>;
}

async function accessToken(): Promise<string> {
  const sa = JSON.parse(Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON")!);
  const pk = await jose.importPKCS8(sa.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new jose.SignJWT({ scope: "https://www.googleapis.com/auth/androidpublisher" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email).setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now).setExpirationTime(now + 600)
    .sign(pk);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`Google OAuth ${res.status}`);
  return (await res.json()).access_token;
}

export async function verifyGooglePurchase(productId: string, purchaseToken: string): Promise<VerifiedTx> {
  if (!productId || !purchaseToken) throw new Error("productId / purchaseToken manquants");
  const pkg = Deno.env.get("GOOGLE_PACKAGE_NAME")!;
  const token = await accessToken();
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/purchases/products/${
    encodeURIComponent(productId)
  }/tokens/${encodeURIComponent(purchaseToken)}`;
  const res = await fetch(base, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`Android Publisher ${res.status}`);
  const p = await res.json();
  // purchaseState : 0 = acheté, 1 = annulé, 2 = en attente.
  if (p.purchaseState !== 0) throw new Error("achat non finalisé");
  if (p.purchaseType === 0 && Deno.env.get("GOOGLE_ALLOW_TEST") !== "true") {
    throw new Error("achat de test refusé");
  }
  if (p.acknowledgementState === 0) {
    await fetch(`${base}:acknowledge`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: "{}",
    });
  }
  return {
    transactionId: String(p.orderId ?? purchaseToken),
    productId,
    environment: p.purchaseType === 0 ? "Test" : "Production",
    raw: p,
  };
}

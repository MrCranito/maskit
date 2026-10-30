// Vérification d'une transaction App Store (StoreKit 2) via l'App Store Server API.
// Secrets : APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (contenu du .p8), APPLE_BUNDLE_ID.
// Le jeu envoie l'identifiant de transaction ; on relit la transaction signée chez Apple
// (JWS) et on vérifie sa signature et sa chaîne (racine Apple Root CA - G3).
import * as jose from "npm:jose@5";

const PROD = "https://api.storekit.itunes.apple.com";
const SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";
// Empreinte SHA-256 du certificat Apple Root CA - G3 (DER).
const APPLE_ROOT_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

export interface VerifiedTx {
  transactionId: string;
  productId: string;
  environment: string;
  raw: Record<string, unknown>;
}

async function serverToken(): Promise<string> {
  const pk = await jose.importPKCS8(Deno.env.get("APPLE_PRIVATE_KEY")!.replace(/\\n/g, "\n"), "ES256");
  const now = Math.floor(Date.now() / 1000);
  return await new jose.SignJWT({ bid: Deno.env.get("APPLE_BUNDLE_ID")! })
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APPLE_KEY_ID")!, typ: "JWT" })
    .setIssuer(Deno.env.get("APPLE_ISSUER_ID")!)
    .setIssuedAt(now).setExpirationTime(now + 600)
    .setAudience("appstoreconnect-v1")
    .sign(pk);
}

function pem(der: string): string {
  return `-----BEGIN CERTIFICATE-----\n${der.match(/.{1,64}/g)!.join("\n")}\n-----END CERTIFICATE-----`;
}

async function sha256Hex(b64: string): Promise<string> {
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const h = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(h)).map((x) => x.toString(16).padStart(2, "0")).join("");
}

/** Vérifie la signature d'un JWS Apple (x5c) et que la chaîne remonte à Apple Root CA - G3. */
export async function verifySignedPayload(jws: string): Promise<Record<string, unknown>> {
  const header = jose.decodeProtectedHeader(jws);
  const chain = header.x5c as string[] | undefined;
  if (!chain || chain.length < 2) throw new Error("x5c manquant");
  const rootHash = await sha256Hex(chain[chain.length - 1]);
  if (rootHash !== APPLE_ROOT_G3_SHA256) throw new Error("racine inconnue");
  const leaf = await jose.importX509(pem(chain[0]), header.alg as string);
  const { payload } = await jose.compactVerify(jws, leaf);
  return JSON.parse(new TextDecoder().decode(payload));
}

export async function verifyAppleTransaction(transactionId: string): Promise<VerifiedTx> {
  if (!/^\d+$/.test(transactionId)) throw new Error("transactionId invalide");
  const token = await serverToken();
  let res = await fetch(`${PROD}/inApps/v1/transactions/${transactionId}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) {
    res = await fetch(`${SANDBOX}/inApps/v1/transactions/${transactionId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
  }
  if (!res.ok) throw new Error(`App Store Server API ${res.status}`);
  const body = await res.json();
  const tx = await verifySignedPayload(body.signedTransactionInfo);
  if (tx.bundleId !== Deno.env.get("APPLE_BUNDLE_ID")) throw new Error("bundleId inattendu");
  if (tx.revocationDate) throw new Error("transaction remboursée");
  if (tx.environment === "Sandbox" && Deno.env.get("APPLE_ALLOW_SANDBOX") !== "true") {
    throw new Error("transaction sandbox refusée");
  }
  return {
    transactionId: String(tx.transactionId),
    productId: String(tx.productId),
    environment: String(tx.environment),
    raw: tx,
  };
}

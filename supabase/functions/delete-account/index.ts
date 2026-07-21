// delete-account
//
// Required by Apple's "account deletion" guideline (5.1.1(v)). Called from
// Settings → "delete account". Cascades everything owned by the caller and
// finally deletes the auth user itself so no orphaned row can identify them.
//
// Order matters:
//   1. Delete owned rows (meal_corrections, app_feedback, meals cascades
//      to meal_items, daily_checkins, health_days, insights). The
//      `on delete cascade` FKs to auth.users MEAN step 2 alone would do
//      the cleanup — but doing it explicitly here gives us a clear error
//      surface if a future table forgot to add the FK.
//   2. Delete the auth.users row via admin API. Only the service role
//      can do this; that's why this must be an Edge Function.
//
// Contract (request): { authorization_code?: string } (auth via bearer
//   token — the user we delete is always the caller; the optional code
//   is a fresh SIWA authorization code used for best-effort token
//   revocation, see below).
// Contract (success 204): empty body.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

function empty(status: number): Response {
  return new Response(null, { status });
}

// ─── Sign in with Apple token revocation ────────────────────────────────────
// Apple requires apps that use SIWA to revoke the user's token when their
// account is deleted. The client sends a fresh single-use authorization
// code; we exchange it for a refresh token and revoke that. Best-effort:
// any failure here must never block the actual deletion.
//
// Requires secrets (all four, else silently skipped):
//   APPLE_CLIENT_ID    — the app's bundle id (com.pranavsurampudi.soma)
//   APPLE_TEAM_ID      — 10-char developer team id
//   APPLE_KEY_ID       — key id of the SIWA .p8 key
//   APPLE_PRIVATE_KEY  — the .p8 PEM contents

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlJSON(obj: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function appleClientSecret(
  teamId: string,
  keyId: string,
  clientId: string,
  privateKeyPem: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const signingInput =
    base64urlJSON({ alg: "ES256", kid: keyId }) + "." +
    base64urlJSON({
      iss: teamId,
      iat: now,
      exp: now + 300,
      aud: "https://appleid.apple.com",
      sub: clientId,
    });
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto ECDSA emits the raw r||s form JWS ES256 expects.
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(sig))}`;
}

async function revokeAppleToken(authorizationCode: string): Promise<void> {
  const clientId = Deno.env.get("APPLE_CLIENT_ID");
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!clientId || !teamId || !keyId || !privateKey) return;

  const clientSecret = await appleClientSecret(teamId, keyId, clientId, privateKey);
  const form = (params: Record<string, string>) =>
    new URLSearchParams(params).toString();
  const headers = { "content-type": "application/x-www-form-urlencoded" };

  const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers,
    body: form({
      client_id: clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenRes.ok) return;
  const tokens: { refresh_token?: string } = await tokenRes.json();
  if (!tokens.refresh_token) return;

  await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers,
    body: form({
      client_id: clientId,
      client_secret: clientSecret,
      token: tokens.refresh_token,
      token_type_hint: "refresh_token",
    }),
  });
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "missing_bearer" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return json(401, { error: "unauthorized" });
  const userId = userData.user.id;

  // Optional body: { authorization_code } for SIWA token revocation.
  let authorizationCode: string | null = null;
  try {
    const body = await req.json();
    if (typeof body?.authorization_code === "string") {
      authorizationCode = body.authorization_code;
    }
  } catch {
    // Empty/invalid body is fine — revocation is best-effort.
  }
  if (authorizationCode) {
    try {
      await revokeAppleToken(authorizationCode);
    } catch (e) {
      console.error("apple_revoke_failed", e);
    }
  }

  const admin = createClient(supabaseUrl, serviceKey);

  // Explicit deletes for clarity + error surface. Order is dependency-
  // safe: meal_items and meal_corrections reference meals; delete those
  // (or let cascade handle it) before meals themselves.
  const tables = [
    "meal_items",
    "meal_corrections",
    "app_feedback",
    "insights",
    "daily_checkins",
    "health_days",
    "meals",
  ];
  for (const table of tables) {
    // .neq('id', '00000000-...') is unnecessary — RLS + user_id filter is enough.
    await admin.from(table).delete().eq("user_id", userId);
  }

  // Finally, remove the auth user. This invalidates their sessions and
  // frees their Apple sub for a re-sign-up.
  const { error: delErr } = await admin.auth.admin.deleteUser(userId);
  if (delErr) return json(500, { error: "auth_delete_failed", detail: delErr.message });

  return empty(204);
});

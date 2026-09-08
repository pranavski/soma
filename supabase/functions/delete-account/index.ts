// delete-account
//
// Required by Apple's "account deletion" guideline (5.1.1(v)). Called from
// Settings → "delete account". Cascades everything owned by the caller and
// finally deletes the auth user itself so no orphaned row can identify them.
//
// Order matters:
//   1. Purge the caller's storage objects. Storage rows do not cascade
//      from auth.users, so this is the one step nothing else would do.
//   2. Delete owned rows in every user-keyed table (the list below). The
//      `on delete cascade` FKs to auth.users MEAN step 3 alone would do
//      the cleanup — but doing it explicitly here gives us a clear error
//      surface if a future table forgot to add the FK. Keep the list in
//      step with the schema: a table missing here is a table whose
//      deletion is trusted to a cascade nobody has checked.
//   3. Delete the auth.users row via admin API. Only the service role
//      can do this; that's why this must be an Edge Function.
//
// Contract (request): { authorization_code?: string } (auth via bearer
//   token — the user we delete is always the caller; the optional code
//   is a fresh SIWA authorization code used for best-effort token
//   revocation, see below).
// Contract (success 204): empty body.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.0";

function empty(status: number): Response {
  return new Response(null, { status });
}

// ─── Sign in with Apple token revocation ────────────────────────────────────
// Apple requires apps that use SIWA to revoke the user's token when their
// account is deleted. The client sends a fresh single-use authorization
// code; we exchange it for a refresh token and revoke that. Best-effort:
// any failure here must never block the actual deletion.
//
// Requires secrets — all four, or revocation is skipped (loudly: an
// incomplete config is an operator mistake, and App Review does test
// deletion on SIWA apps, so it must not disappear into a silent return):
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

function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  // Backed by a plain ArrayBuffer so WebCrypto's BufferSource type is
  // satisfied under Deno 2's stricter typed-array generics.
  const out = new Uint8Array(new ArrayBuffer(bin.length));
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

  // The guard stays one expression so the four stay narrowed below; the
  // log names only which secrets are absent, never a value. A partial
  // config is the dangerous case — it looks configured from the dashboard
  // and revokes nothing.
  if (!clientId || !teamId || !keyId || !privateKey) {
    const missing = [
      ["APPLE_CLIENT_ID", clientId],
      ["APPLE_TEAM_ID", teamId],
      ["APPLE_KEY_ID", keyId],
      ["APPLE_PRIVATE_KEY", privateKey],
    ].filter(([, value]) => !value).map(([name]) => name);
    console.error(
      `delete-account: Apple token revocation SKIPPED — missing secrets: ${missing.join(", ")}. ` +
      "The account and its rows are still deleted, but Apple is not told. " +
      "See docs/deployment-checklist.md §2.",
    );
    return;
  }

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

const PHOTO_BUCKET = "meal-photos";

/// Remove every object under `<user_id>/` in the private photo bucket.
/// Best-effort and paged: a failure here is logged, never fatal, because
/// the account deletion itself must not hang on an empty folder listing.
async function purgeStorage(
  admin: SupabaseClient,
  userId: string,
): Promise<void> {
  const bucket = admin.storage.from(PHOTO_BUCKET);
  const pageSize = 100;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await bucket.list(userId, { limit: pageSize, offset });
    if (error) {
      console.error(`delete-account: storage list failed — ${error.message}`);
      return;
    }
    const paths = (data ?? [])
      .filter((o) => typeof o.name === "string" && o.name.length > 0)
      .map((o) => `${userId}/${o.name}`);
    if (paths.length === 0) return;
    const { error: rmErr } = await bucket.remove(paths);
    if (rmErr) {
      console.error(`delete-account: storage remove failed — ${rmErr.message}`);
      return;
    }
    if (paths.length < pageSize) return;
    // Removed objects fall out of the listing, so re-list from the start.
    offset = -pageSize;
  }
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

  // Storage first. The meal-photos bucket is owner-scoped by the first
  // path segment (<user_id>/...), and storage.objects has no FK to
  // auth.users, so without this step a deleted account's photos would
  // outlive it. Photo logging is not in this version, so the folder is
  // usually empty — the purge is still the only thing that guarantees it.
  await purgeStorage(admin, userId);

  // Explicit deletes for clarity + error surface. Order is dependency-
  // safe: meal_items and meal_corrections reference meals; delete those
  // (or let cascade handle it) before meals themselves.
  const tables = [
    "meal_items",
    "meal_corrections",
    "app_feedback",
    "insights",
    "pattern_history",
    "reflections",
    "insight_runs",
    "daily_checkins",
    "health_days",
    "meals",
  ];
  for (const table of tables) {
    // .neq('id', '00000000-...') is unnecessary — RLS + user_id filter is enough.
    const { error } = await admin.from(table).delete().eq("user_id", userId);
    if (error) {
      // Surface, don't abort: the auth delete below cascades everything
      // with an FK, and a stuck row is better logged than left behind
      // with the account still alive.
      console.error(`delete-account: ${table} delete failed — ${error.message}`);
    }
  }

  // Finally, remove the auth user. This invalidates their sessions and
  // frees their Apple sub for a re-sign-up.
  const { error: delErr } = await admin.auth.admin.deleteUser(userId);
  if (delErr) return json(500, { error: "auth_delete_failed", detail: delErr.message });

  return empty(204);
});

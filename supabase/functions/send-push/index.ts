// send-push (D-52): sends the rows waiting in public.push_outbox through Firebase Cloud Messaging (HTTP v1).
// Called by the database (pg_net trigger after an insert, and a pg_cron retry every minute) with the shared
// secret in the x-push-secret header. Firebase stays on the free Spark plan: FCM needs no Blaze.
//
// Secrets (supabase secrets set …, never in git):
//   PUSH_SECRET            same value as the Vault secret "push_secret"
//   FCM_SERVICE_ACCOUNT    the Firebase service account JSON of asani-b2b17, base64-encoded
// Provided by Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface OutboxRow {
  id: number;
  user_id: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  attempts: number;
  devices: { deviceId: string; token: string; platform: string }[];
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PUSH_SECRET = Deno.env.get('PUSH_SECRET') ?? '';

// ------------------------------------------------------------------ Google access token (cached ~55 min)
let cached: { token: string; until: number } | null = null;
let account: ServiceAccount | null = null;

function serviceAccount(): ServiceAccount {
  if (!account) {
    // Stored base64-encoded (no quotes or newlines for the env file to mangle); plain JSON also works.
    const raw = (Deno.env.get('FCM_SERVICE_ACCOUNT') ?? '').trim();
    account = JSON.parse(raw.startsWith('{') ? raw : new TextDecoder().decode(Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)))) as ServiceAccount;
  }
  if (!account.project_id || !account.private_key) throw new Error('FCM_SERVICE_ACCOUNT secret is missing');
  return account;
}

const b64url = (bytes: Uint8Array | string) => {
  const s = typeof bytes === 'string' ? btoa(bytes) : btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

async function accessToken(): Promise<string> {
  if (cached && cached.until > Date.now()) return cached.token;
  const sa = serviceAccount();
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`)));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claims}.${b64url(sig)}`,
    }),
  });
  if (!res.ok) throw new Error(`google token ${res.status}: ${await res.text()}`);
  const json = await res.json();
  cached = { token: json.access_token, until: Date.now() + 55 * 60 * 1000 };
  return cached.token;
}

// ------------------------------------------------------------------ database (service role, RPC only)
async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`${fn} ${res.status}: ${await res.text()}`);
  const text = await res.text();
  return (text ? JSON.parse(text) : null) as T;
}

// ------------------------------------------------------------------ FCM
type SendResult = 'ok' | 'dead' | 'retry';

/**
 * Which FCM target field a saved device value needs. Apps now save a Firebase Installation ID (22 characters);
 * older installs saved a registration token (much longer, with a ":"). `fcm_token` holds either.
 */
function target(value: string): { fid: string } | { token: string } {
  return /^[A-Za-z0-9_-]{22}$/.test(value) ? { fid: value } : { token: value };
}

/** Android channel per type (same as the Firebase functions): follow-ups have their own channel. */
function channelFor(type: string): string {
  return type === 'followUp' ? 'follow_ups' : 'queue_alerts';
}

async function sendOne(row: OutboxRow, deviceToken: string): Promise<{ result: SendResult; error?: string }> {
  const sa = serviceAccount();
  const type = String(row.data.type ?? 'queue');
  // FCM data values must be strings.
  const data = Object.fromEntries(Object.entries(row.data).map(([k, v]) => [k, typeof v === 'string' ? v : JSON.stringify(v)]));
  const tag = typeof row.data.tokenId === 'string' ? row.data.tokenId : undefined;
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await accessToken()}` },
    body: JSON.stringify({
      message: {
        ...target(deviceToken),
        notification: { title: row.title, body: row.body },
        data,
        android: { priority: 'HIGH', notification: { channel_id: channelFor(type), ...(tag ? { tag } : {}) } },
        apns: { payload: { aps: { sound: 'default' } } },
      },
    }),
  });
  if (res.ok) return { result: 'ok' };
  const text = await res.text();
  // The phone uninstalled the app or the token changed: delete the device (replaces cleanupStaleDevices).
  if (res.status === 404 || /UNREGISTERED|registration token is not a valid/i.test(text)) return { result: 'dead', error: text };
  // Any other 400 means our message is wrong: keep the device, retry a few times, then give up (last_error shows why).
  return { result: 'retry', error: `${res.status}: ${text.slice(0, 300)}` };
}

async function processBatch(): Promise<{ claimed: number; sent: number; failed: number }> {
  const rows = await rpc<OutboxRow[]>('claim_push_batch', { p_limit: 50 });
  let sent = 0;
  let failed = 0;
  for (const row of rows ?? []) {
    const dead: string[] = [];
    let retryError: string | null = null;
    for (const d of row.devices) {
      try {
        const r = await sendOne(row, d.token);
        if (r.result === 'ok') sent++;
        else if (r.result === 'dead') dead.push(d.token);
        else retryError = r.error ?? 'retry';
      } catch (e) {
        retryError = String(e);
      }
    }
    // No devices is not an error: the entry is already in the in-app list (D-45).
    if (retryError) failed++;
    await rpc('finish_push', { p_id: row.id, p_error: retryError, p_dead_tokens: dead });
  }
  return { claimed: rows?.length ?? 0, sent, failed };
}

function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });
  if (!sameSecret(req.headers.get('x-push-secret') ?? '', PUSH_SECRET)) return new Response('forbidden', { status: 403 });
  try {
    const total = { claimed: 0, sent: 0, failed: 0 };
    for (let i = 0; i < 5; i++) {
      const r = await processBatch();
      total.claimed += r.claimed;
      total.sent += r.sent;
      total.failed += r.failed;
      if (r.claimed < 50) break;
    }
    return Response.json(total);
  } catch (e) {
    console.error('send-push', e);
    return Response.json({ error: String(e) }, { status: 500 });
  }
});

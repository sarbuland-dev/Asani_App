// admin-clinic-login (D-52, phase 6): the Super Admin's clinic-login actions that need the Auth admin API.
//   create  (A-04): clinic + billing (SQL svc_create_clinic) → invite email → app_metadata {role: clinic, clinic_id}
//                   → clinic_accounts row. Anything that fails undoes what was made, so no login without a clinic.
//   resend  (A-03): sends a "set your password" email again.
//   disable / enable (A-03): bans / unbans the login (it cannot sign in or refresh; current access tokens expire
//                   within the hour).
// Caller: a signed-in Super Admin (app_metadata.role = superAdmin), checked here from their JWT.
// Body: {action: 'create', clinic: {...A-04 fields, email, lat, lng}} | {action: 'resend'|'disable'|'enable', clinicId}.
// Errors: {error: code, message}; codes: unauthenticated, permission-denied, invalid-argument, email-taken, not-found, failed.
//
// Secrets: CLINIC_WEB_URL (the clinic web's address, e.g. http://localhost:8092). That URL must be in
// Auth → URL Configuration → Redirect URLs. Provided by Supabase: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WEB_URL = (Deno.env.get('CLINIC_WEB_URL') ?? 'http://localhost:8092').replace(/\/$/, '');
// The web uses #/ routes and reads the invite / reset link on its root page, then shows #/set-password.
const SET_PASSWORD = `${WEB_URL}/`;
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const fail = (status: number, error: string, message: string) => reply(status, { error, message });

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

/** Postgres raises the code as the message and the text as the hint (docs/10 §6b). */
function dbError(e: { message?: string; hint?: string } | null) {
  return fail(400, e?.message ?? 'failed', e?.hint ?? e?.message ?? 'Something went wrong.');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return fail(405, 'invalid-argument', 'POST only.');

  // ---- who is calling
  const auth = req.headers.get('Authorization') ?? '';
  const caller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: who, error: whoErr } = await caller.auth.getUser();
  if (whoErr || !who.user) return fail(401, 'unauthenticated', 'Please log in again.');
  if (who.user.app_metadata?.role !== 'superAdmin') return fail(403, 'permission-denied', 'Super admin only.');
  const actor = who.user.id;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail(400, 'invalid-argument', 'Send JSON.');
  }
  const action = String(body.action ?? '');

  // ---- A-04 new clinic + its login
  if (action === 'create') {
    const c = (body.clinic ?? {}) as Record<string, unknown>;
    const email = String(c.email ?? '').trim().toLowerCase();
    if (!EMAIL.test(email) || email.length > 120) return fail(400, 'invalid-argument', 'Enter a valid clinic email.');

    const made = await admin.rpc('svc_create_clinic', { p: { ...c, email }, p_actor: actor });
    if (made.error) return dbError(made.error);
    const clinicId = (made.data as { clinicId: string }).clinicId;

    const invited = await admin.auth.admin.inviteUserByEmail(email, {
      redirectTo: SET_PASSWORD,
      data: { name: String(c.name ?? '') },
    });
    if (invited.error || !invited.data.user) {
      await admin.rpc('svc_delete_new_clinic', { p_clinic_id: clinicId });
      const taken = /already (been )?registered|already exists/i.test(invited.error?.message ?? '');
      return taken
        ? fail(409, 'email-taken', 'An account with this email already exists.')
        : fail(500, 'failed', `Could not send the invite: ${invited.error?.message ?? 'unknown error'}`);
    }
    const uid = invited.data.user.id;

    const roled = await admin.auth.admin.updateUserById(uid, { app_metadata: { role: 'clinic', clinic_id: clinicId } });
    const attached = roled.error
      ? { error: roled.error }
      : await admin.rpc('svc_attach_clinic_login', {
          p_clinic_id: clinicId,
          p_uid: uid,
          p_email: email,
          p_name: String(c.ownerName ?? ''),
          p_actor: actor,
        });
    if (attached.error) {
      await admin.auth.admin.deleteUser(uid);
      await admin.rpc('svc_delete_new_clinic', { p_clinic_id: clinicId });
      return fail(500, 'failed', `Could not finish the clinic login: ${attached.error.message}`);
    }
    return reply(200, { clinicId, email });
  }

  // ---- A-03 resend / disable / enable
  if (action === 'resend' || action === 'disable' || action === 'enable') {
    const clinicId = String(body.clinicId ?? '');
    if (!clinicId) return fail(400, 'invalid-argument', 'clinicId is required.');
    const ev = await admin.rpc('svc_clinic_login_event', { p_clinic_id: clinicId, p_event: action, p_actor: actor });
    if (ev.error) return dbError(ev.error);
    const { uid, email } = ev.data as { uid: string; email: string };

    const res =
      action === 'resend'
        ? await admin.auth.resetPasswordForEmail(email, { redirectTo: SET_PASSWORD })
        : await admin.auth.admin.updateUserById(uid, { ban_duration: action === 'disable' ? '876000h' : 'none' });
    if (res.error) return fail(500, 'failed', res.error.message);
    return reply(200, { ok: true, email });
  }

  return fail(400, 'invalid-argument', 'Unknown action.');
});

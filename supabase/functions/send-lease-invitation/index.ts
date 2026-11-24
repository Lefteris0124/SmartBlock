import { createClient } from 'npm:@supabase/supabase-js@2';

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('Origin') ?? '';
  const allowedOrigins = new Set(['https://lefteris0124.github.io', 'http://localhost:8080', 'http://localhost:5000', 'http://127.0.0.1:8080']);
  const cors = {
    'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://lefteris0124.github.io',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const authHeader = req.headers.get('Authorization') ?? '';
    const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authError } = await caller.auth.getUser();
    if (authError || !user) return Response.json({ error: 'Sign in required.' }, { status: 401, headers: cors });

    const { offer_id, token } = await req.json();
    if (typeof offer_id !== 'string' || typeof token !== 'string' || token.length < 32) {
      return Response.json({ error: 'Invalid invitation.' }, { status: 400, headers: cors });
    }
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: offer, error: offerError } = await admin.from('lease_contract_offers')
      .select('id,owner_user_id,owner_email,tenant_email,invite_token_sha256,status,invite_expires_at')
      .eq('id', offer_id).maybeSingle();
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
    const tokenHash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
    if (offerError || !offer || offer.owner_user_id !== user.id || offer.invite_token_sha256 !== tokenHash || offer.status !== 'awaiting_tenant' || new Date(offer.invite_expires_at) <= new Date()) {
      return Response.json({ error: 'Invitation could not be verified.' }, { status: 403, headers: cors });
    }
    const redirectTo = `https://lefteris0124.github.io/SmartBlock/?lease_token=${encodeURIComponent(token)}`;
    const invitation = await admin.auth.admin.inviteUserByEmail(offer.tenant_email, { redirectTo });
    if (!invitation.error) return Response.json({ sent: true }, { headers: cors });

    // Existing registered tenants receive a sign-in link instead of a second account.
    const otp = await caller.auth.signInWithOtp({ email: offer.tenant_email, options: { emailRedirectTo: redirectTo, shouldCreateUser: false } });
    if (otp.error) return Response.json({ error: `Email could not be sent: ${otp.error.message}` }, { status: 502, headers: cors });
    return Response.json({ sent: true, existing_account: true }, { headers: cors });
  } catch (e) {
    return Response.json({ error: e instanceof Error ? e.message : 'Unexpected invitation error.' }, { status: 500, headers: cors });
  }
});


import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishableKey || !serviceRoleKey) {
    return json({ error: "Trial service is not configured." }, 503);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Administrator sign-in required." }, 401);

  const callerClient = createClient(url, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const serviceClient = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: callerData, error: callerError } = await callerClient.auth.getUser(token);
  if (callerError || !callerData.user) return json({ error: "Your session is no longer valid." }, 401);

  const { data: staff, error: staffError } = await serviceClient
    .from("smartblock_staff")
    .select("is_active,staff_role")
    .eq("user_id", callerData.user.id)
    .maybeSingle();
  if (staffError || !staff?.is_active || staff.staff_role !== "admin") {
    return json({ error: "Only an active SmartBlock administrator can start a trial." }, 403);
  }

  let role: string;
  try {
    const body = await request.json();
    role = body?.role;
  } catch {
    return json({ error: "Choose owner or tenant." }, 400);
  }
  if (role !== "owner" && role !== "tenant") return json({ error: "Choose owner or tenant." }, 400);

  const isOwner = role === "owner";
  const email = isOwner
    ? "smartblock.trial.owner@smartblock.invalid"
    : "smartblock.trial.tenant@smartblock.invalid";
  const fullName = isOwner ? "SmartBlock Trial Owner" : "SmartBlock Trial Tenant";
  const requestedRoles = isOwner ? ["property_owner"] : ["tenant"];
  let trialUserId: string;

  const { data: usersPage, error: listError } = await serviceClient.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (listError) return json({ error: "Could not prepare the trial account." }, 500);
  const existing = usersPage.users.find((user) => user.email?.toLowerCase() === email);
  const password = `${crypto.randomUUID()}-${crypto.randomUUID()}Aa1!`;
  const metadata = { smartblock_trial: true, smartblock_trial_role: role };

  if (existing) {
    trialUserId = existing.id;
    const { error } = await serviceClient.auth.admin.updateUserById(existing.id, {
      password,
      email_confirm: true,
      app_metadata: metadata,
      user_metadata: { ...(existing.user_metadata ?? {}), full_name: fullName, requested_roles: requestedRoles },
    });
    if (error) return json({ error: "Could not refresh the trial account." }, 500);
  } else {
    const { data, error } = await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      app_metadata: metadata,
      user_metadata: { full_name: fullName, requested_roles: requestedRoles },
    });
    if (error || !data.user) return json({ error: "Could not create the trial account." }, 500);
    trialUserId = data.user.id;
  }

  const ownerId = isOwner
    ? trialUserId
    : await ensureOtherTrialAccount(serviceClient, "owner");
  const tenantId = isOwner
    ? await ensureOtherTrialAccount(serviceClient, "tenant")
    : trialUserId;
  if (!ownerId || !tenantId) return json({ error: "Could not prepare both trial roles." }, 500);

  const { data: fixture, error: fixtureError } = await serviceClient.rpc("smartblock_admin_ensure_trial_fixture", {
    p_owner_user_id: ownerId,
    p_tenant_user_id: tenantId,
  });
  if (fixtureError) {
    console.error("Trial fixture setup failed:", fixtureError.message);
    return json({ error: "Could not prepare the trial building. Please try again shortly." }, 500);
  }

  const propertyId = fixture?.property_id as string | undefined;
  if (!propertyId) return json({ error: "Trial building was not returned." }, 500);
  const sampleDueDate = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const [chargeUpdate, contracts] = await Promise.all([
    serviceClient.from("property_charge_runs")
      .update({ due_date: sampleDueDate })
      .eq("property_id", propertyId)
      .eq("period_label", "SmartBlock Trial Common Charges"),
    serviceClient.from("property_rent_contracts")
      .select("id")
      .eq("property_id", propertyId)
      .eq("unit_reference", "2")
      .eq("tenant_name", "SmartBlock Trial Tenant"),
  ]);
  if (chargeUpdate.error || contracts.error) {
    console.error("Could not refresh trial due dates:", chargeUpdate.error?.message ?? contracts.error?.message);
    return json({ error: "Could not finish the trial setup." }, 500);
  }
  const contractIds = (contracts.data ?? []).map((contract) => contract.id as string);
  if (contractIds.length) {
    const { error } = await serviceClient.from("property_rent_installments")
      .update({ due_date: sampleDueDate })
      .in("contract_id", contractIds);
    if (error) {
      console.error("Could not refresh trial rent due dates:", error.message);
      return json({ error: "Could not finish the trial setup." }, 500);
    }
  }

  const loginClient = createClient(url, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: loginData, error: loginError } = await loginClient.auth.signInWithPassword({ email, password });
  if (loginError || !loginData.session) return json({ error: "Could not start the trial session." }, 500);

  return json({
    access_token: loginData.session.access_token,
    refresh_token: loginData.session.refresh_token,
    expires_in: loginData.session.expires_in,
    token_type: loginData.session.token_type,
    role,
  });
});

async function ensureOtherTrialAccount(client: ReturnType<typeof createClient>, role: "owner" | "tenant"): Promise<string | null> {
  const isOwner = role === "owner";
  const email = isOwner
    ? "smartblock.trial.owner@smartblock.invalid"
    : "smartblock.trial.tenant@smartblock.invalid";
  const fullName = isOwner ? "SmartBlock Trial Owner" : "SmartBlock Trial Tenant";
  const requestedRoles = isOwner ? ["property_owner"] : ["tenant"];
  const { data, error } = await client.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (error) return null;
  const existing = data.users.find((user) => user.email?.toLowerCase() === email);
  const password = `${crypto.randomUUID()}-${crypto.randomUUID()}Aa1!`;
  const appMetadata = { smartblock_trial: true, smartblock_trial_role: role };
  if (existing) {
    const { error: updateError } = await client.auth.admin.updateUserById(existing.id, {
      password,
      email_confirm: true,
      app_metadata: appMetadata,
      user_metadata: { ...(existing.user_metadata ?? {}), full_name: fullName, requested_roles: requestedRoles },
    });
    return updateError ? null : existing.id;
  }
  const { data: created, error: createError } = await client.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: appMetadata,
    user_metadata: { full_name: fullName, requested_roles: requestedRoles },
  });
  return createError ? null : created.user?.id ?? null;
}
\n
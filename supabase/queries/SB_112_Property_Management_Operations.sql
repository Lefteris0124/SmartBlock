-- Property management operations for SmartBlock.
-- Contract terms are stored per property/contract and are not treated as general legal rules.
BEGIN;

ALTER TABLE public.property_charge_runs
  ADD COLUMN IF NOT EXISTS billing_cycle text NOT NULL DEFAULT 'monthly';
ALTER TABLE public.property_charge_runs
  DROP CONSTRAINT IF EXISTS property_charge_runs_billing_cycle_check;
ALTER TABLE public.property_charge_runs
  ADD CONSTRAINT property_charge_runs_billing_cycle_check
  CHECK (billing_cycle IN ('monthly','quarterly','semiannual','annual','custom'));

CREATE TABLE IF NOT EXISTS public.property_management_contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  provider_name text NOT NULL CHECK (length(btrim(provider_name)) BETWEEN 2 AND 200),
  contract_reference text,
  starts_on date NOT NULL,
  ends_on date,
  monthly_fee numeric(12,2) NOT NULL CHECK (monthly_fee >= 0),
  vat_rate numeric(5,2) NOT NULL DEFAULT 0 CHECK (vat_rate BETWEEN 0 AND 100),
  billing_cycle text NOT NULL DEFAULT 'monthly'
    CHECK (billing_cycle IN ('monthly','quarterly','semiannual','annual','custom')),
  auto_renew boolean NOT NULL DEFAULT false,
  notice_period_months integer NOT NULL DEFAULT 0 CHECK (notice_period_months BETWEEN 0 AND 36),
  termination_approval_percent numeric(5,2) CHECK (termination_approval_percent BETWEEN 0 AND 100),
  termination_compensation_months numeric(6,2) CHECK (termination_compensation_months >= 0),
  pause_payments_if_fund_deficit boolean NOT NULL DEFAULT false,
  terms_summary text NOT NULL DEFAULT '',
  source_document_path text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','expired','terminated')),
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_on IS NULL OR ends_on >= starts_on)
);
CREATE INDEX IF NOT EXISTS property_management_contracts_property_idx
  ON public.property_management_contracts(property_id, starts_on DESC);

CREATE TABLE IF NOT EXISTS public.property_management_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  contract_id uuid REFERENCES public.property_management_contracts(id) ON DELETE SET NULL,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 200),
  description text NOT NULL DEFAULT '',
  fee_amount numeric(12,2) CHECK (fee_amount >= 0),
  fee_unit text NOT NULL DEFAULT 'fixed'
    CHECK (fee_unit IN ('fixed','per_hour','per_visit','per_letter','quote_required')),
  requires_prior_approval boolean NOT NULL DEFAULT true,
  active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS property_management_services_property_idx
  ON public.property_management_services(property_id, active, title);

CREATE TABLE IF NOT EXISTS public.property_operating_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  service_id uuid REFERENCES public.property_management_services(id) ON DELETE SET NULL,
  category text NOT NULL DEFAULT 'other',
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 2 AND 500),
  supplier text,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  currency text NOT NULL DEFAULT 'EUR' CHECK (currency = 'EUR'),
  expense_date date NOT NULL DEFAULT current_date,
  due_date date,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','awaiting_approval','approved','paid','rejected')),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  paid_at timestamptz,
  document_path text,
  notes text NOT NULL DEFAULT '',
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS property_operating_expenses_property_date_idx
  ON public.property_operating_expenses(property_id, expense_date DESC);
CREATE INDEX IF NOT EXISTS property_operating_expenses_unpaid_idx
  ON public.property_operating_expenses(property_id, due_date)
  WHERE status IN ('awaiting_approval','approved');

CREATE TABLE IF NOT EXISTS public.property_finance_settings (
  property_id uuid PRIMARY KEY REFERENCES public.properties(id) ON DELETE CASCADE,
  minimum_operating_reserve numeric(12,2) NOT NULL DEFAULT 0 CHECK (minimum_operating_reserve >= 0),
  require_approval_below_reserve boolean NOT NULL DEFAULT true,
  updated_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.property_arrears_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  charge_entry_id uuid REFERENCES public.property_charge_entries(id) ON DELETE SET NULL,
  property_owner_id uuid NOT NULL REFERENCES public.property_owners(id) ON DELETE CASCADE,
  stage text NOT NULL DEFAULT 'reminder'
    CHECK (stage IN ('reminder','first_notice','final_notice','legal_review','resolved')),
  communication_method text NOT NULL DEFAULT 'other'
    CHECK (communication_method IN ('email','phone','letter','in_person','other')),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  agreed_fee numeric(12,2) NOT NULL DEFAULT 0 CHECK (agreed_fee >= 0),
  fee_basis text NOT NULL DEFAULT '',
  notes text NOT NULL DEFAULT '',
  letter_document_path text,
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS property_arrears_actions_owner_idx
  ON public.property_arrears_actions(property_id, property_owner_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.property_insurance_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  insurer text NOT NULL CHECK (length(btrim(insurer)) BETWEEN 2 AND 200),
  policy_number text NOT NULL CHECK (length(btrim(policy_number)) BETWEEN 1 AND 120),
  coverage_summary text NOT NULL DEFAULT '',
  premium_amount numeric(12,2) CHECK (premium_amount >= 0),
  currency text NOT NULL DEFAULT 'EUR' CHECK (currency = 'EUR'),
  starts_on date,
  expires_on date NOT NULL,
  document_path text,
  notes text NOT NULL DEFAULT '',
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (property_id, policy_number)
);
CREATE INDEX IF NOT EXISTS property_insurance_expiry_idx
  ON public.property_insurance_policies(property_id, expires_on);

CREATE TABLE IF NOT EXISTS public.property_meetings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 200),
  meeting_type text NOT NULL DEFAULT 'general' CHECK (meeting_type IN ('general','extraordinary','committee')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  organizer_name text NOT NULL DEFAULT '',
  representative_hours numeric(7,2) NOT NULL DEFAULT 0 CHECK (representative_hours >= 0),
  agreed_service_fee numeric(12,2) NOT NULL DEFAULT 0 CHECK (agreed_service_fee >= 0),
  fee_approved boolean NOT NULL DEFAULT false,
  attendees jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(attendees) = 'array'),
  minutes text NOT NULL DEFAULT '',
  linked_vote_id uuid REFERENCES public.property_votes(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','held','cancelled')),
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at IS NULL OR ends_at >= starts_at)
);
CREATE INDEX IF NOT EXISTS property_meetings_property_start_idx
  ON public.property_meetings(property_id, starts_at DESC);

CREATE TABLE IF NOT EXISTS public.property_handover_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  from_manager text NOT NULL DEFAULT '',
  to_manager text NOT NULL DEFAULT '',
  handover_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','awaiting_acceptance','accepted','cancelled')),
  financial_summary text NOT NULL DEFAULT '',
  open_items jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(open_items) = 'array'),
  document_paths jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(document_paths) = 'array'),
  accepted_by uuid REFERENCES auth.users(id),
  accepted_at timestamptz,
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS property_handover_records_property_date_idx
  ON public.property_handover_records(property_id, handover_date DESC);

CREATE TABLE IF NOT EXISTS public.property_management_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES auth.users(id),
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS property_management_audit_property_date_idx
  ON public.property_management_audit(property_id, created_at DESC);

DO $policies$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'property_management_contracts','property_management_services',
    'property_operating_expenses','property_arrears_actions',
    'property_insurance_policies','property_meetings','property_handover_records'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_insert', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_update', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_delete', t);
    IF t IN ('property_arrears_actions','property_handover_records') THEN
      EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.can_manage_property(property_id))', t || '_select', t);
    ELSE
      EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.can_access_property(property_id))', t || '_select', t);
    END IF;
    EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (created_by = (SELECT auth.uid()) AND public.can_manage_property(property_id))', t || '_insert', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (public.can_manage_property(property_id)) WITH CHECK (public.can_manage_property(property_id))', t || '_update', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (public.can_manage_property(property_id))', t || '_delete', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
  END LOOP;
END
$policies$;

ALTER TABLE public.property_finance_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS property_finance_settings_access ON public.property_finance_settings;
CREATE POLICY property_finance_settings_access ON public.property_finance_settings
  FOR ALL TO authenticated
  USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.property_finance_settings TO authenticated;

ALTER TABLE public.property_management_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS property_management_audit_read ON public.property_management_audit;
CREATE POLICY property_management_audit_read ON public.property_management_audit
  FOR SELECT TO authenticated USING (public.can_manage_property(property_id));
GRANT SELECT ON public.property_management_audit TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.property_management_audit FROM authenticated, anon, PUBLIC;

CREATE OR REPLACE FUNCTION public.capture_property_management_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE old_data jsonb; new_data jsonb; pid uuid; row_id text;
BEGIN
  old_data := CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END;
  new_data := CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END;
  pid := COALESCE((new_data ->> 'property_id')::uuid, (old_data ->> 'property_id')::uuid);
  row_id := COALESCE(new_data ->> 'id', old_data ->> 'id');
  INSERT INTO public.property_management_audit(property_id, actor_id, action, entity_type, entity_id, details)
  VALUES (pid, (SELECT auth.uid()), lower(TG_OP), TG_TABLE_NAME, row_id,
    jsonb_build_object('before', old_data, 'after', new_data));
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.capture_property_management_audit() FROM PUBLIC, anon, authenticated;

DO $triggers$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'property_management_contracts','property_management_services',
    'property_operating_expenses','property_arrears_actions',
    'property_insurance_policies','property_meetings','property_handover_records'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t || '_audit', t);
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.capture_property_management_audit()', t || '_audit', t);
  END LOOP;
END
$triggers$;

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES ('property-management-documents','property-management-documents',false,15728640,
  ARRAY['application/pdf','image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = 15728640,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS property_management_docs_read ON storage.objects;
CREATE POLICY property_management_docs_read ON storage.objects
  FOR SELECT TO authenticated USING (
    bucket_id = 'property-management-documents'
    AND CASE WHEN (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN public.can_access_property(((storage.foldername(name))[1])::uuid) ELSE false END
    AND ((storage.foldername(name))[2] = 'shared'
      OR public.can_manage_property(((storage.foldername(name))[1])::uuid))
  );
DROP POLICY IF EXISTS property_management_docs_insert ON storage.objects;
CREATE POLICY property_management_docs_insert ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (
    bucket_id = 'property-management-documents'
    AND CASE WHEN (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN public.can_manage_property(((storage.foldername(name))[1])::uuid) ELSE false END
    AND (storage.foldername(name))[2] IN ('shared','restricted')
  );
DROP POLICY IF EXISTS property_management_docs_update ON storage.objects;
CREATE POLICY property_management_docs_update ON storage.objects
  FOR UPDATE TO authenticated USING (
    bucket_id = 'property-management-documents'
    AND CASE WHEN (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN public.can_manage_property(((storage.foldername(name))[1])::uuid) ELSE false END
  ) WITH CHECK (
    bucket_id = 'property-management-documents'
    AND CASE WHEN (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN public.can_manage_property(((storage.foldername(name))[1])::uuid) ELSE false END
    AND (storage.foldername(name))[2] IN ('shared','restricted')
  );
DROP POLICY IF EXISTS property_management_docs_delete ON storage.objects;
CREATE POLICY property_management_docs_delete ON storage.objects
  FOR DELETE TO authenticated USING (
    bucket_id = 'property-management-documents'
    AND CASE WHEN (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN public.can_manage_property(((storage.foldername(name))[1])::uuid) ELSE false END
  );

COMMIT;

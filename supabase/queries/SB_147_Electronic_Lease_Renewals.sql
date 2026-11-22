BEGIN;

CREATE TABLE IF NOT EXISTS public.lease_renewals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  source_contract_id uuid NOT NULL REFERENCES public.property_rent_contracts(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  owner_user_id uuid NOT NULL REFERENCES auth.users(id),
  tenant_user_id uuid NOT NULL REFERENCES auth.users(id),
  property_name text NOT NULL,
  property_address text NOT NULL,
  unit_reference text NOT NULL,
  owner_name text NOT NULL,
  owner_email text NOT NULL,
  owner_id_type text NOT NULL,
  owner_id_number text NOT NULL,
  tenant_name text NOT NULL,
  tenant_email text NOT NULL,
  tenant_id_type text NOT NULL,
  tenant_id_number text NOT NULL,
  monthly_rent numeric(12,2) NOT NULL CHECK (monthly_rent > 0),
  deposit_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (deposit_amount >= 0),
  currency text NOT NULL DEFAULT 'EUR',
  start_date date NOT NULL,
  end_date date NOT NULL,
  rent_due_day integer NOT NULL DEFAULT 1 CHECK (rent_due_day BETWEEN 1 AND 28),
  common_charges numeric(12,2) NOT NULL DEFAULT 0 CHECK (common_charges >= 0),
  furniture_and_inventory text NOT NULL DEFAULT '',
  included_services text NOT NULL DEFAULT '',
  special_terms text NOT NULL DEFAULT '',
  payment_terms text NOT NULL,
  status text NOT NULL DEFAULT 'awaiting_signatures'
    CHECK (status IN ('awaiting_signatures', 'signed', 'cancelled')),
  owner_signed_at timestamptz,
  owner_signed_name text,
  tenant_signed_at timestamptz,
  tenant_signed_name text,
  terms_sha256 text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date > start_date),
  CHECK (owner_user_id <> tenant_user_id)
);

CREATE INDEX IF NOT EXISTS lease_renewals_owner_inbox_idx
  ON public.lease_renewals(owner_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS lease_renewals_tenant_inbox_idx
  ON public.lease_renewals(tenant_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS lease_renewals_property_idx
  ON public.lease_renewals(property_id, created_at DESC);

ALTER TABLE public.lease_renewals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lease_renewals_parties_read ON public.lease_renewals;
CREATE POLICY lease_renewals_parties_read ON public.lease_renewals
  FOR SELECT TO authenticated
  USING (owner_user_id = (SELECT auth.uid())
      OR tenant_user_id = (SELECT auth.uid())
      OR created_by = (SELECT auth.uid())
      OR public.is_smartblock_staff());

REVOKE ALL ON TABLE public.lease_renewals FROM anon, authenticated;
GRANT SELECT ON TABLE public.lease_renewals TO authenticated;

CREATE TABLE IF NOT EXISTS public.lease_renewal_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  renewal_id uuid NOT NULL REFERENCES public.lease_renewals(id) ON DELETE CASCADE,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  event_type text NOT NULL CHECK (event_type IN ('created', 'owner_signed', 'tenant_signed', 'cancelled')),
  actor_name text NOT NULL,
  terms_sha256 text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS lease_renewal_events_renewal_idx
  ON public.lease_renewal_events(renewal_id, occurred_at);
ALTER TABLE public.lease_renewal_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lease_renewal_events_parties_read ON public.lease_renewal_events;
CREATE POLICY lease_renewal_events_parties_read ON public.lease_renewal_events
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.lease_renewals r
    WHERE r.id = renewal_id
      AND (r.owner_user_id = (SELECT auth.uid())
        OR r.tenant_user_id = (SELECT auth.uid())
        OR r.created_by = (SELECT auth.uid())
        OR public.is_smartblock_staff())
  ));
REVOKE ALL ON TABLE public.lease_renewal_events FROM anon, authenticated;
GRANT SELECT ON TABLE public.lease_renewal_events TO authenticated;

CREATE OR REPLACE FUNCTION public.create_lease_renewal(
  p_contract_id uuid,
  p_owner_email text,
  p_tenant_email text,
  p_owner_id_type text,
  p_owner_id_number text,
  p_tenant_id_type text,
  p_tenant_id_number text,
  p_deposit_amount numeric,
  p_start_date date,
  p_end_date date,
  p_rent_due_day integer,
  p_common_charges numeric,
  p_furniture_and_inventory text,
  p_included_services text,
  p_special_terms text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  contract_row public.property_rent_contracts%ROWTYPE;
  property_row public.properties%ROWTYPE;
  owner_row record;
  tenant_row record;
  new_id uuid;
  canonical_terms text;
  payment_clause text :=
    'Οι συμβαλλόμενοι συμφωνούν ότι το ενοίκιο, η εγγύηση και οι λοιπές συμφωνημένες συναλλαγές της παρούσας μίσθωσης θα καταχωρούνται και θα διεκπεραιώνονται μέσω της ψηφιακής πλατφόρμας SmartBlock, με τον ενσωματωμένο πάροχο πληρωμών και τους διαθέσιμους τρόπους πληρωμής. Το SmartBlock παρέχει το ψηφιακό κανάλι διαχείρισης και δεν αποτελεί συμβαλλόμενο μέρος της μίσθωσης. Η επεξεργασία και απόδοση των χρημάτων διέπονται από τους όρους του παρόχου πληρωμών και τη ρύθμιση δικαιούχου του ακινήτου.';
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501'; END IF;
  SELECT * INTO contract_row FROM public.property_rent_contracts c WHERE c.id = p_contract_id;
  IF NOT FOUND OR NOT public.can_manage_property(contract_row.property_id) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
  END IF;
  IF contract_row.status NOT IN ('active', 'ended') THEN
    RAISE EXCEPTION 'Only an active or ended rental can be renewed.' USING ERRCODE = '22023';
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date <= p_start_date
     OR COALESCE(p_deposit_amount, -1) < 0 OR COALESCE(p_common_charges, -1) < 0
     OR p_rent_due_day NOT BETWEEN 1 AND 28 THEN
    RAISE EXCEPTION 'Enter valid dates, deposit, common charges and rent due day.' USING ERRCODE = '22023';
  END IF;
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(p_owner_id_number,''))) < 3
     OR pg_catalog.length(pg_catalog.btrim(COALESCE(p_tenant_id_number,''))) < 3 THEN
    RAISE EXCEPTION 'Enter the identification number for both signatories.' USING ERRCODE = '22023';
  END IF;

  SELECT pr.* INTO property_row FROM public.properties pr WHERE pr.id = contract_row.property_id;
  SELECT pr.id, COALESCE(nullif(pg_catalog.btrim(pr.full_name),''), u.email::text) AS full_name,
         u.email::text AS email
    INTO owner_row
    FROM public.property_owners po
    JOIN public.organization_members om ON om.organization_id = po.organization_id
      AND om.member_role = 'owner' AND om.membership_status = 'active'
    JOIN public.profiles pr ON pr.id = om.user_id
    JOIN auth.users u ON u.id = om.user_id
    JOIN public.account_role_requests rr ON rr.user_id = om.user_id
      AND rr.status = 'approved' AND rr.requested_roles @> ARRAY['property_owner']::text[]
    WHERE po.property_id = contract_row.property_id AND po.ownership_status = 'active'
      AND pg_catalog.lower(u.email::text) = pg_catalog.lower(pg_catalog.btrim(p_owner_email))
    ORDER BY po.is_primary_representative DESC, po.created_at
    LIMIT 1;
  IF owner_row.id IS NULL THEN
    RAISE EXCEPTION 'Select a registered, approved owner linked to this property.' USING ERRCODE = '22023';
  END IF;

  SELECT pr.id, COALESCE(nullif(pg_catalog.btrim(pr.full_name),''), u.email::text) AS full_name,
         u.email::text AS email
    INTO tenant_row
    FROM auth.users u
    JOIN public.profiles pr ON pr.id = u.id
    JOIN public.account_role_requests rr ON rr.user_id = u.id
      AND rr.status = 'approved' AND rr.requested_roles @> ARRAY['tenant']::text[]
    WHERE pg_catalog.lower(u.email::text) = pg_catalog.lower(pg_catalog.btrim(p_tenant_email))
      AND pg_catalog.regexp_replace(COALESCE(pr.phone,''), '[^0-9]', '', 'g')
          = pg_catalog.regexp_replace(COALESCE(contract_row.tenant_phone_e164,''), '[^0-9]', '', 'g')
    LIMIT 1;
  IF tenant_row.id IS NULL THEN
    RAISE EXCEPTION 'The registered tenant account must be approved and its phone must match the rental record.' USING ERRCODE = '22023';
  END IF;
  IF owner_row.id = tenant_row.id THEN RAISE EXCEPTION 'Owner and tenant must be different accounts.' USING ERRCODE = '22023'; END IF;

  canonical_terms := pg_catalog.jsonb_build_object(
    'contract_id', contract_row.id, 'property_id', contract_row.property_id,
    'property_name', COALESCE(property_row.name, ''),
    'property_address', pg_catalog.concat_ws(', ', property_row.address, property_row.city, property_row.country),
    'unit_reference', contract_row.unit_reference,
    'owner_user_id', owner_row.id, 'owner_name', owner_row.full_name, 'owner_email', owner_row.email,
    'owner_id_type', pg_catalog.btrim(p_owner_id_type), 'owner_id_number', pg_catalog.btrim(p_owner_id_number),
    'tenant_user_id', tenant_row.id, 'tenant_name', contract_row.tenant_name,
    'tenant_email', tenant_row.email, 'tenant_id_type', pg_catalog.btrim(p_tenant_id_type),
    'tenant_id_number', pg_catalog.btrim(p_tenant_id_number),
    'monthly_rent', contract_row.monthly_rent, 'deposit_amount', p_deposit_amount,
    'currency', contract_row.currency, 'start_date', p_start_date, 'end_date', p_end_date,
    'rent_due_day', p_rent_due_day, 'common_charges', p_common_charges,
    'furniture_and_inventory', COALESCE(p_furniture_and_inventory,''),
    'included_services', COALESCE(p_included_services,''),
    'special_terms', COALESCE(p_special_terms,''), 'payment_terms', payment_clause
  )::text;

  INSERT INTO public.lease_renewals (
    property_id, source_contract_id, created_by, owner_user_id, tenant_user_id,
    property_name, property_address, unit_reference,
    owner_name, owner_email, owner_id_type, owner_id_number,
    tenant_name, tenant_email, tenant_id_type, tenant_id_number,
    monthly_rent, deposit_amount, currency, start_date, end_date, rent_due_day,
    common_charges, furniture_and_inventory, included_services, special_terms,
    payment_terms, terms_sha256
  ) VALUES (
    contract_row.property_id, contract_row.id, actor, owner_row.id, tenant_row.id,
    COALESCE(property_row.name,''), pg_catalog.concat_ws(', ', property_row.address, property_row.city, property_row.country),
    contract_row.unit_reference, owner_row.full_name, owner_row.email,
    pg_catalog.btrim(p_owner_id_type), pg_catalog.btrim(p_owner_id_number),
    contract_row.tenant_name, tenant_row.email,
    pg_catalog.btrim(p_tenant_id_type), pg_catalog.btrim(p_tenant_id_number),
    contract_row.monthly_rent, p_deposit_amount, contract_row.currency, p_start_date, p_end_date,
    p_rent_due_day, p_common_charges, COALESCE(p_furniture_and_inventory,''),
    COALESCE(p_included_services,''), COALESCE(p_special_terms,''), payment_clause,
    pg_catalog.encode(extensions.digest(pg_catalog.convert_to(canonical_terms, 'UTF8'), 'sha256'), 'hex')
  ) RETURNING id INTO new_id;

  INSERT INTO public.lease_renewal_events(renewal_id, actor_user_id, event_type, actor_name, terms_sha256)
  VALUES (new_id, actor, 'created', COALESCE((SELECT full_name FROM public.profiles WHERE id = actor),''),
    (SELECT terms_sha256 FROM public.lease_renewals WHERE id = new_id));

  RETURN new_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_lease_renewal(uuid,text,text,text,text,text,text,numeric,date,date,integer,numeric,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_lease_renewal(uuid,text,text,text,text,text,text,numeric,date,date,integer,numeric,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.sign_lease_renewal(p_renewal_id uuid, p_signer_name text, p_confirm boolean)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  renewal_row public.lease_renewals%ROWTYPE;
  event_kind text;
BEGIN
  IF actor IS NULL OR p_confirm IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Sign in and explicit electronic acceptance are required.' USING ERRCODE = '42501';
  END IF;
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(p_signer_name,''))) < 3 THEN
    RAISE EXCEPTION 'Enter your full legal name.' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO renewal_row FROM public.lease_renewals WHERE id = p_renewal_id FOR UPDATE;
  IF NOT FOUND OR renewal_row.status <> 'awaiting_signatures' THEN
    RAISE EXCEPTION 'This renewal is not awaiting signatures.' USING ERRCODE = '22023';
  END IF;
  IF actor = renewal_row.owner_user_id AND renewal_row.owner_signed_at IS NULL THEN
    UPDATE public.lease_renewals SET owner_signed_at=now(), owner_signed_name=pg_catalog.btrim(p_signer_name), updated_at=now()
      WHERE id=p_renewal_id;
    event_kind := 'owner_signed';
  ELSIF actor = renewal_row.tenant_user_id AND renewal_row.tenant_signed_at IS NULL THEN
    UPDATE public.lease_renewals SET tenant_signed_at=now(), tenant_signed_name=pg_catalog.btrim(p_signer_name), updated_at=now()
      WHERE id=p_renewal_id;
    event_kind := 'tenant_signed';
  ELSE
    RAISE EXCEPTION 'Only the assigned owner or tenant can sign, and each party can sign once.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.lease_renewals SET status='signed', updated_at=now()
    WHERE id=p_renewal_id AND owner_signed_at IS NOT NULL AND tenant_signed_at IS NOT NULL;
  INSERT INTO public.lease_renewal_events(renewal_id, actor_user_id, event_type, actor_name, terms_sha256)
    VALUES (p_renewal_id, actor, event_kind, pg_catalog.btrim(p_signer_name), renewal_row.terms_sha256);
  RETURN (SELECT status FROM public.lease_renewals WHERE id=p_renewal_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.sign_lease_renewal(uuid,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sign_lease_renewal(uuid,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_lease_renewal(p_renewal_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE r public.lease_renewals%ROWTYPE; actor uuid := (SELECT auth.uid());
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in is required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO r FROM public.lease_renewals WHERE id=p_renewal_id FOR UPDATE;
  IF NOT FOUND OR r.status <> 'awaiting_signatures'
    OR (actor <> r.created_by AND NOT public.is_smartblock_staff()) THEN
    RAISE EXCEPTION 'Only the creator or SmartBlock staff can cancel an unsigned draft.' USING ERRCODE='42501';
  END IF;
  UPDATE public.lease_renewals SET status='cancelled', updated_at=now() WHERE id=p_renewal_id;
  INSERT INTO public.lease_renewal_events(renewal_id, actor_user_id, event_type, actor_name, terms_sha256)
  VALUES (p_renewal_id, actor, 'cancelled', COALESCE((SELECT full_name FROM public.profiles WHERE id=actor),''), r.terms_sha256);
END;
$function$;

REVOKE ALL ON FUNCTION public.cancel_lease_renewal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_lease_renewal(uuid) TO authenticated;

COMMIT;



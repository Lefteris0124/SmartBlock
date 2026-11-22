BEGIN;

ALTER TABLE public.lease_renewals
  ALTER COLUMN owner_id_type SET DEFAULT '',
  ALTER COLUMN owner_id_number SET DEFAULT '',
  ALTER COLUMN tenant_id_type SET DEFAULT '',
  ALTER COLUMN tenant_id_number SET DEFAULT '';

ALTER TABLE public.lease_renewal_events
  DROP CONSTRAINT IF EXISTS lease_renewal_events_event_type_check;
ALTER TABLE public.lease_renewal_events
  ADD CONSTRAINT lease_renewal_events_event_type_check
  CHECK (event_type IN ('created','owner_details_saved','tenant_details_saved','owner_signed','tenant_signed','cancelled'));

CREATE OR REPLACE FUNCTION public.clear_lease_renewal_identity_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  NEW.owner_id_type := '';
  NEW.owner_id_number := '';
  NEW.tenant_id_type := '';
  NEW.tenant_id_number := '';
  NEW.terms_sha256 := pg_catalog.encode(extensions.digest(
    pg_catalog.convert_to((pg_catalog.to_jsonb(NEW) - ARRAY[
      'id','status','owner_signed_at','owner_signed_name','tenant_signed_at','tenant_signed_name',
      'terms_sha256','created_at','updated_at'
    ])::text, 'UTF8'), 'sha256'), 'hex');
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.clear_lease_renewal_identity_before_insert() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS clear_lease_renewal_identity_before_insert ON public.lease_renewals;
CREATE TRIGGER clear_lease_renewal_identity_before_insert
  BEFORE INSERT ON public.lease_renewals
  FOR EACH ROW EXECUTE FUNCTION public.clear_lease_renewal_identity_before_insert();

CREATE OR REPLACE FUNCTION public.save_lease_renewal_party_details(
  p_renewal_id uuid,
  p_full_name text,
  p_id_type text,
  p_id_number text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  r public.lease_renewals%ROWTYPE;
  event_kind text;
  terms_hash text;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in is required.' USING ERRCODE='42501'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(p_full_name,''))) < 3
     OR pg_catalog.length(pg_catalog.btrim(COALESCE(p_id_type,''))) < 2
     OR pg_catalog.length(pg_catalog.btrim(COALESCE(p_id_number,''))) < 3 THEN
    RAISE EXCEPTION 'Enter your full legal name and identification details.' USING ERRCODE='22023';
  END IF;
  SELECT * INTO r FROM public.lease_renewals WHERE id=p_renewal_id FOR UPDATE;
  IF NOT FOUND OR r.status <> 'awaiting_signatures'
     OR r.owner_signed_at IS NOT NULL OR r.tenant_signed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Party details cannot be changed after a signature.' USING ERRCODE='22023';
  END IF;
  IF actor = r.owner_user_id THEN
    UPDATE public.lease_renewals SET owner_name=pg_catalog.btrim(p_full_name),
      owner_id_type=pg_catalog.btrim(p_id_type), owner_id_number=pg_catalog.btrim(p_id_number), updated_at=now()
      WHERE id=p_renewal_id;
    event_kind := 'owner_details_saved';
  ELSIF actor = r.tenant_user_id THEN
    UPDATE public.lease_renewals SET tenant_name=pg_catalog.btrim(p_full_name),
      tenant_id_type=pg_catalog.btrim(p_id_type), tenant_id_number=pg_catalog.btrim(p_id_number), updated_at=now()
      WHERE id=p_renewal_id;
    event_kind := 'tenant_details_saved';
  ELSE
    RAISE EXCEPTION 'Only the assigned owner or tenant can update their details.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO r FROM public.lease_renewals WHERE id=p_renewal_id;
  terms_hash := pg_catalog.encode(extensions.digest(
    pg_catalog.convert_to((pg_catalog.to_jsonb(r) - ARRAY[
      'id','status','owner_signed_at','owner_signed_name','tenant_signed_at','tenant_signed_name',
      'terms_sha256','created_at','updated_at'
    ])::text, 'UTF8'), 'sha256'), 'hex');
  UPDATE public.lease_renewals SET terms_sha256=terms_hash, updated_at=now()
    WHERE id=p_renewal_id;
  INSERT INTO public.lease_renewal_events(renewal_id,actor_user_id,event_type,actor_name,terms_sha256)
    VALUES(p_renewal_id,actor, event_kind,pg_catalog.btrim(p_full_name),terms_hash);
END;
$function$;
REVOKE ALL ON FUNCTION public.save_lease_renewal_party_details(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_lease_renewal_party_details(uuid,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.sign_lease_renewal(
  p_renewal_id uuid,
  p_signer_name text,
  p_confirm boolean
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  renewal_row public.lease_renewals%ROWTYPE;
  event_kind text;
  month_count integer;
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
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(renewal_row.owner_id_number,''))) < 3
     OR pg_catalog.length(pg_catalog.btrim(COALESCE(renewal_row.tenant_id_number,''))) < 3
     OR COALESCE(renewal_row.owner_id_type,'') = '' OR COALESCE(renewal_row.tenant_id_type,'') = '' THEN
    RAISE EXCEPTION 'Both parties must complete their identification details before signing.' USING ERRCODE='22023';
  END IF;
  IF (actor=renewal_row.owner_user_id AND pg_catalog.btrim(p_signer_name) IS DISTINCT FROM renewal_row.owner_name)
     OR (actor=renewal_row.tenant_user_id AND pg_catalog.btrim(p_signer_name) IS DISTINCT FROM renewal_row.tenant_name) THEN
    RAISE EXCEPTION 'Use the same full legal name saved in your party details.' USING ERRCODE='22023';
  END IF;
  IF actor = renewal_row.owner_user_id AND renewal_row.owner_signed_at IS NULL THEN
    UPDATE public.lease_renewals
      SET owner_signed_at = now(), owner_signed_name = pg_catalog.btrim(p_signer_name), updated_at = now()
      WHERE id = p_renewal_id;
    event_kind := 'owner_signed';
  ELSIF actor = renewal_row.tenant_user_id AND renewal_row.tenant_signed_at IS NULL THEN
    UPDATE public.lease_renewals
      SET tenant_signed_at = now(), tenant_signed_name = pg_catalog.btrim(p_signer_name), updated_at = now()
      WHERE id = p_renewal_id;
    event_kind := 'tenant_signed';
  ELSE
    RAISE EXCEPTION 'Only the assigned owner or tenant can sign, and each party can sign once.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO renewal_row FROM public.lease_renewals WHERE id = p_renewal_id;
  IF renewal_row.owner_signed_at IS NOT NULL AND renewal_row.tenant_signed_at IS NOT NULL THEN
    IF renewal_row.end_date > renewal_row.start_date + INTERVAL '10 years' THEN
      RAISE EXCEPTION 'A lease renewal cannot exceed ten years.' USING ERRCODE = '22023';
    END IF;
    UPDATE public.lease_renewals SET status = 'signed', updated_at = now() WHERE id = p_renewal_id;
    UPDATE public.property_rent_contracts
      SET monthly_rent = renewal_row.monthly_rent,
          start_date = renewal_row.start_date,
          end_date = renewal_row.end_date,
          due_day = renewal_row.rent_due_day,
          status = 'active'
      WHERE id = renewal_row.source_contract_id;

    month_count :=
      (pg_catalog.date_part('year', renewal_row.end_date)::integer - pg_catalog.date_part('year', renewal_row.start_date)::integer) * 12
      + pg_catalog.date_part('month', renewal_row.end_date)::integer - pg_catalog.date_part('month', renewal_row.start_date)::integer;
    INSERT INTO public.property_rent_installments AS existing_installment(contract_id, period_start, due_date, amount_due)
    SELECT renewal_row.source_contract_id,
      (pg_catalog.date_trunc('month', renewal_row.start_date::timestamp) + pg_catalog.make_interval(months => s.month_no))::date,
      GREATEST(
        ((pg_catalog.date_trunc('month', renewal_row.start_date::timestamp) + pg_catalog.make_interval(months => s.month_no))::date + (renewal_row.rent_due_day - 1)),
        CASE WHEN s.month_no = 0 THEN renewal_row.start_date
          ELSE ((pg_catalog.date_trunc('month', renewal_row.start_date::timestamp) + pg_catalog.make_interval(months => s.month_no))::date + (renewal_row.rent_due_day - 1)) END
      ),
      renewal_row.monthly_rent
    FROM pg_catalog.generate_series(0, month_count) AS s(month_no)
    WHERE (pg_catalog.date_trunc('month', renewal_row.start_date::timestamp) + pg_catalog.make_interval(months => s.month_no))::date <= renewal_row.end_date
    ON CONFLICT (contract_id, period_start) DO UPDATE
      SET due_date = EXCLUDED.due_date,
          amount_due = EXCLUDED.amount_due
      WHERE existing_installment.amount_paid = 0
        AND existing_installment.status NOT IN ('paid', 'cancelled');
  END IF;

  INSERT INTO public.lease_renewal_events(renewal_id, actor_user_id, event_type, actor_name, terms_sha256)
    VALUES (p_renewal_id, actor, event_kind, pg_catalog.btrim(p_signer_name), renewal_row.terms_sha256);
  RETURN (SELECT status FROM public.lease_renewals WHERE id = p_renewal_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.sign_lease_renewal(uuid,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sign_lease_renewal(uuid,text,boolean) TO authenticated;

COMMIT;




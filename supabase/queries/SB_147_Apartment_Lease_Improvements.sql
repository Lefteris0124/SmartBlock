-- Apartment inventory linked to the established lease invitation workflow.
CREATE TABLE IF NOT EXISTS public.property_apartments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  apartment_number text NOT NULL CHECK (length(btrim(apartment_number)) BETWEEN 1 AND 30),
  room_count integer NOT NULL CHECK (room_count BETWEEN 0 AND 50),
  area_sqm numeric(10,2) NOT NULL CHECK (area_sqm > 0),
  furnished boolean NOT NULL DEFAULT false,
  furniture_details text NOT NULL DEFAULT '',
  comments text NOT NULL DEFAULT '',
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (property_id, apartment_number),
  UNIQUE (id, property_id)
);
CREATE INDEX IF NOT EXISTS property_apartments_property_idx
  ON public.property_apartments(property_id, apartment_number);
ALTER TABLE public.property_apartments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.property_apartments FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.property_apartments TO authenticated;
DROP POLICY IF EXISTS property_apartments_access ON public.property_apartments;
CREATE POLICY property_apartments_access ON public.property_apartments
  FOR SELECT TO authenticated USING (public.can_access_property(property_id));
DROP POLICY IF EXISTS property_apartments_manage ON public.property_apartments;
CREATE POLICY property_apartments_manage ON public.property_apartments
  FOR ALL TO authenticated USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id) AND created_by = (SELECT auth.uid()));

ALTER TABLE public.lease_contract_offers
  ADD COLUMN IF NOT EXISTS apartment_id uuid;
ALTER TABLE public.lease_contract_offers
  ADD COLUMN IF NOT EXISTS tenant_id_country text;
ALTER TABLE public.lease_contract_offers
  DROP CONSTRAINT IF EXISTS lease_contract_offers_apartment_fk;
ALTER TABLE public.lease_contract_offers
  ADD CONSTRAINT lease_contract_offers_apartment_fk
  FOREIGN KEY (apartment_id, property_id)
  REFERENCES public.property_apartments(id, property_id) ON DELETE RESTRICT;
ALTER TABLE public.lease_contract_offers ALTER COLUMN owner_signed_at DROP NOT NULL;
ALTER TABLE public.lease_contract_offers ALTER COLUMN owner_signed_at DROP DEFAULT;
ALTER TABLE public.lease_contract_offers ALTER COLUMN owner_signed_name DROP NOT NULL;
ALTER TABLE public.lease_contract_offers ALTER COLUMN owner_signed_name DROP DEFAULT;
ALTER TABLE public.lease_contract_offers DROP CONSTRAINT IF EXISTS lease_contract_offers_status_check;
ALTER TABLE public.lease_contract_offers ADD CONSTRAINT lease_contract_offers_status_check
  CHECK (status = ANY (ARRAY['awaiting_tenant','awaiting_owner','accepted','cancelled','expired']));

CREATE OR REPLACE FUNCTION public.get_lease_contract_offer(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor uuid := (SELECT auth.uid()); actor_email text; offer public.lease_contract_offers%ROWTYPE; property_row public.properties%ROWTYPE;
BEGIN
  IF actor IS NULL OR length(coalesce(p_token,''))<32 THEN RAISE EXCEPTION 'Sign in with the invited email to view this contract.' USING ERRCODE='42501'; END IF;
  SELECT lower(email::text) INTO actor_email FROM auth.users WHERE id=actor;
  SELECT * INTO offer FROM public.lease_contract_offers WHERE invite_token_sha256=pg_catalog.encode(extensions.digest(p_token,'sha256'),'hex')
    AND lower(tenant_email)=actor_email AND status IN ('awaiting_tenant','awaiting_owner','accepted')
    AND (status<>'awaiting_tenant' OR invite_expires_at>now());
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitation invalid, expired, or belongs to another email.' USING ERRCODE='42501'; END IF;
  SELECT * INTO property_row FROM public.properties WHERE id=offer.property_id;
  INSERT INTO public.lease_contract_offer_events(offer_id,actor_user_id,event_type,terms_sha256)
    VALUES(offer.id,actor,'viewed',offer.terms_sha256);
  RETURN (pg_catalog.to_jsonb(offer)-ARRAY['invite_token_sha256']) || pg_catalog.jsonb_build_object(
    'property_name',property_row.name,'property_address',pg_catalog.concat_ws(', ',property_row.address,property_row.city,property_row.country)
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_lease_contract_offer(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lease_contract_offer(text) TO authenticated;

-- Create via the established token/hash/audit RPC, attach the unit, and leave
-- the offer unsigned by its owner until the tenant has signed it.
CREATE OR REPLACE FUNCTION public.create_apartment_lease_offer(
  p_apartment_id uuid, p_owner_name text, p_owner_id_type text, p_owner_id_number text,
  p_tenant_name text, p_tenant_email text, p_tenant_phone_e164 text,
  p_monthly_rent numeric, p_deposit_amount numeric, p_common_charges numeric,
  p_start_date date, p_end_date date, p_rent_due_day integer,
  p_furniture_and_inventory text, p_included_services text, p_special_terms text,
  p_guarantor_name text, p_guarantor_terms text, p_owner_confirm boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  unit public.property_apartments%ROWTYPE;
  result jsonb;
BEGIN
  IF actor IS NULL OR p_owner_confirm IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Sign in and confirm the draft before sending.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO unit FROM public.property_apartments WHERE id=p_apartment_id FOR SHARE;
  IF NOT FOUND OR NOT public.can_manage_property(unit.property_id) THEN
    RAISE EXCEPTION 'Apartment management access is required.' USING ERRCODE='42501';
  END IF;
  result := public.create_lease_contract_offer(
    unit.property_id, unit.apartment_number, p_owner_name, p_owner_id_type, p_owner_id_number,
    p_tenant_name, p_tenant_email, p_tenant_phone_e164, p_monthly_rent, p_deposit_amount,
    p_common_charges, p_start_date, p_end_date, p_rent_due_day,
    coalesce(p_furniture_and_inventory,'') || CASE WHEN unit.furniture_details='' THEN '' ELSE E'\n\nInventory: '||unit.furniture_details END,
    p_included_services, p_special_terms || E'\n\nApartment details: '||unit.room_count||' rooms, '||unit.area_sqm||' m², furnished: '||unit.furnished||'. '||unit.comments,
    p_guarantor_name, p_guarantor_terms, true
  );
  UPDATE public.lease_contract_offers SET apartment_id=unit.id, owner_signed_at=NULL, owner_signed_name=NULL
    WHERE id=(result->>'offer_id')::uuid AND owner_user_id=actor;
  UPDATE public.lease_contract_offer_events SET signer_name=NULL
    WHERE offer_id=(result->>'offer_id')::uuid AND event_type='created';
  RETURN result;
END;
$function$;
REVOKE ALL ON FUNCTION public.create_apartment_lease_offer(uuid,text,text,text,text,text,text,numeric,numeric,numeric,date,date,integer,text,text,text,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_apartment_lease_offer(uuid,text,text,text,text,text,text,numeric,numeric,numeric,date,date,integer,text,text,text,text,text,boolean) TO authenticated;

-- Tenant signs first; owner approval and rent ledger creation follow separately.
CREATE OR REPLACE FUNCTION public.accept_lease_contract_offer(
  p_token text, p_signer_name text, p_tenant_id_type text, p_tenant_id_number text, p_confirm boolean
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  actor_email text;
  offer public.lease_contract_offers%ROWTYPE;
BEGIN
  IF actor IS NULL OR p_confirm IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Sign in and explicitly accept the lease terms.' USING ERRCODE='42501';
  END IF;
  IF length(btrim(coalesce(p_signer_name,'')))<3 OR length(btrim(coalesce(p_tenant_id_type,'')))<2 OR length(btrim(coalesce(p_tenant_id_number,'')))<3 THEN
    RAISE EXCEPTION 'Enter your full name and identification details.' USING ERRCODE='22023';
  END IF;
  SELECT lower(email::text) INTO actor_email FROM auth.users WHERE id=actor;
  SELECT * INTO offer FROM public.lease_contract_offers
    WHERE invite_token_sha256=pg_catalog.encode(extensions.digest(p_token,'sha256'),'hex')
      AND lower(tenant_email)=actor_email AND status='awaiting_tenant' AND invite_expires_at>now() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'This contract invitation cannot be accepted.' USING ERRCODE='42501'; END IF;
  UPDATE public.lease_contract_offers SET tenant_user_id=actor, tenant_id_type=btrim(p_tenant_id_type),
    tenant_id_number=btrim(p_tenant_id_number), tenant_signed_at=now(), tenant_signed_name=btrim(p_signer_name),
    status='awaiting_owner', updated_at=now() WHERE id=offer.id;
  INSERT INTO public.lease_contract_offer_events(offer_id,actor_user_id,event_type,signer_name,terms_sha256)
    VALUES(offer.id,actor,'tenant_signed',btrim(p_signer_name),offer.terms_sha256);
  INSERT INTO public.account_role_requests(user_id,requested_roles,status)
    VALUES(actor,ARRAY['tenant']::text[],'pending') ON CONFLICT(user_id) DO UPDATE SET requested_roles=ARRAY(
      SELECT DISTINCT role FROM unnest(public.account_role_requests.requested_roles||ARRAY['tenant']::text[]) AS role ORDER BY role
    );
  UPDATE public.profiles SET full_name=CASE WHEN length(btrim(coalesce(full_name,'')))<3 THEN btrim(p_signer_name) ELSE full_name END,
    phone=coalesce(nullif(phone,''),offer.tenant_phone_e164) WHERE id=actor;
  RETURN offer.id;
END;
$function$;
REVOKE ALL ON FUNCTION public.accept_lease_contract_offer(text,text,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_lease_contract_offer(text,text,text,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_apartment_lease_offer(
  p_token text, p_signer_name text, p_tenant_id_type text, p_tenant_id_country text,
  p_tenant_id_number text, p_confirm boolean
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE offer_id uuid;
BEGIN
  IF length(btrim(coalesce(p_tenant_id_country,'')))<2 THEN
    RAISE EXCEPTION 'Enter the document issuing country.' USING ERRCODE='22023';
  END IF;
  offer_id := public.accept_lease_contract_offer(p_token,p_signer_name,p_tenant_id_type,p_tenant_id_number,p_confirm);
  UPDATE public.lease_contract_offers SET tenant_id_country=btrim(p_tenant_id_country) WHERE id=offer_id;
  RETURN offer_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.accept_apartment_lease_offer(text,text,text,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_apartment_lease_offer(text,text,text,text,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.finalize_lease_contract_offer(p_offer_id uuid, p_signer_name text, p_confirm boolean)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE actor uuid := (SELECT auth.uid()); offer public.lease_contract_offers%ROWTYPE; contract_id uuid;
BEGIN
  IF actor IS NULL OR p_confirm IS DISTINCT FROM true OR length(btrim(coalesce(p_signer_name,'')))<3 THEN
    RAISE EXCEPTION 'Sign in, review the signed offer, and confirm with your full name.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO offer FROM public.lease_contract_offers WHERE id=p_offer_id FOR UPDATE;
  IF NOT FOUND OR offer.owner_user_id<>actor OR offer.status<>'awaiting_owner' OR offer.tenant_signed_at IS NULL THEN
    RAISE EXCEPTION 'This offer is not awaiting your final review.' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.property_rent_contracts(property_id,unit_reference,tenant_name,tenant_phone_e164,tenant_user_id,monthly_rent,currency,start_date,end_date,due_day,status,created_by)
  VALUES(offer.property_id,offer.unit_reference,offer.tenant_name,offer.tenant_phone_e164,offer.tenant_user_id,offer.monthly_rent,offer.currency,offer.start_date,offer.end_date,offer.rent_due_day,'active',actor)
  RETURNING id INTO contract_id;
  INSERT INTO public.property_rent_installments(contract_id,period_start,due_date,amount_due)
  SELECT contract_id,(date_trunc('month',offer.start_date::timestamp)+make_interval(months=>s.m))::date,
    GREATEST((date_trunc('month',offer.start_date::timestamp)+make_interval(months=>s.m))::date+(offer.rent_due_day-1),
      CASE WHEN s.m=0 THEN offer.start_date ELSE (date_trunc('month',offer.start_date::timestamp)+make_interval(months=>s.m))::date+(offer.rent_due_day-1) END),offer.monthly_rent
  FROM generate_series(0,120) AS s(m)
  WHERE (date_trunc('month',offer.start_date::timestamp)+make_interval(months=>s.m))::date<=offer.end_date;
  UPDATE public.lease_contract_offers SET owner_signed_at=now(),owner_signed_name=btrim(p_signer_name),status='accepted',rent_contract_id=contract_id,updated_at=now() WHERE id=offer.id;
  INSERT INTO public.lease_contract_offer_events(offer_id,actor_user_id,event_type,signer_name,terms_sha256)
    VALUES(offer.id,actor,'owner_signed',btrim(p_signer_name),offer.terms_sha256);
  RETURN contract_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.finalize_lease_contract_offer(uuid,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_lease_contract_offer(uuid,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_lease_contract_offer_for_owner(p_offer_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE offer public.lease_contract_offers%ROWTYPE; property_row public.properties%ROWTYPE;
BEGIN
  SELECT * INTO offer FROM public.lease_contract_offers WHERE id=p_offer_id;
  IF NOT FOUND OR offer.owner_user_id IS DISTINCT FROM (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Offer is unavailable.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO property_row FROM public.properties WHERE id=offer.property_id;
  RETURN (pg_catalog.to_jsonb(offer)-ARRAY['invite_token_sha256']) || pg_catalog.jsonb_build_object(
    'property_name',property_row.name,'property_address',pg_catalog.concat_ws(', ',property_row.address,property_row.city,property_row.country)
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_lease_contract_offer_for_owner(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lease_contract_offer_for_owner(uuid) TO authenticated;


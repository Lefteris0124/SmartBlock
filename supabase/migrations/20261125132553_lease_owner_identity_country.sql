ALTER TABLE public.lease_contract_offers
  ADD COLUMN IF NOT EXISTS owner_id_country text;

CREATE OR REPLACE FUNCTION public.create_apartment_lease_offer(
  p_apartment_id uuid, p_owner_name text, p_owner_id_type text,
  p_owner_id_number text, p_tenant_name text, p_tenant_email text,
  p_tenant_phone_e164 text, p_monthly_rent numeric, p_deposit_amount numeric,
  p_common_charges numeric, p_start_date date, p_end_date date,
  p_rent_due_day integer, p_furniture_and_inventory text,
  p_included_services text, p_special_terms text, p_guarantor_name text,
  p_guarantor_terms text, p_owner_confirm boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Update SmartBlock to provide the identity document issuing country.';
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_apartment_lease_offer(
  p_apartment_id uuid, p_owner_name text, p_owner_id_type text,
  p_owner_id_country text, p_owner_id_number text, p_tenant_name text,
  p_tenant_email text, p_tenant_phone_e164 text, p_monthly_rent numeric,
  p_deposit_amount numeric, p_common_charges numeric, p_start_date date,
  p_end_date date, p_rent_due_day integer, p_furniture_and_inventory text,
  p_included_services text, p_special_terms text, p_guarantor_name text,
  p_guarantor_terms text, p_owner_confirm boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  unit public.property_apartments%ROWTYPE;
  result jsonb;
BEGIN
  IF actor IS NULL OR p_owner_confirm IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Sign in and confirm the draft before sending.' USING ERRCODE='42501';
  END IF;
  IF nullif(pg_catalog.btrim(p_owner_id_country), '') IS NULL THEN
    RAISE EXCEPTION 'The identity document issuing country is required.';
  END IF;
  SELECT * INTO unit FROM public.property_apartments WHERE id=p_apartment_id FOR SHARE;
  IF NOT FOUND OR NOT public.can_manage_property(unit.property_id) THEN
    RAISE EXCEPTION 'Apartment management access is required.' USING ERRCODE='42501';
  END IF;
  result := public.create_lease_contract_offer(
    unit.property_id, unit.apartment_number, p_owner_name, p_owner_id_type,
    p_owner_id_number, p_tenant_name, p_tenant_email, p_tenant_phone_e164,
    p_monthly_rent, p_deposit_amount, p_common_charges, p_start_date,
    p_end_date, p_rent_due_day,
    coalesce(p_furniture_and_inventory,'') ||
      CASE WHEN unit.furniture_details='' THEN ''
        ELSE E'\\n\\nInventory: '||unit.furniture_details END,
    p_included_services,
    p_special_terms || E'\\n\\nApartment details: '||unit.room_count||
      ' rooms, '||unit.area_sqm||' m², furnished: '||unit.furnished||'. '||unit.comments,
    p_guarantor_name, p_guarantor_terms, true
  );
  UPDATE public.lease_contract_offers
    SET apartment_id=unit.id, owner_id_country=pg_catalog.btrim(p_owner_id_country),
        owner_signed_at=NULL, owner_signed_name=NULL
    WHERE id=(result->>'offer_id')::uuid AND owner_user_id=actor;
  UPDATE public.lease_contract_offer_events SET signer_name=NULL
    WHERE offer_id=(result->>'offer_id')::uuid AND event_type='created';
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_apartment_lease_offer(
  uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,date,date,integer,
  text,text,text,text,text,boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_apartment_lease_offer(
  uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,date,date,integer,
  text,text,text,text,text,boolean
) TO authenticated, service_role;

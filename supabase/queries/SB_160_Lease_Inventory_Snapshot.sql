-- Treat the owner-edited inventory as the complete lease snapshot.
-- Unit-specific and owner-default furniture are merged in the app before this RPC.
CREATE OR REPLACE FUNCTION public.create_apartment_lease_offer(p_apartment_id uuid, p_owner_name text, p_owner_id_type text, p_owner_id_country text, p_owner_id_number text, p_tenant_name text, p_tenant_email text, p_tenant_phone_e164 text, p_tenant_id_type text, p_tenant_id_country text, p_tenant_id_number text, p_tenant_id_expiry_date date, p_monthly_rent numeric, p_deposit_amount numeric, p_common_charges numeric, p_start_date date, p_end_date date, p_rent_due_day integer, p_furniture_and_inventory text, p_included_services text, p_special_terms text, p_guarantor_name text, p_guarantor_terms text, p_owner_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := (select auth.uid());
  unit public.property_apartments%rowtype;
  result jsonb;
  new_offer_id uuid;
  new_hash text;
begin
  if actor is null or p_owner_confirm is distinct from true then
    raise exception 'Sign in and confirm the draft before sending.' using errcode='42501';
  end if;
  if nullif(pg_catalog.btrim(coalesce(p_owner_id_country,'')), '') is null
     or coalesce(p_tenant_id_type,'') not in ('national_id','passport')
     or length(pg_catalog.btrim(coalesce(p_tenant_id_country,''))) < 2
     or length(pg_catalog.btrim(coalesce(p_tenant_id_number,''))) < 3
     or p_tenant_id_expiry_date is null
     or p_tenant_id_expiry_date < current_date then
    raise exception 'Complete the tenant identity document type, issuing country, number, and future expiry date.' using errcode='22023';
  end if;
  select * into unit from public.property_apartments
    where id=p_apartment_id for share;
  if not found or not public.can_manage_property(unit.property_id) then
    raise exception 'Apartment management access is required.' using errcode='42501';
  end if;

  result := public.create_lease_contract_offer(
    unit.property_id, unit.apartment_number, p_owner_name, p_owner_id_type,
    p_owner_id_number, p_tenant_name, p_tenant_email, p_tenant_phone_e164,
    p_monthly_rent, p_deposit_amount, p_common_charges, p_start_date,
    p_end_date, p_rent_due_day,
    coalesce(p_furniture_and_inventory,''),
    p_included_services,
    p_special_terms || E'\n\nApartment details: '||unit.room_count||
      ' rooms, '||unit.area_sqm||' m², furnished: '||unit.furnished||'. '||unit.comments,
    p_guarantor_name, p_guarantor_terms, true
  );
  new_offer_id := (result->>'offer_id')::uuid;
  update public.lease_contract_offers
    set apartment_id=unit.id,
        owner_id_country=pg_catalog.btrim(p_owner_id_country),
        tenant_id_type=pg_catalog.btrim(p_tenant_id_type),
        tenant_id_country=pg_catalog.btrim(p_tenant_id_country),
        tenant_id_number=pg_catalog.btrim(p_tenant_id_number),
        tenant_id_expiry_date=p_tenant_id_expiry_date,
        owner_signed_at=null, owner_signed_name=null,
        terms_sha256=pg_catalog.encode(
          extensions.digest(
            terms_sha256 || E'\n' || pg_catalog.jsonb_build_object(
              'tenant_id_type',pg_catalog.btrim(p_tenant_id_type),
              'tenant_id_country',pg_catalog.btrim(p_tenant_id_country),
              'tenant_id_number',pg_catalog.btrim(p_tenant_id_number),
              'tenant_id_expiry_date',p_tenant_id_expiry_date
            )::text,
            'sha256'
          ),
          'hex'
        )
    where id=new_offer_id and owner_user_id=actor
    returning terms_sha256 into new_hash;
  update public.lease_contract_offer_events as event
    set signer_name=null, terms_sha256=new_hash
    where event.offer_id=new_offer_id and event.event_type='created';
  return result;
end;
$function$



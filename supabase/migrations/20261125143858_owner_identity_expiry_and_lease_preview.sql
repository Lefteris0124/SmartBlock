alter table public.lease_contract_offers
  add column if not exists owner_id_expiry_date date;

create or replace function public.create_apartment_lease_offer(
  p_apartment_id uuid,
  p_owner_name text,
  p_owner_id_type text,
  p_owner_id_country text,
  p_owner_id_number text,
  p_owner_id_expiry_date date,
  p_tenant_name text,
  p_tenant_email text,
  p_tenant_phone_e164 text,
  p_tenant_id_type text,
  p_tenant_id_country text,
  p_tenant_id_number text,
  p_tenant_id_expiry_date date,
  p_monthly_rent numeric,
  p_deposit_amount numeric,
  p_common_charges numeric,
  p_start_date date,
  p_end_date date,
  p_rent_due_day integer,
  p_furniture_and_inventory text,
  p_included_services text,
  p_special_terms text,
  p_guarantor_name text,
  p_guarantor_terms text,
  p_owner_confirm boolean
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  result jsonb;
  new_offer_id uuid;
  new_hash text;
begin
  if actor is null or p_owner_confirm is distinct from true then
    raise exception 'Sign in and confirm the draft before sending.' using errcode='42501';
  end if;
  if coalesce(p_owner_id_type,'') not in ('national_id','passport')
     or length(pg_catalog.btrim(coalesce(p_owner_id_country,''))) < 2
     or length(pg_catalog.btrim(coalesce(p_owner_id_number,''))) < 3
     or p_owner_id_expiry_date is null
     or p_owner_id_expiry_date < current_date then
    raise exception 'Complete the owner identity document type, issuing country, number, and future expiry date.' using errcode='22023';
  end if;

  result := public.create_apartment_lease_offer(
    p_apartment_id, p_owner_name, p_owner_id_type, p_owner_id_country,
    p_owner_id_number, p_tenant_name, p_tenant_email, p_tenant_phone_e164,
    p_tenant_id_type, p_tenant_id_country, p_tenant_id_number,
    p_tenant_id_expiry_date, p_monthly_rent, p_deposit_amount,
    p_common_charges, p_start_date, p_end_date, p_rent_due_day,
    p_furniture_and_inventory, p_included_services, p_special_terms,
    p_guarantor_name, p_guarantor_terms, p_owner_confirm
  );

  new_offer_id := (result->>'offer_id')::uuid;
  update public.lease_contract_offers as offer
    set owner_id_expiry_date = p_owner_id_expiry_date,
        terms_sha256 = pg_catalog.encode(extensions.digest(
          offer.terms_sha256 || E'\n' || pg_catalog.jsonb_build_object(
            'owner_id_type', offer.owner_id_type,
            'owner_id_country', offer.owner_id_country,
            'owner_id_number', offer.owner_id_number,
            'owner_id_expiry_date', p_owner_id_expiry_date
          )::text,
          'sha256'
        ), 'hex'),
        updated_at = now()
    where offer.id = new_offer_id
      and offer.owner_user_id = actor
    returning offer.terms_sha256 into new_hash;

  if new_hash is null then
    raise exception 'Lease offer could not be updated with owner document expiry.' using errcode='42501';
  end if;

  update public.lease_contract_offer_events as event
    set terms_sha256 = new_hash,
        signer_name = null
    where event.offer_id = new_offer_id
      and event.event_type = 'created';

  return result;
end;
$function$;

revoke all on function public.create_apartment_lease_offer(uuid,text,text,text,text,text,text,text,text,text,text,date,numeric,numeric,numeric,date,date,integer,text,text,text,text,text,boolean)
  from public, anon, authenticated;
revoke all on function public.create_apartment_lease_offer(uuid,text,text,text,text,date,text,text,text,text,text,text,date,numeric,numeric,numeric,date,date,integer,text,text,text,text,text,boolean)
  from public, anon;
grant execute on function public.create_apartment_lease_offer(uuid,text,text,text,text,date,text,text,text,text,text,text,date,numeric,numeric,numeric,date,date,integer,text,text,text,text,text,boolean)
  to authenticated;

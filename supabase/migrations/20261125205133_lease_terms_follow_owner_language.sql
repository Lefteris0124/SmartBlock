create or replace function public.stamp_smartblock_lease_terms()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  property_row public.properties%rowtype;
  owner_language text;
  terms text;
begin
  select profile.preferred_language into owner_language
  from public.profiles as profile
  where profile.id = new.owner_user_id;

  select case when owner_language = 'en' then settings.terms_en else settings.terms_el end
    into terms
  from public.smartblock_lease_term_settings as settings
  where settings.setting_key = 'default';
  if terms is null then
    raise exception 'SmartBlock rental terms are not configured.';
  end if;

  new.payment_terms := terms;
  select * into property_row
  from public.properties as property
  where property.id = new.property_id;

  new.terms_sha256 := pg_catalog.encode(
    extensions.digest(
      pg_catalog.jsonb_build_object(
        'property_id', new.property_id,
        'property_name', property_row.name,
        'property_address', pg_catalog.concat_ws(', ', property_row.address, property_row.city, property_row.country),
        'unit_reference', pg_catalog.btrim(new.unit_reference),
        'owner_user_id', new.owner_user_id,
        'owner_name', pg_catalog.btrim(new.owner_name),
        'owner_email', new.owner_email,
        'owner_id_type', pg_catalog.btrim(new.owner_id_type),
        'owner_id_number', pg_catalog.btrim(new.owner_id_number),
        'tenant_name', pg_catalog.btrim(new.tenant_name),
        'tenant_email', pg_catalog.lower(pg_catalog.btrim(new.tenant_email)),
        'monthly_rent', new.monthly_rent,
        'deposit_amount', new.deposit_amount,
        'common_charges', new.common_charges,
        'currency', 'EUR',
        'start_date', new.start_date,
        'end_date', new.end_date,
        'rent_due_day', new.rent_due_day,
        'furniture_and_inventory', coalesce(new.furniture_and_inventory, ''),
        'included_services', coalesce(new.included_services, ''),
        'special_terms', coalesce(new.special_terms, ''),
        'guarantor_name', coalesce(new.guarantor_name, ''),
        'guarantor_terms', coalesce(new.guarantor_terms, ''),
        'payment_terms', new.payment_terms
      )::text,
      'sha256'
    ),
    'hex'
  );
  return new;
end;
$function$;

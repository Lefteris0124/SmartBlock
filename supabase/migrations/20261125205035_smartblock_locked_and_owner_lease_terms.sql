create table if not exists public.smartblock_lease_term_settings (
  setting_key text primary key check (setting_key = 'default'),
  terms_el text not null,
  terms_en text not null,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

insert into public.smartblock_lease_term_settings(setting_key, terms_el, terms_en)
values (
  'default',
  'Τα συμβαλλόμενα μέρη αναγνωρίζουν το SmartBlock ως διαχειριστή της μίσθωσης για τις υπηρεσίες που παρέχει μέσω της εφαρμογής. Το ενοίκιο, η εγγύηση και οι συμφωνημένες πληρωμές καταχωρούνται και διεκπεραιώνονται μέσω του SmartBlock με τους διαθέσιμους τρόπους πληρωμής. Το SmartBlock παρέχει το ψηφιακό κανάλι διαχείρισης και δεν αποτελεί συμβαλλόμενο μέρος της μίσθωσης.',
  'The parties recognize SmartBlock as the rental administrator for the services it provides through the application. Rent, the deposit, and agreed payments are recorded and processed through SmartBlock using the available payment methods. SmartBlock provides the digital management channel and is not a party to the rental agreement.'
)
on conflict (setting_key) do nothing;

create table if not exists public.lease_owner_term_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  terms text not null default '',
  updated_at timestamptz not null default now(),
  constraint lease_owner_term_preferences_terms_length check (char_length(terms) <= 10000)
);

alter table public.smartblock_lease_term_settings enable row level security;
alter table public.lease_owner_term_preferences enable row level security;
revoke all on public.smartblock_lease_term_settings from public, anon, authenticated;
revoke all on public.lease_owner_term_preferences from public, anon, authenticated;

create or replace function public.get_owner_lease_term_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  owner_terms text;
  locked_terms_el text;
  locked_terms_en text;
begin
  if actor is null then
    raise exception 'Sign in to view rental term settings.' using errcode='42501';
  end if;

  select coalesce(pref.terms, '') into owner_terms
  from public.lease_owner_term_preferences as pref
  where pref.user_id = actor;
  if owner_terms is null then owner_terms := ''; end if;

  select settings.terms_el, settings.terms_en
    into locked_terms_el, locked_terms_en
  from public.smartblock_lease_term_settings as settings
  where settings.setting_key = 'default';

  return pg_catalog.jsonb_build_object(
    'owner_terms', coalesce(owner_terms, ''),
    'smartblock_terms_el', coalesce(locked_terms_el, ''),
    'smartblock_terms_en', coalesce(locked_terms_en, '')
  );
end;
$function$;

create or replace function public.save_owner_lease_terms(p_terms text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
begin
  if actor is null then
    raise exception 'Sign in to save your default rental terms.' using errcode='42501';
  end if;
  if char_length(coalesce(p_terms, '')) > 10000 then
    raise exception 'Default rental terms are limited to 10,000 characters.' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.properties as property
    where public.can_manage_property(property.id)
  ) then
    raise exception 'Only an owner or authorized property manager can save default rental terms.' using errcode='42501';
  end if;

  insert into public.lease_owner_term_preferences(user_id, terms, updated_at)
  values (actor, coalesce(p_terms, ''), now())
  on conflict (user_id) do update
    set terms = excluded.terms, updated_at = excluded.updated_at;
end;
$function$;

create or replace function public.admin_get_smartblock_lease_terms()
returns table(terms_el text, terms_en text, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not public.is_smartblock_admin() then
    raise exception 'SmartBlock admin access is required.' using errcode='42501';
  end if;
  return query
    select settings.terms_el, settings.terms_en, settings.updated_at
    from public.smartblock_lease_term_settings as settings
    where settings.setting_key = 'default';
end;
$function$;

create or replace function public.admin_update_smartblock_lease_terms(
  p_terms_el text,
  p_terms_en text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.is_smartblock_admin() then
    raise exception 'SmartBlock admin access is required.' using errcode='42501';
  end if;
  if char_length(btrim(coalesce(p_terms_el, ''))) < 20
     or char_length(btrim(coalesce(p_terms_en, ''))) < 20
     or char_length(p_terms_el) > 10000
     or char_length(p_terms_en) > 10000 then
    raise exception 'Enter both language versions (20 to 10,000 characters).' using errcode='22023';
  end if;
  update public.smartblock_lease_term_settings
     set terms_el = btrim(p_terms_el),
         terms_en = btrim(p_terms_en),
         updated_by = (select auth.uid()),
         updated_at = now()
   where setting_key = 'default';
end;
$function$;

create or replace function public.stamp_smartblock_lease_terms()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  property_row public.properties%rowtype;
  terms text;
begin
  select settings.terms_el into terms
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
        'property_address', pg_catalog.concat_ws(
          ', ', property_row.address, property_row.city, property_row.country
        ),
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

drop trigger if exists stamp_smartblock_lease_terms on public.lease_contract_offers;
create trigger stamp_smartblock_lease_terms
before insert on public.lease_contract_offers
for each row execute function public.stamp_smartblock_lease_terms();

revoke all on function public.get_owner_lease_term_settings() from public, anon;
grant execute on function public.get_owner_lease_term_settings() to authenticated;
revoke all on function public.save_owner_lease_terms(text) from public, anon;
grant execute on function public.save_owner_lease_terms(text) to authenticated;
revoke all on function public.admin_get_smartblock_lease_terms() from public, anon, authenticated;
grant execute on function public.admin_get_smartblock_lease_terms() to authenticated;
revoke all on function public.admin_update_smartblock_lease_terms(text,text) from public, anon, authenticated;
grant execute on function public.admin_update_smartblock_lease_terms(text,text) to authenticated;
revoke all on function public.stamp_smartblock_lease_terms() from public, anon, authenticated;

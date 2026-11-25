create or replace function public.search_owner_tenant_suggestions(p_search text)
returns table (
  tenant_name text,
  tenant_email text,
  tenant_phone_e164 text
)
language sql
stable
security definer
set search_path = ''
as $function$
  with candidates as (
    select
      coalesce(nullif(btrim(o.tenant_name), ''), o.tenant_email) as tenant_name,
      lower(btrim(o.tenant_email)) as tenant_email,
      o.tenant_phone_e164,
      o.created_at
    from public.lease_contract_offers as o
    where o.owner_user_id = auth.uid()
      and nullif(btrim(o.tenant_email), '') is not null

    union all

    select
      coalesce(nullif(btrim(r.tenant_name), ''), u.email) as tenant_name,
      lower(btrim(u.email)) as tenant_email,
      r.tenant_phone_e164,
      r.created_at
    from public.property_rent_contracts as r
    join auth.users as u on u.id = r.tenant_user_id
    where public.can_manage_property(r.property_id)
      and nullif(btrim(u.email), '') is not null
  ),
  matches as (
    select c.*
    from candidates as c
    where auth.uid() is not null
      and length(btrim(coalesce(p_search, ''))) >= 2
      and strpos(c.tenant_email, lower(btrim(p_search))) > 0
  ),
  newest_per_email as (
    select distinct on (m.tenant_email)
      m.tenant_name, m.tenant_email, m.tenant_phone_e164, m.created_at
    from matches as m
    order by m.tenant_email, m.created_at desc nulls last
  )
  select n.tenant_name, n.tenant_email, n.tenant_phone_e164
  from newest_per_email as n
  order by n.created_at desc nulls last, n.tenant_email
  limit 12;
$function$;

revoke all on function public.search_owner_tenant_suggestions(text) from public, anon;
grant execute on function public.search_owner_tenant_suggestions(text) to authenticated;

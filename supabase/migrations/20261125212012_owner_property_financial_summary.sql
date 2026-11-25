create or replace function public.my_owner_property_financial_summary(
  p_property_id uuid default null,
  p_from date default null,
  p_to date default null
)
returns table (
  property_id uuid,
  property_name text,
  property_address text,
  ownership_percent numeric,
  rent_collected_gross numeric,
  smartblock_fee numeric,
  rent_net_to_property numeric,
  repairs_paid numeric,
  maintenance_paid numeric,
  other_expenses_paid numeric,
  total_expenses_paid numeric,
  approved_expenses_pending numeric,
  owner_payout_pending numeric,
  owner_payout_paid numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;
  if p_from is not null and p_to is not null and p_from > p_to then
    raise exception 'Invalid accounting period.' using errcode = '22023';
  end if;

  return query
  with owner_scope as (
    select distinct
      po.id as property_owner_id,
      po.property_id,
      po.ownership_percentage
    from public.property_owners po
    join public.organization_members om
      on om.organization_id = po.organization_id
    where om.user_id = v_user_id
      and om.membership_status = 'active'
      and po.ownership_status = 'active'
      and po.ownership_percentage > 0
      and (p_property_id is null or po.property_id = p_property_id)
  ),
  owner_share as (
    select
      os.property_id,
      sum(os.ownership_percentage)::numeric as ownership_percent
    from owner_scope os
    group by os.property_id
  ),
  rent_totals as (
    select
      pr.property_id,
      sum(pr.amount * sh.ownership_percent / 100)::numeric(14,2) as gross_amount,
      sum(coalesce(pr.platform_fee_amount, 0) * sh.ownership_percent / 100)::numeric(14,2) as fee_amount,
      sum(coalesce(pr.net_to_property_amount, pr.amount - coalesce(pr.platform_fee_amount, 0))
          * sh.ownership_percent / 100)::numeric(14,2) as net_amount
    from public.property_payment_records pr
    join owner_share sh on sh.property_id = pr.property_id
    where pr.rent_installment_id is not null
      and (p_from is null or pr.paid_at::date >= p_from)
      and (p_to is null or pr.paid_at::date <= p_to)
    group by pr.property_id
  ),
  expense_totals as (
    select
      e.property_id,
      sum(case
        when e.status = 'paid'
         and lower(coalesce(e.category, '') || ' ' || coalesce(e.description, ''))
              ~ '(damage|repair|βλαβ|επισκευ)'
        then e.amount * sh.ownership_percent / 100 else 0 end)::numeric(14,2) as repairs_amount,
      sum(case
        when e.status = 'paid'
         and lower(coalesce(e.category, '') || ' ' || coalesce(e.description, ''))
              ~ '(maint|συντηρ)'
        then e.amount * sh.ownership_percent / 100 else 0 end)::numeric(14,2) as maintenance_amount,
      sum(case
        when e.status = 'paid'
         and lower(coalesce(e.category, '') || ' ' || coalesce(e.description, ''))
              !~ '(damage|repair|βλαβ|επισκευ|maint|συντηρ)'
        then e.amount * sh.ownership_percent / 100 else 0 end)::numeric(14,2) as other_amount,
      sum(case when e.status = 'paid'
        then e.amount * sh.ownership_percent / 100 else 0 end)::numeric(14,2) as total_paid,
      sum(case when e.status = 'approved'
        then e.amount * sh.ownership_percent / 100 else 0 end)::numeric(14,2) as pending_amount
    from public.property_operating_expenses e
    join owner_share sh on sh.property_id = e.property_id
    where e.status in ('paid', 'approved')
      and (p_from is null or coalesce(e.paid_at::date, e.expense_date) >= p_from)
      and (p_to is null or coalesce(e.paid_at::date, e.expense_date) <= p_to)
    group by e.property_id
  ),
  payouts as (
    select
      po.property_id,
      sum(case when q.status = 'paid' or q.paid_at is not null
          then q.amount_due else 0 end)::numeric(14,2) as paid_amount,
      sum(case when q.status <> 'paid' and q.paid_at is null
          then q.amount_due else 0 end)::numeric(14,2) as pending_amount
    from owner_scope os
    join public.property_owners po on po.id = os.property_owner_id
    join public.owner_payout_queue q on q.property_owner_id = po.id
    where (p_from is null or coalesce(q.paid_at::date, q.created_at::date) >= p_from)
      and (p_to is null or coalesce(q.paid_at::date, q.created_at::date) <= p_to)
    group by po.property_id
  )
  select
    p.id,
    p.name,
    concat_ws(', ', p.address, p.city, p.country),
    sh.ownership_percent,
    coalesce(rt.gross_amount, 0),
    coalesce(rt.fee_amount, 0),
    coalesce(rt.net_amount, 0),
    coalesce(ex.repairs_amount, 0),
    coalesce(ex.maintenance_amount, 0),
    coalesce(ex.other_amount, 0),
    coalesce(ex.total_paid, 0),
    coalesce(ex.pending_amount, 0),
    coalesce(q.pending_amount, 0),
    coalesce(q.paid_amount, 0)
  from owner_share sh
  join public.properties p on p.id = sh.property_id
  left join rent_totals rt on rt.property_id = p.id
  left join expense_totals ex on ex.property_id = p.id
  left join payouts q on q.property_id = p.id
  order by p.name;
end;
$function$;

revoke all on function public.my_owner_property_financial_summary(uuid,date,date) from public, anon;
grant execute on function public.my_owner_property_financial_summary(uuid,date,date) to authenticated;
alter table public.property_apartments
  add column if not exists property_owner_id uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='property_owners_id_property_unique') then
    alter table public.property_owners
      add constraint property_owners_id_property_unique unique (id, property_id);
  end if;
  if not exists (select 1 from pg_constraint where conname='property_apartments_owner_property_fkey') then
    alter table public.property_apartments
      add constraint property_apartments_owner_property_fkey
      foreign key (property_owner_id, property_id)
      references public.property_owners(id, property_id)
      on delete restrict;
  end if;
end $$;

create index if not exists property_apartments_owner_property_idx
  on public.property_apartments(property_owner_id, property_id);

drop trigger if exists property_apartments_audit on public.property_apartments;
create trigger property_apartments_audit
  after insert or update or delete on public.property_apartments
  for each row execute function public.capture_property_management_audit();

create or replace function public.set_property_apartment_owner(
  p_apartment_id uuid,
  p_property_owner_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_property_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;

  select pa.property_id into target_property_id
  from public.property_apartments pa
  where pa.id = p_apartment_id;

  if target_property_id is null or not public.can_manage_property(target_property_id) then
    raise exception 'Property management access is required.' using errcode='42501';
  end if;

  if p_property_owner_id is not null and not exists (
    select 1 from public.property_owners po
    where po.id = p_property_owner_id
      and po.property_id = target_property_id
      and po.ownership_status = 'active'
  ) then
    raise exception 'Choose an active owner for the same property.';
  end if;

  update public.property_apartments
  set property_owner_id = p_property_owner_id,
      updated_at = now()
  where id = p_apartment_id and property_id = target_property_id;

  return found;
end
$function$;

revoke all on function public.set_property_apartment_owner(uuid,uuid) from public, anon;
grant execute on function public.set_property_apartment_owner(uuid,uuid) to authenticated;

create or replace function public.get_property_shared_financial_overview(p_property_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_total_due numeric := 0;
  v_total_paid numeric := 0;
  v_allocated_due numeric := 0;
  v_allocated_paid numeric := 0;
  v_paid_expenses numeric := 0;
  v_damage_repair numeric := 0;
  v_maintenance numeric := 0;
  v_opening_balance numeric := 0;
  v_apartments jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null or not public.can_access_property(p_property_id) then
    raise exception 'Property access is required.' using errcode='42501';
  end if;

  select coalesce(sum(ce.amount_due),0), coalesce(sum(ce.amount_paid),0)
    into v_total_due, v_total_paid
  from public.property_charge_entries ce
  join public.property_charge_runs cr on cr.id=ce.run_id
  where cr.property_id=p_property_id;

  select coalesce(fs.opening_balance,0) into v_opening_balance
  from public.property_finance_settings fs
  where fs.property_id=p_property_id;
  v_opening_balance := coalesce(v_opening_balance,0);

  select
    coalesce(sum(e.amount) filter (where e.status='paid'),0),
    coalesce(sum(e.amount) filter (where e.status='paid' and e.category='damage_repair'),0),
    coalesce(sum(e.amount) filter (where e.status='paid' and e.category='maintenance'),0)
  into v_paid_expenses, v_damage_repair, v_maintenance
  from public.property_operating_expenses e
  where e.property_id=p_property_id;

  with owner_mapping as (
    select po.id as owner_id,
           po.apartment_count,
           po.area_sqm as declared_area,
           count(pa.id)::integer as mapped_count,
           coalesce(sum(pa.area_sqm),0) as mapped_area
    from public.property_owners po
    left join public.property_apartments pa
      on pa.property_owner_id=po.id and pa.property_id=p_property_id
    where po.property_id=p_property_id and po.ownership_status='active'
    group by po.id,po.apartment_count,po.area_sqm
  ),
  eligible_owner_mapping as (
    select *
    from owner_mapping
    where apartment_count is not null
      and apartment_count > 0
      and mapped_count = apartment_count
      and mapped_area > 0
      and (declared_area is null or abs(mapped_area-declared_area) <= 0.10)
  ),
  allocations as (
    select pa.id as apartment_id,
           ce.amount_due * case
             when cr.allocation_method='per_apartment'
               then 1::numeric / nullif(om.mapped_count,0)
             else pa.area_sqm / nullif(om.mapped_area,0)
           end as amount_due,
           ce.amount_paid * case
             when cr.allocation_method='per_apartment'
               then 1::numeric / nullif(om.mapped_count,0)
             else pa.area_sqm / nullif(om.mapped_area,0)
           end as amount_paid
    from public.property_charge_entries ce
    join public.property_charge_runs cr on cr.id=ce.run_id
    join public.property_owners po on po.id=ce.property_owner_id
      and po.property_id=cr.property_id and po.ownership_status='active'
    join eligible_owner_mapping om on om.owner_id=po.id
    join public.property_apartments pa on pa.property_owner_id=po.id
      and pa.property_id=p_property_id
    where cr.property_id=p_property_id
  ),
  unit_totals as (
    select pa.id, pa.apartment_number,
      exists (
        select 1 from public.property_owners po
        where po.id=pa.property_owner_id and po.property_id=p_property_id
          and po.ownership_status='active'
      ) as owner_assigned,
      exists (
        select 1 from eligible_owner_mapping om
        where om.owner_id=pa.property_owner_id
      ) as allocation_complete,
      coalesce(sum(a.amount_due),0) as amount_due,
      coalesce(sum(a.amount_paid),0) as amount_paid
    from public.property_apartments pa
    left join allocations a on a.apartment_id=pa.id
    where pa.property_id=p_property_id
    group by pa.id,pa.apartment_number,pa.property_owner_id
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'apartment_number', apartment_number,
      'owner_assigned', owner_assigned,
      'allocation_complete', allocation_complete,
      'amount_due', round(amount_due,2),
      'amount_paid', round(amount_paid,2),
      'amount_outstanding', round(greatest(amount_due-amount_paid,0),2),
      'status', case
        when owner_assigned and not allocation_complete then 'needs_mapping'
        when amount_due <= 0 then 'not_charged'
        when amount_due-amount_paid <= 0.005 then 'paid'
        when amount_paid > 0 then 'partial'
        else 'unpaid'
      end
    ) order by apartment_number), '[]'::jsonb),
    coalesce(sum(amount_due),0),
    coalesce(sum(amount_paid),0)
  into v_apartments,v_allocated_due,v_allocated_paid
  from unit_totals;

  return jsonb_build_object(
    'common_charges_due', round(v_total_due,2),
    'common_charges_paid', round(v_total_paid,2),
    'common_charges_outstanding', round(greatest(v_total_due-v_total_paid,0),2),
    'damage_repair_paid', round(v_damage_repair,2),
    'maintenance_paid', round(v_maintenance,2),
    'other_operating_expenses_paid', round(greatest(v_paid_expenses-v_damage_repair-v_maintenance,0),2),
    'opening_balance', round(v_opening_balance,2),
    'operating_expenses_paid', round(v_paid_expenses,2),
    'estimated_common_fund', round(v_opening_balance+v_total_paid-v_paid_expenses,2),
    'unallocated_common_charges_due', round(greatest(v_total_due-v_allocated_due,0),2),
    'unallocated_common_charges_paid', round(greatest(v_total_paid-v_allocated_paid,0),2),
    'apartments', v_apartments
  );
end
$function$;

revoke all on function public.get_property_shared_financial_overview(uuid) from public, anon;
grant execute on function public.get_property_shared_financial_overview(uuid) to authenticated;

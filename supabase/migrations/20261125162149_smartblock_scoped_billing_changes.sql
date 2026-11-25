alter table public.smartblock_billing_schedules
  add column if not exists scope_type text not null default 'all',
  add column if not exists scope_ids uuid[] not null default '{}';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.smartblock_billing_schedules'::regclass
      and conname = 'smartblock_billing_schedules_scope_check'
  ) then
    alter table public.smartblock_billing_schedules
      add constraint smartblock_billing_schedules_scope_check
      check (
        scope_type in ('all', 'users', 'properties')
        and (
          (scope_type = 'all' and cardinality(scope_ids) = 0)
          or (scope_type in ('users', 'properties') and cardinality(scope_ids) > 0)
        )
      );
  end if;
end
$$;

create or replace function public.admin_list_smartblock_billing_targets(p_scope_type text)
returns table(target_id uuid, display_name text, detail text)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null or not public.is_smartblock_admin() then
    raise exception 'SmartBlock administrator access is required.' using errcode = '42501';
  end if;

  if p_scope_type = 'users' then
    return query
      select distinct
        account.id,
        coalesce(nullif(btrim(profile.full_name), ''), account.email, 'SmartBlock user')::text,
        account.email::text
      from auth.users as account
      left join public.profiles as profile on profile.id = account.id
      where exists (
        select 1
        from public.properties as property_row
        where property_row.property_type = 'building'
          and property_row.approval_status = 'approved'
          and (
            property_row.manager_user_id = account.id
            or exists (
              select 1
              from public.property_owners as owner_row
              join public.organization_members as member
                on member.organization_id = owner_row.organization_id
              where owner_row.property_id = property_row.id
                and owner_row.ownership_status = 'active'
                and member.membership_status = 'active'
                and member.member_role in ('owner', 'representative')
                and member.user_id = account.id
            )
          )
      )
      order by 2, 1;
  elsif p_scope_type = 'properties' then
    return query
      select
        property_row.id,
        property_row.name,
        nullif(concat_ws(' · ', property_row.address, property_row.city, property_row.country), '')
      from public.properties as property_row
      where property_row.property_type = 'building'
        and property_row.approval_status = 'approved'
      order by property_row.name, property_row.city, property_row.id;
  else
    raise exception 'Select users or properties as the billing scope.' using errcode = '22023';
  end if;
end;
$function$;

revoke all on function public.admin_list_smartblock_billing_targets(text) from public, anon;
grant execute on function public.admin_list_smartblock_billing_targets(text) to authenticated;

create or replace function public.admin_schedule_smartblock_billing_change(
  p_apartment_monthly_eur numeric,
  p_online_payment_fee_percent numeric,
  p_effective_on date,
  p_scope_type text,
  p_scope_ids uuid[]
)
returns table(schedule_id uuid, notified_owner_count integer)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  normalized_scope_ids uuid[] := coalesce(p_scope_ids, '{}'::uuid[]);
  matching_target_count integer := 0;
  new_schedule_id uuid;
  notice_count integer := 0;
begin
  if current_user_id is null or not public.is_smartblock_admin() then
    raise exception 'SmartBlock administrator access is required.' using errcode = '42501';
  end if;

  if p_apartment_monthly_eur is null or p_apartment_monthly_eur < 0
     or p_online_payment_fee_percent is null
     or p_online_payment_fee_percent not between 0 and 100
     or p_effective_on is null or p_effective_on < current_date then
    raise exception 'Enter valid prices and an effective date of today or later.'
      using errcode = '22023';
  end if;

  if p_scope_type not in ('all', 'users', 'properties')
     or (p_scope_type = 'all' and cardinality(normalized_scope_ids) <> 0)
     or (p_scope_type in ('users', 'properties') and cardinality(normalized_scope_ids) = 0) then
    raise exception 'Choose all users or at least one account/property.'
      using errcode = '22023';
  end if;

  if p_scope_type = 'users' then
    select count(distinct account.id)::integer into matching_target_count
    from auth.users as account
    where account.id = any(normalized_scope_ids)
      and exists (
        select 1
        from public.properties as property_row
        where property_row.property_type = 'building'
          and property_row.approval_status = 'approved'
          and (
            property_row.manager_user_id = account.id
            or exists (
              select 1
              from public.property_owners as owner_row
              join public.organization_members as member
                on member.organization_id = owner_row.organization_id
              where owner_row.property_id = property_row.id
                and owner_row.ownership_status = 'active'
                and member.membership_status = 'active'
                and member.member_role in ('owner', 'representative')
                and member.user_id = account.id
            )
          )
      );
  elsif p_scope_type = 'properties' then
    select count(distinct property_row.id)::integer into matching_target_count
    from public.properties as property_row
    where property_row.id = any(normalized_scope_ids)
      and property_row.property_type = 'building'
      and property_row.approval_status = 'approved';
  end if;

  if p_scope_type <> 'all' and matching_target_count <> cardinality(normalized_scope_ids) then
    raise exception 'One or more selected billing targets are unavailable.'
      using errcode = '22023';
  end if;

  insert into public.smartblock_billing_schedules (
    apartment_monthly_eur, online_payment_fee_percent, effective_on, created_by,
    scope_type, scope_ids
  ) values (
    p_apartment_monthly_eur, p_online_payment_fee_percent, p_effective_on, current_user_id,
    p_scope_type, normalized_scope_ids
  ) returning id into new_schedule_id;

  insert into public.property_billing_notifications (
    schedule_id, property_id, recipient_id,
    apartment_monthly_eur, online_payment_fee_percent, effective_on
  )
  select new_schedule_id, property_row.id, recipients.user_id,
         p_apartment_monthly_eur, p_online_payment_fee_percent, p_effective_on
  from public.properties as property_row
  cross join lateral (
    select property_row.manager_user_id as user_id
    where property_row.manager_user_id is not null
      and (p_scope_type <> 'users' or property_row.manager_user_id = any(normalized_scope_ids))
    union
    select member.user_id
    from public.property_owners as owner_row
    join public.organization_members as member
      on member.organization_id = owner_row.organization_id
    where owner_row.property_id = property_row.id
      and owner_row.ownership_status = 'active'
      and member.membership_status = 'active'
      and member.member_role in ('owner', 'representative')
      and member.user_id is not null
      and (p_scope_type <> 'users' or member.user_id = any(normalized_scope_ids))
  ) as recipients
  where property_row.property_type = 'building'
    and property_row.approval_status = 'approved'
    and (
      p_scope_type = 'all'
      or (p_scope_type = 'properties' and property_row.id = any(normalized_scope_ids))
      or (
        p_scope_type = 'users'
        and (
          property_row.manager_user_id = any(normalized_scope_ids)
          or exists (
            select 1
            from public.property_owners as owner_row
            join public.organization_members as member
              on member.organization_id = owner_row.organization_id
            where owner_row.property_id = property_row.id
              and owner_row.ownership_status = 'active'
              and member.membership_status = 'active'
              and member.member_role in ('owner', 'representative')
              and member.user_id = any(normalized_scope_ids)
          )
        )
      )
    )
  on conflict (schedule_id, property_id, recipient_id) do nothing;

  get diagnostics notice_count = row_count;
  schedule_id := new_schedule_id;
  notified_owner_count := notice_count;
  return next;
end;
$function$;

revoke all on function public.admin_schedule_smartblock_billing_change(numeric, numeric, date, text, uuid[]) from public, anon;
grant execute on function public.admin_schedule_smartblock_billing_change(numeric, numeric, date, text, uuid[]) to authenticated;

create or replace function public.smartblock_current_billing_rates(p_property_id uuid)
returns table(apartment_monthly_eur numeric, online_payment_fee_percent numeric, effective_on date)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'Sign in is required.' using errcode = '42501';
  end if;

  if p_property_id is not null
     and not public.is_smartblock_admin()
     and not public.can_manage_property(p_property_id)
     and not exists (
       select 1
       from public.property_owners as owner_row
       join public.organization_members as member
         on member.organization_id = owner_row.organization_id
       where owner_row.property_id = p_property_id
         and owner_row.ownership_status = 'active'
         and member.membership_status = 'active'
         and member.user_id = current_user_id
     ) then
    raise exception 'You cannot view billing rates for this property.' using errcode = '42501';
  end if;

  return query
    select schedule.apartment_monthly_eur,
           schedule.online_payment_fee_percent,
           schedule.effective_on
    from public.smartblock_billing_schedules as schedule
    where schedule.status = 'scheduled'
      and schedule.effective_on <= current_date
      and (
        schedule.scope_type = 'all'
        or (
          p_property_id is not null
          and schedule.scope_type = 'properties'
          and p_property_id = any(schedule.scope_ids)
        )
        or (
          p_property_id is not null
          and schedule.scope_type = 'users'
          and exists (
            select 1
            from public.properties as property_row
            where property_row.id = p_property_id
              and (
                property_row.manager_user_id = any(schedule.scope_ids)
                or exists (
                  select 1
                  from public.property_owners as owner_row
                  join public.organization_members as member
                    on member.organization_id = owner_row.organization_id
                  where owner_row.property_id = property_row.id
                    and owner_row.ownership_status = 'active'
                    and member.membership_status = 'active'
                    and member.member_role in ('owner', 'representative')
                    and member.user_id = any(schedule.scope_ids)
                )
              )
          )
        )
      )
    order by
      case schedule.scope_type when 'properties' then 0 when 'users' then 1 else 2 end,
      schedule.effective_on desc,
      schedule.created_at desc
    limit 1;

  if not found then
    return query
      select settings.apartment_monthly_eur,
             settings.online_payment_fee_percent,
             current_date
      from public.smartblock_billing_settings as settings
      where settings.singleton = true;
  end if;
end;
$function$;

revoke all on function public.smartblock_current_billing_rates(uuid) from public, anon;
grant execute on function public.smartblock_current_billing_rates(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.prepare_property_online_payment(p_target_type text, p_target_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
  target_property_id uuid;
  target_amount numeric(12,2);
  amount_paid numeric(12,2);
  target_label text;
  owner_organization_id uuid;
  payment_row public.property_online_payment_sessions%ROWTYPE;
  balance numeric(12,2);
  active_fee_percent numeric(5,2);
  fee_amount numeric(12,2);
  property_amount numeric(12,2);
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
  END IF;
  IF p_target_type IS NULL OR p_target_type NOT IN ('charge','rent') THEN
    RAISE EXCEPTION 'Invalid payment type.';
  END IF;

  IF p_target_type = 'charge' THEN
    SELECT run.property_id, entry.amount_due, entry.amount_paid,
           owner.organization_id, 'Κοινόχρηστα · ' || run.period_label
    INTO target_property_id, target_amount, amount_paid,
         owner_organization_id, target_label
    FROM public.property_charge_entries AS entry
    JOIN public.property_charge_runs AS run ON run.id = entry.run_id
    JOIN public.property_owners AS owner ON owner.id = entry.property_owner_id
    WHERE entry.id = p_target_id
    FOR UPDATE OF entry;
    IF target_property_id IS NULL OR NOT (
      public.can_access_organization(owner_organization_id)
      OR public.can_manage_property(target_property_id)
    ) THEN
      RAISE EXCEPTION 'You cannot pay this common charge.' USING ERRCODE = '42501';
    END IF;
  ELSE
    SELECT contract.property_id, installment.amount_due, installment.amount_paid,
           'Ενοίκιο · ' || contract.unit_reference || ' · ' || installment.period_start::text
    INTO target_property_id, target_amount, amount_paid, target_label
    FROM public.property_rent_installments AS installment
    JOIN public.property_rent_contracts AS contract ON contract.id = installment.contract_id
    WHERE installment.id = p_target_id
    FOR UPDATE OF installment;
    IF target_property_id IS NULL OR NOT public.can_manage_property(target_property_id) THEN
      RAISE EXCEPTION 'Property management access is required to pay this rent installment.'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  balance := target_amount - amount_paid;
  IF balance <= 0 THEN RAISE EXCEPTION 'This balance is already paid.'; END IF;

  UPDATE public.property_online_payment_sessions
  SET status = 'expired'
  WHERE target_type = p_target_type AND target_id = p_target_id
    AND ((status = 'open' AND expires_at <= now())
      OR (status = 'creating' AND created_at < now() - interval '5 minutes'));

  SELECT * INTO payment_row
  FROM public.property_online_payment_sessions
  WHERE target_type = p_target_type AND target_id = p_target_id
    AND status IN ('creating','open') AND expires_at > now()
  FOR UPDATE;

  IF FOUND THEN
    IF payment_row.created_by <> current_user_id THEN
      RAISE EXCEPTION 'A checkout for this balance is already open.';
    END IF;
    RETURN jsonb_build_object(
      'id', payment_row.id,
      'amount', payment_row.amount,
      'currency', payment_row.currency,
      'description', target_label,
      'status', payment_row.status,
      'is_new', false,
      'platform_fee_percent', payment_row.platform_fee_percent,
      'platform_fee_amount', payment_row.platform_fee_amount,
      'net_to_property_amount', payment_row.net_to_property_amount,
      'stripe_checkout_session_id', payment_row.stripe_checkout_session_id
    );
  END IF;

  SELECT rates.online_payment_fee_percent INTO active_fee_percent
  FROM public.smartblock_current_billing_rates(target_property_id) AS rates;
  active_fee_percent := COALESCE(active_fee_percent, 0);
  fee_amount := round(balance * active_fee_percent / 100, 2);
  property_amount := balance - fee_amount;

  INSERT INTO public.property_online_payment_sessions(
    property_id, target_type, target_id, amount, currency, status, created_by,
    platform_fee_percent, platform_fee_amount, net_to_property_amount
  ) VALUES (
    target_property_id, p_target_type, p_target_id, balance, 'EUR', 'creating', current_user_id,
    active_fee_percent, fee_amount, property_amount
  ) RETURNING * INTO payment_row;

  RETURN jsonb_build_object(
    'id', payment_row.id,
    'amount', payment_row.amount,
    'currency', payment_row.currency,
    'description', target_label,
    'status', payment_row.status,
    'is_new', true,
    'platform_fee_percent', payment_row.platform_fee_percent,
    'platform_fee_amount', payment_row.platform_fee_amount,
    'net_to_property_amount', payment_row.net_to_property_amount,
    'stripe_checkout_session_id', payment_row.stripe_checkout_session_id
  );
END;
$function$


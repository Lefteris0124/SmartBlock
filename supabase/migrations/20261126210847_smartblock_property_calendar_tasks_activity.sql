create table if not exists public.property_calendar_events (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 140),
  description text not null default '',
  event_type text not null default 'other'
    check (event_type in ('inspection','maintenance','service','payment_deadline','meeting','other')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  all_day boolean not null default true,
  status text not null default 'scheduled'
    check (status in ('scheduled','completed','cancelled')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_by uuid not null default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at)
);

create table if not exists public.property_tasks (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 140),
  description text not null default '',
  category text not null default 'other'
    check (category in ('maintenance','repair','cleaning','inspection','administration','other')),
  assigned_provider text not null default '',
  assigned_contact text not null default '',
  due_on date,
  priority text not null default 'normal'
    check (priority in ('low','normal','high','urgent')),
  status text not null default 'open'
    check (status in ('open','in_progress','blocked','completed','cancelled')),
  linked_service_request_id uuid references public.property_service_requests(id) on delete set null,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_by uuid not null default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists property_calendar_events_property_start_idx
  on public.property_calendar_events(property_id, starts_at);
create index if not exists property_tasks_property_due_idx
  on public.property_tasks(property_id, due_on);
create index if not exists property_tasks_service_request_idx
  on public.property_tasks(linked_service_request_id)
  where linked_service_request_id is not null;
create index if not exists property_management_audit_property_created_idx
  on public.property_management_audit(property_id, created_at desc);

alter table public.property_calendar_events enable row level security;
alter table public.property_tasks enable row level security;

grant select, insert, update, delete on public.property_calendar_events to authenticated;
grant select, insert, update, delete on public.property_tasks to authenticated;

drop policy if exists property_calendar_events_select on public.property_calendar_events;
create policy property_calendar_events_select on public.property_calendar_events
  for select to authenticated
  using (public.can_access_property(property_id));
drop policy if exists property_calendar_events_insert on public.property_calendar_events;
create policy property_calendar_events_insert on public.property_calendar_events
  for insert to authenticated
  with check (created_by = (select auth.uid()) and public.can_manage_property(property_id));
drop policy if exists property_calendar_events_update on public.property_calendar_events;
create policy property_calendar_events_update on public.property_calendar_events
  for update to authenticated
  using (public.can_manage_property(property_id))
  with check (public.can_manage_property(property_id));
drop policy if exists property_calendar_events_delete on public.property_calendar_events;
create policy property_calendar_events_delete on public.property_calendar_events
  for delete to authenticated
  using (public.can_manage_property(property_id));

drop policy if exists property_tasks_select on public.property_tasks;
create policy property_tasks_select on public.property_tasks
  for select to authenticated
  using (public.can_access_property(property_id));
drop policy if exists property_tasks_insert on public.property_tasks;
create policy property_tasks_insert on public.property_tasks
  for insert to authenticated
  with check (created_by = (select auth.uid()) and public.can_manage_property(property_id));
drop policy if exists property_tasks_update on public.property_tasks;
create policy property_tasks_update on public.property_tasks
  for update to authenticated
  using (public.can_manage_property(property_id))
  with check (public.can_manage_property(property_id));
drop policy if exists property_tasks_delete on public.property_tasks;
create policy property_tasks_delete on public.property_tasks
  for delete to authenticated
  using (public.can_manage_property(property_id));

do $$
declare
  t text;
  managed_tables text[] := array[
    'property_management_contracts',
    'property_management_contract_amendments',
    'property_management_services',
    'property_service_requests',
    'property_operating_expenses',
    'property_arrears_actions',
    'property_insurance_policies',
    'property_insurance_claims',
    'property_meetings',
    'property_handover_records',
    'property_management_policies',
    'property_calendar_events',
    'property_tasks',
    'property_charge_runs',
    'property_votes',
    'property_notes'
  ];
begin
  foreach t in array managed_tables loop
    execute format('drop trigger if exists %I on public.%I', t || '_audit', t);
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function public.capture_property_management_audit()',
      t || '_audit',
      t
    );
  end loop;
end $$;

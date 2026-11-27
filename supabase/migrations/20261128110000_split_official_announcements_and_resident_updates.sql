alter table public.property_notes
  add column if not exists post_type text not null default 'community_update';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'property_notes_post_type_check'
      and conrelid = 'public.property_notes'::regclass
  ) then
    alter table public.property_notes
      add constraint property_notes_post_type_check
      check (post_type in ('official_announcement', 'community_update'));
  end if;
end
$$;

drop policy if exists property_notes_insert on public.property_notes;
create policy property_notes_insert
on public.property_notes
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.can_access_property(property_id)
  and (
    post_type = 'community_update'
    or (
      post_type = 'official_announcement'
      and public.can_manage_property(property_id)
    )
  )
);

create or replace function public.notify_property_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  post_notification_type text;
  title_el text;
  title_en text;
begin
  if new.post_type = 'official_announcement' then
    post_notification_type := 'announcement';
    title_el := 'Νέα επίσημη ανακοίνωση';
    title_en := 'New building announcement';
  else
    post_notification_type := 'community_update';
    title_el := 'Νέα ενημέρωση ενοίκων';
    title_en := 'New resident update';
  end if;

  perform public.notify_property_audience(
    new.property_id,
    array['property', 'staff'],
    post_notification_type,
    title_el,
    title_en,
    left(new.body, 240),
    left(new.body, 240),
    'property_notes',
    new.id,
    new.created_by
  );
  return new;
end
$function$;

revoke all on function public.notify_property_post() from public, anon, authenticated;
drop trigger if exists smartblock_announcement_notification on public.property_notes;
create trigger smartblock_property_post_notification
after insert on public.property_notes
for each row execute function public.notify_property_post();

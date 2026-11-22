BEGIN;

CREATE TABLE IF NOT EXISTS public.user_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  property_id uuid REFERENCES public.properties(id) ON DELETE CASCADE,
  notification_type text NOT NULL,
  title_el text NOT NULL,
  title_en text NOT NULL,
  message_el text NOT NULL,
  message_en text NOT NULL,
  related_type text,
  related_id uuid,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, notification_type, related_type, related_id)
);
CREATE INDEX IF NOT EXISTS user_notifications_inbox_idx
  ON public.user_notifications(user_id, created_at DESC) WHERE NOT is_read;
ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE (is_read) ON public.user_notifications TO authenticated;
CREATE POLICY user_notifications_read_own ON public.user_notifications
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY user_notifications_mark_read_own ON public.user_notifications
  FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION public.notify_property_audience(
  p_property_id uuid, p_audience text[], p_type text,
  p_title_el text, p_title_en text, p_message_el text, p_message_en text,
  p_related_type text, p_related_id uuid, p_exclude_user uuid DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.user_notifications(
    user_id, property_id, notification_type, title_el, title_en,
    message_el, message_en, related_type, related_id
  )
  SELECT DISTINCT target.user_id, p_property_id, p_type, p_title_el, p_title_en,
         p_message_el, p_message_en, p_related_type, p_related_id
  FROM (
    SELECT staff.user_id FROM public.smartblock_staff AS staff
      WHERE staff.is_active AND 'staff' = ANY(p_audience)
    UNION
    SELECT member.user_id
    FROM public.property_owners AS owner
    JOIN public.organization_members AS member
      ON member.organization_id = owner.organization_id
     AND member.membership_status = 'active'
     AND member.user_id IS NOT NULL
    WHERE owner.property_id = p_property_id
      AND owner.ownership_status = 'active'
      AND ('owners' = ANY(p_audience) OR 'property' = ANY(p_audience))
    UNION
    SELECT resident.user_id FROM public.property_residents AS resident
      WHERE resident.property_id = p_property_id AND resident.active
        AND ('tenants' = ANY(p_audience) OR 'property' = ANY(p_audience))
  ) AS target
  WHERE target.user_id IS NOT NULL
    AND target.user_id IS DISTINCT FROM p_exclude_user
  ON CONFLICT (user_id, notification_type, related_type, related_id) DO NOTHING;
END;
$function$;
REVOKE ALL ON FUNCTION public.notify_property_audience(uuid,text[],text,text,text,text,text,text,uuid,uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_property_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  row_data jsonb := to_jsonb(NEW);
  prop_id uuid;
  row_id uuid;
  event_type text := TG_ARGV[0];
  audience text[] := string_to_array(TG_ARGV[1], ',');
  title_el text; title_en text; message_el text; message_en text;
BEGIN
  prop_id := COALESCE((row_data ->> 'property_id')::uuid, (row_data ->> 'id')::uuid);
  row_id := (row_data ->> 'id')::uuid;
  CASE event_type
    WHEN 'new_property' THEN
      title_el := 'Νέο ακίνητο προς έλεγχο'; title_en := 'New property for review';
      message_el := 'Καταχωρίστηκε το ακίνητο ' || COALESCE(row_data->>'name','') || '.';
      message_en := 'A new property was registered: ' || COALESCE(row_data->>'name','') || '.';
    WHEN 'announcement' THEN
      title_el := 'Νέα ανακοίνωση'; title_en := 'New announcement';
      message_el := left(COALESCE(row_data->>'body',''),240);
      message_en := left(COALESCE(row_data->>'body',''),240);
    WHEN 'vote' THEN
      title_el := 'Νέα ψηφοφορία'; title_en := 'New vote';
      message_el := COALESCE(row_data->>'title','');
      message_en := COALESCE(row_data->>'title','');
    WHEN 'damage' THEN
      title_el := CASE WHEN row_data->>'issue_scope'='building' THEN 'Νέα βλάβη κοινόχρηστου χώρου' ELSE 'Νέα αναφορά βλάβης διαμερίσματος' END;
      title_en := CASE WHEN row_data->>'issue_scope'='building' THEN 'New building damage report' ELSE 'New apartment damage report' END;
      message_el := COALESCE(row_data->>'title','') || ' · ' || COALESCE(row_data->>'apartment_number','');
      message_en := COALESCE(row_data->>'title','') || ' · ' || COALESCE(row_data->>'apartment_number','');
    WHEN 'meeting' THEN
      title_el := 'Νέα συνέλευση'; title_en := 'New meeting';
      message_el := COALESCE(row_data->>'title','') || ' · ' || COALESCE(row_data->>'starts_at','');
      message_en := COALESCE(row_data->>'title','') || ' · ' || COALESCE(row_data->>'starts_at','');
    ELSE RETURN NEW;
  END CASE;
  PERFORM public.notify_property_audience(
    prop_id, audience, event_type, title_el, title_en, message_el, message_en,
    TG_TABLE_NAME, row_id, NULL
  );
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.notify_property_event() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS smartblock_new_property_notification ON public.properties;
CREATE TRIGGER smartblock_new_property_notification AFTER INSERT ON public.properties
FOR EACH ROW EXECUTE FUNCTION public.notify_property_event('new_property','staff');
DROP TRIGGER IF EXISTS smartblock_announcement_notification ON public.property_notes;
CREATE TRIGGER smartblock_announcement_notification AFTER INSERT ON public.property_notes
FOR EACH ROW EXECUTE FUNCTION public.notify_property_event('announcement','property,staff');
DROP TRIGGER IF EXISTS smartblock_vote_notification ON public.property_votes;
CREATE TRIGGER smartblock_vote_notification AFTER INSERT ON public.property_votes
FOR EACH ROW EXECUTE FUNCTION public.notify_property_event('vote','property,staff');
DROP TRIGGER IF EXISTS smartblock_damage_notification ON public.property_service_requests;
CREATE TRIGGER smartblock_damage_notification AFTER INSERT ON public.property_service_requests
FOR EACH ROW WHEN (NEW.request_type = 'damage_report')
EXECUTE FUNCTION public.notify_property_event('damage','owners,staff');
DROP TRIGGER IF EXISTS smartblock_meeting_notification ON public.property_meetings;
CREATE TRIGGER smartblock_meeting_notification AFTER INSERT ON public.property_meetings
FOR EACH ROW EXECUTE FUNCTION public.notify_property_event('meeting','property,staff');

CREATE OR REPLACE FUNCTION public.notify_registration_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.user_notifications(user_id, notification_type, title_el,title_en,message_el,message_en,related_type,related_id)
  SELECT staff.user_id,'registration','Νέα εγγραφή προς έγκριση','New registration for review',
         'Υποβλήθηκε αίτημα επιλογής ρόλου.','A new role registration is waiting for review.',
         'account_role_requests',NEW.user_id
  FROM public.smartblock_staff AS staff WHERE staff.is_active
  ON CONFLICT (user_id, notification_type, related_type, related_id) DO NOTHING;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS account_role_registration_notification ON public.account_role_requests;
CREATE TRIGGER account_role_registration_notification AFTER INSERT OR UPDATE OF submitted_at
ON public.account_role_requests FOR EACH ROW
EXECUTE FUNCTION public.notify_registration_request();

CREATE OR REPLACE FUNCTION public.notify_support_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE conv public.support_conversations%ROWTYPE;
BEGIN
  SELECT * INTO conv FROM public.support_conversations WHERE id=NEW.conversation_id;
  IF conv.user_id IS NULL THEN RETURN NEW; END IF;
  IF public.is_smartblock_staff() THEN
    INSERT INTO public.user_notifications(user_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
    VALUES (conv.user_id,'support_reply','Νέο μήνυμα υποστήριξης','New support message',
      left(NEW.body,240),left(NEW.body,240),'support_messages',NEW.id)
    ON CONFLICT (user_id,notification_type,related_type,related_id) DO NOTHING;
  ELSE
    INSERT INTO public.user_notifications(user_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
    SELECT staff.user_id,'support_message','Νέο μήνυμα βοήθειας','New help chat message',
      left(NEW.body,240),left(NEW.body,240),'support_messages',NEW.id
    FROM public.smartblock_staff AS staff WHERE staff.is_active
    ON CONFLICT (user_id,notification_type,related_type,related_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS support_message_notification ON public.support_messages;
CREATE TRIGGER support_message_notification AFTER INSERT ON public.support_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_support_message();

CREATE OR REPLACE FUNCTION public.refresh_property_due_notifications()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE affected integer := 0; v_count integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501'; END IF;
  -- Unpaid rent reminders go to the tenant assigned to the contract's unit, its owners and staff.
  INSERT INTO public.user_notifications(user_id,property_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
  SELECT targets.user_id,c.property_id,
         CASE WHEN i.due_date < current_date THEN 'rent_overdue' ELSE 'rent_due' END,
         CASE WHEN i.due_date < current_date THEN 'Καθυστερεί το ενοίκιο' ELSE 'Υπενθύμιση ενοικίου' END,
         CASE WHEN i.due_date < current_date THEN 'Rent is overdue' ELSE 'Rent reminder' END,
         c.unit_reference || ' · €' || (i.amount_due-i.amount_paid)::text || ' · ' || i.due_date::text,
         c.unit_reference || ' · €' || (i.amount_due-i.amount_paid)::text || ' · ' || i.due_date::text,
         'property_rent_installments',i.id
  FROM public.property_rent_installments i
  JOIN public.property_rent_contracts c ON c.id=i.contract_id AND c.status='active'
  JOIN LATERAL (
    SELECT r.user_id FROM public.property_residents r
      WHERE r.property_id=c.property_id AND r.active
        AND r.apartment_number=c.unit_reference
        AND i.amount_paid < i.amount_due AND i.due_date <= current_date + 3
    UNION
    SELECT m.user_id FROM public.property_owners o
      JOIN public.organization_members m ON m.organization_id=o.organization_id
        AND m.membership_status='active' AND m.user_id IS NOT NULL
      WHERE o.property_id=c.property_id AND o.ownership_status='active'
        AND i.amount_paid < i.amount_due AND i.due_date <= current_date + 3
    UNION
    SELECT s.user_id FROM public.smartblock_staff s WHERE s.is_active
      AND i.amount_paid < i.amount_due AND i.due_date <= current_date + 3
  ) targets ON true
  WHERE i.amount_paid < i.amount_due AND i.due_date <= current_date + 3
  ON CONFLICT (user_id,notification_type,related_type,related_id) DO NOTHING;
  GET DIAGNOSTICS affected = ROW_COUNT;

  -- Common charges remind the responsible owner representatives and SmartBlock staff.
  INSERT INTO public.user_notifications(user_id,property_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
  SELECT targets.user_id,r.property_id,
         CASE WHEN run.due_date < current_date THEN 'charges_overdue' ELSE 'charges_due' END,
         CASE WHEN run.due_date < current_date THEN 'Καθυστερούν τα κοινόχρηστα' ELSE 'Υπενθύμιση κοινοχρήστων' END,
         CASE WHEN run.due_date < current_date THEN 'Common charges are overdue' ELSE 'Common charges reminder' END,
         run.period_label || ' · €' || (e.amount_due-e.amount_paid)::text || ' · ' || run.due_date::text,
         run.period_label || ' · €' || (e.amount_due-e.amount_paid)::text || ' · ' || run.due_date::text,
         'property_charge_entries',e.id
  FROM public.property_charge_entries e
  JOIN public.property_owners o ON o.id=e.property_owner_id
  JOIN public.property_charge_runs run ON run.id=e.run_id
  JOIN public.properties r ON r.id=run.property_id
  JOIN LATERAL (
    SELECT m.user_id FROM public.organization_members m
      WHERE m.organization_id=o.organization_id AND m.membership_status='active' AND m.user_id IS NOT NULL
    UNION
    SELECT s.user_id FROM public.smartblock_staff s WHERE s.is_active
  ) targets ON true
  WHERE e.amount_paid < e.amount_due AND run.due_date <= current_date + 3
  ON CONFLICT (user_id,notification_type,related_type,related_id) DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  affected := affected + v_count;
  RETURN affected;
END;
$function$;
REVOKE ALL ON FUNCTION public.refresh_property_due_notifications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refresh_property_due_notifications() TO authenticated;

DO $publication$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='user_notifications') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_notifications;
  END IF;
END
$publication$;

COMMIT;

-- Keep owners informed if an announced future billing change is cancelled.
BEGIN;

ALTER TABLE public.property_billing_notifications
  ADD COLUMN IF NOT EXISTS notification_kind text NOT NULL DEFAULT 'scheduled'
    CHECK (notification_kind IN ('scheduled', 'cancelled'));

ALTER TABLE public.property_billing_notifications
  DROP CONSTRAINT IF EXISTS property_billing_notifications_schedule_id_property_id_recipient_id_key;
ALTER TABLE public.property_billing_notifications
  ADD CONSTRAINT property_billing_notifications_once_per_kind
  UNIQUE (schedule_id, property_id, recipient_id, notification_kind);

CREATE OR REPLACE FUNCTION public.admin_cancel_smartblock_billing_change(p_schedule_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  schedule_row public.smartblock_billing_schedules%ROWTYPE;
BEGIN
  IF NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO schedule_row
  FROM public.smartblock_billing_schedules
  WHERE id = p_schedule_id AND status = 'scheduled'
    AND effective_on > CURRENT_DATE
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only a future scheduled change can be cancelled.';
  END IF;

  UPDATE public.smartblock_billing_schedules
  SET status = 'cancelled', cancelled_at = now(), cancelled_by = (SELECT auth.uid())
  WHERE id = p_schedule_id;

  UPDATE public.property_billing_notifications
  SET is_read = true
  WHERE schedule_id = p_schedule_id AND notification_kind = 'scheduled';

  INSERT INTO public.property_billing_notifications (
    schedule_id, property_id, recipient_id, apartment_monthly_eur,
    online_payment_fee_percent, effective_on, notification_kind
  )
  SELECT schedule_id, property_id, recipient_id, apartment_monthly_eur,
         online_payment_fee_percent, effective_on, 'cancelled'
  FROM public.property_billing_notifications
  WHERE schedule_id = p_schedule_id AND notification_kind = 'scheduled'
  ON CONFLICT (schedule_id, property_id, recipient_id, notification_kind) DO NOTHING;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_cancel_smartblock_billing_change(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_smartblock_billing_change(uuid) TO authenticated;

COMMIT;


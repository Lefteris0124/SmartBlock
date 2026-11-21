-- Admin-controlled SmartBlock pricing with effective dates and owner notices.
BEGIN;

CREATE TABLE IF NOT EXISTS public.smartblock_billing_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  apartment_monthly_eur numeric(10,2) NOT NULL DEFAULT 5.00
    CHECK (apartment_monthly_eur >= 0),
  online_payment_fee_percent numeric(5,2) NOT NULL DEFAULT 0.00
    CHECK (online_payment_fee_percent BETWEEN 0 AND 100),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id)
);

INSERT INTO public.smartblock_billing_settings(singleton, apartment_monthly_eur)
VALUES (true, 5.00)
ON CONFLICT (singleton) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.smartblock_billing_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  apartment_monthly_eur numeric(10,2) NOT NULL CHECK (apartment_monthly_eur >= 0),
  online_payment_fee_percent numeric(5,2) NOT NULL
    CHECK (online_payment_fee_percent BETWEEN 0 AND 100),
  effective_on date NOT NULL,
  status text NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'cancelled')),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  cancelled_at timestamptz,
  cancelled_by uuid REFERENCES auth.users(id)
);

DROP INDEX IF EXISTS public.smartblock_billing_one_schedule_per_day;
CREATE INDEX IF NOT EXISTS smartblock_billing_schedules_effective_idx
  ON public.smartblock_billing_schedules(effective_on DESC, created_at DESC)
  WHERE status = 'scheduled';

CREATE TABLE IF NOT EXISTS public.property_billing_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id uuid NOT NULL REFERENCES public.smartblock_billing_schedules(id) ON DELETE CASCADE,
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  apartment_monthly_eur numeric(10,2) NOT NULL,
  online_payment_fee_percent numeric(5,2) NOT NULL,
  effective_on date NOT NULL,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (schedule_id, property_id, recipient_id)
);

ALTER TABLE public.smartblock_billing_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.smartblock_billing_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_billing_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.smartblock_billing_settings,
  public.smartblock_billing_schedules,
  public.property_billing_notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.smartblock_billing_schedules,
  public.property_billing_notifications TO authenticated;

CREATE POLICY smartblock_billing_schedules_admin_read
  ON public.smartblock_billing_schedules FOR SELECT TO authenticated
  USING (public.is_smartblock_admin());
CREATE POLICY property_billing_notifications_recipient_read
  ON public.property_billing_notifications FOR SELECT TO authenticated
  USING (recipient_id = (SELECT auth.uid()));
CREATE POLICY property_billing_notifications_recipient_update
  ON public.property_billing_notifications FOR UPDATE TO authenticated
  USING (recipient_id = (SELECT auth.uid()))
  WITH CHECK (recipient_id = (SELECT auth.uid()));
GRANT UPDATE (is_read) ON public.property_billing_notifications TO authenticated;

CREATE OR REPLACE FUNCTION public.smartblock_current_billing_rates()
RETURNS TABLE (
  apartment_monthly_eur numeric,
  online_payment_fee_percent numeric,
  effective_on date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT schedule.apartment_monthly_eur,
           schedule.online_payment_fee_percent,
           schedule.effective_on
    FROM public.smartblock_billing_schedules AS schedule
    WHERE schedule.status = 'scheduled'
      AND schedule.effective_on <= CURRENT_DATE
    ORDER BY schedule.effective_on DESC, schedule.created_at DESC
    LIMIT 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT settings.apartment_monthly_eur,
                        settings.online_payment_fee_percent,
                        CURRENT_DATE
    FROM public.smartblock_billing_settings AS settings
    WHERE settings.singleton = true;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_smartblock_billing_schedules()
RETURNS SETOF public.smartblock_billing_schedules
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT * FROM public.smartblock_billing_schedules
    ORDER BY effective_on DESC, created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_schedule_smartblock_billing_change(
  p_apartment_monthly_eur numeric,
  p_online_payment_fee_percent numeric,
  p_effective_on date
)
RETURNS TABLE (schedule_id uuid, notified_owner_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
  new_schedule_id uuid;
  notice_count integer := 0;
BEGIN
  IF current_user_id IS NULL OR NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE = '42501';
  END IF;
  IF p_apartment_monthly_eur IS NULL OR p_apartment_monthly_eur < 0
     OR p_online_payment_fee_percent IS NULL
     OR p_online_payment_fee_percent NOT BETWEEN 0 AND 100
     OR p_effective_on IS NULL OR p_effective_on < CURRENT_DATE THEN
    RAISE EXCEPTION 'Enter valid prices and an effective date of today or later.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.smartblock_billing_schedules (
    apartment_monthly_eur, online_payment_fee_percent, effective_on, created_by
  ) VALUES (
    p_apartment_monthly_eur, p_online_payment_fee_percent, p_effective_on, current_user_id
  ) RETURNING id INTO new_schedule_id;

  INSERT INTO public.property_billing_notifications (
    schedule_id, property_id, recipient_id,
    apartment_monthly_eur, online_payment_fee_percent, effective_on
  )
  SELECT new_schedule_id, property_row.id, recipients.user_id,
         p_apartment_monthly_eur, p_online_payment_fee_percent, p_effective_on
  FROM public.properties AS property_row
  CROSS JOIN LATERAL (
    SELECT property_row.manager_user_id AS user_id
    WHERE property_row.manager_user_id IS NOT NULL
    UNION
    SELECT member.user_id
    FROM public.property_owners AS owner_row
    JOIN public.organization_members AS member
      ON member.organization_id = owner_row.organization_id
    WHERE owner_row.property_id = property_row.id
      AND owner_row.ownership_status = 'active'
      AND member.membership_status = 'active'
      AND member.member_role IN ('owner', 'representative')
      AND member.user_id IS NOT NULL
  ) AS recipients
  WHERE property_row.property_type = 'building'
    AND property_row.approval_status = 'approved'
  ON CONFLICT (schedule_id, property_id, recipient_id) DO NOTHING;

  GET DIAGNOSTICS notice_count = ROW_COUNT;
  schedule_id := new_schedule_id;
  notified_owner_count := notice_count;
  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_cancel_smartblock_billing_change(p_schedule_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.smartblock_billing_schedules
  SET status = 'cancelled', cancelled_at = now(), cancelled_by = (SELECT auth.uid())
  WHERE id = p_schedule_id AND status = 'scheduled' AND effective_on > CURRENT_DATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only a future scheduled change can be cancelled.';
  END IF;
  DELETE FROM public.property_billing_notifications WHERE schedule_id = p_schedule_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.smartblock_current_billing_rates() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_smartblock_billing_schedules() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_schedule_smartblock_billing_change(numeric,numeric,date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_cancel_smartblock_billing_change(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.smartblock_current_billing_rates() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_smartblock_billing_schedules() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_schedule_smartblock_billing_change(numeric,numeric,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cancel_smartblock_billing_change(uuid) TO authenticated;

DO $block$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'property_billing_notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.property_billing_notifications;
  END IF;
END;
$block$;

COMMIT;


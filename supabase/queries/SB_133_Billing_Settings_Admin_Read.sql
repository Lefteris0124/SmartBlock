-- Keep the singleton tariff private to staff admins even though RLS is on.
BEGIN;

GRANT SELECT ON public.smartblock_billing_settings TO authenticated;
DROP POLICY IF EXISTS smartblock_billing_settings_admin_read
  ON public.smartblock_billing_settings;
CREATE POLICY smartblock_billing_settings_admin_read
  ON public.smartblock_billing_settings FOR SELECT TO authenticated
  USING (public.is_smartblock_admin());

COMMIT;


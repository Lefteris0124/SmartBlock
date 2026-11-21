-- SmartBlock billing model:
-- physical apartment buildings: €5 per apartment/month (admin-configurable)
-- virtual portfolios: configured percentage on verified in-app payments.
-- Manual/off-platform payment recording is disabled for authenticated clients.

BEGIN;

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS building_model text NOT NULL DEFAULT 'physical';

DO $block$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'properties_building_model_check'
      AND conrelid = 'public.properties'::regclass
  ) THEN
    ALTER TABLE public.properties
      ADD CONSTRAINT properties_building_model_check
      CHECK (building_model IN ('physical','virtual'));
  END IF;
END;
$block$;

-- Existing and future SmartBlock portfolio charges default to the agreed 5%.
UPDATE public.smartblock_billing_settings
SET online_payment_fee_percent = 5.00,
    updated_at = now()
WHERE singleton = true;

-- Only virtual buildings incur this payment fee. Physical buildings and other
-- standalone property types keep the platform-fee snapshot at zero.
CREATE OR REPLACE FUNCTION public.apply_property_billing_model_to_checkout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  property_kind text;
  billing_model text;
BEGIN
  SELECT property_type, building_model
    INTO property_kind, billing_model
  FROM public.properties
  WHERE id = NEW.property_id;

  IF property_kind IS DISTINCT FROM 'building'
     OR billing_model IS DISTINCT FROM 'virtual' THEN
    NEW.platform_fee_percent := 0;
  END IF;

  NEW.platform_fee_amount := round(NEW.amount * NEW.platform_fee_percent / 100, 2);
  NEW.net_to_property_amount := NEW.amount - NEW.platform_fee_amount;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS property_online_payment_billing_model
  ON public.property_online_payment_sessions;
CREATE TRIGGER property_online_payment_billing_model
  BEFORE INSERT ON public.property_online_payment_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_property_billing_model_to_checkout();

-- Remove the old 8-argument overload so the new app RPC has a single target.
DROP FUNCTION IF EXISTS public.create_property_draft_with_units(
  text,text,text,text,text,text,text,integer
);

CREATE OR REPLACE FUNCTION public.create_property_draft_with_units(
    p_name text,
    p_property_type text,
    p_address text,
    p_city text,
    p_country text,
    p_management_model text,
    p_other_description text DEFAULT NULL,
    p_total_apartments integer DEFAULT NULL,
    p_building_model text DEFAULT 'physical'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    new_property_id uuid;
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
    END IF;
    IF p_property_type = 'building' AND (
      COALESCE(p_total_apartments, 0) < 1
      OR public.normalize_property_identity(p_address) = ''
      OR public.normalize_property_identity(p_city) = ''
    ) THEN
        RAISE EXCEPTION 'A building needs a full address, city, and apartment count.'
          USING ERRCODE = '22023';
    END IF;
    IF p_total_apartments IS NOT NULL AND p_total_apartments < 1 THEN
        RAISE EXCEPTION 'Apartment count must be at least 1.';
    END IF;
    IF p_property_type = 'other' AND NULLIF(btrim(p_other_description), '') IS NULL THEN
        RAISE EXCEPTION 'Describe the other property type.';
    END IF;
    IF p_building_model NOT IN ('physical','virtual') THEN
        RAISE EXCEPTION 'Invalid building billing model.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.properties (
        organization_id, property_type, building_model, other_description, name,
        address, city, country, management_model, approval_status, created_by,
        total_apartments
    )
    VALUES (
        NULL, p_property_type,
        CASE WHEN p_property_type = 'building' THEN p_building_model ELSE 'physical' END,
        NULLIF(btrim(p_other_description), ''), btrim(p_name), btrim(p_address),
        NULLIF(btrim(p_city), ''), COALESCE(NULLIF(btrim(p_country), ''), 'Cyprus'),
        p_management_model, 'draft', current_user_id, p_total_apartments
    )
    RETURNING id INTO new_property_id;
    RETURN new_property_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_property_draft_with_units(
  text,text,text,text,text,text,text,integer,text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_property_draft_with_units(
  text,text,text,text,text,text,text,integer,text
) TO authenticated;

-- All payment ledger entries must originate from the verified Stripe webhook.
REVOKE ALL ON FUNCTION public.record_property_charge_payment(
  uuid,numeric,text,text,text,timestamptz
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_property_rent_payment(
  uuid,numeric,text,text,text,timestamptz
) FROM PUBLIC, anon, authenticated;

COMMIT;


BEGIN;

-- A property attached to a portfolio is a virtual building for SmartBlock
-- billing, even when each portfolio item is a separate apartment/house/shop.
CREATE OR REPLACE FUNCTION public.apply_property_billing_model_to_checkout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  property_kind text;
  billing_model text;
  virtual_portfolio_id uuid;
BEGIN
  SELECT property_type, building_model, portfolio_id
    INTO property_kind, billing_model, virtual_portfolio_id
  FROM public.properties
  WHERE id = NEW.property_id;

  IF virtual_portfolio_id IS NULL
     AND (property_kind IS DISTINCT FROM 'building'
       OR billing_model IS DISTINCT FROM 'virtual') THEN
    NEW.platform_fee_percent := 0;
  END IF;

  NEW.platform_fee_amount := round(NEW.amount * NEW.platform_fee_percent / 100, 2);
  NEW.net_to_property_amount := NEW.amount - NEW.platform_fee_amount;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.apply_property_billing_model_to_checkout()
  FROM PUBLIC, anon, authenticated;

COMMIT;


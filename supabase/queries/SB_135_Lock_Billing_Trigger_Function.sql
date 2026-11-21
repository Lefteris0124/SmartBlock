BEGIN;

-- Trigger functions are invoked by PostgreSQL and should not be callable via RPC.
REVOKE ALL ON FUNCTION public.apply_property_billing_model_to_checkout()
  FROM PUBLIC, anon, authenticated;

COMMIT;


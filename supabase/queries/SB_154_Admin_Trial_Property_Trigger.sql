BEGIN;

-- Allow the trusted trial setup RPC to create its disposable property while
-- keeping ordinary property creation behind the signed-in owner checks.
CREATE OR REPLACE FUNCTION public.enforce_approved_property_owner_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
BEGIN
  IF auth.role() = 'service_role' THEN
    IF NEW.created_by IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM auth.users AS account
         WHERE account.id = NEW.created_by
           AND account.raw_app_meta_data ->> 'smartblock_trial' = 'true'
           AND account.raw_app_meta_data ->> 'smartblock_trial_role' = 'owner'
       )
       AND EXISTS (
         SELECT 1 FROM public.account_role_requests AS request
         WHERE request.user_id = NEW.created_by
           AND request.status = 'approved'
           AND 'property_owner' = ANY(request.requested_roles)
       ) THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Only the SmartBlock trial service may create a trial property.'
      USING ERRCODE = '42501';
  END IF;

  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  IF public.is_smartblock_admin() THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.account_role_requests AS request
    WHERE request.user_id = NEW.created_by
      AND request.status = 'approved'
      AND 'property_owner' = ANY(request.requested_roles)
  ) THEN
    RAISE EXCEPTION 'Your SmartBlock owner role must be approved before registering a property.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.enforce_approved_property_owner_role()
  FROM PUBLIC, anon, authenticated;

COMMIT;


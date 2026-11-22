CREATE OR REPLACE FUNCTION public.admin_set_account_roles(
  p_user_id uuid,
  p_requested_roles text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_roles text[];
BEGIN
  IF NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.'
      USING ERRCODE = '42501';
  END IF;
  SELECT array_agg(DISTINCT role_name ORDER BY role_name)
    INTO v_roles
  FROM unnest(COALESCE(p_requested_roles, ARRAY[]::text[])) AS role_name;
  IF COALESCE(cardinality(v_roles), 0) NOT BETWEEN 1 AND 2
     OR v_roles <@ ARRAY['property_owner','tenant']::text[] IS NOT TRUE
     OR cardinality(v_roles) <> cardinality(p_requested_roles) THEN
    RAISE EXCEPTION 'Choose owner, tenant, or both.' USING ERRCODE = '22023';
  END IF;
  UPDATE public.account_role_requests
  SET requested_roles = v_roles,
      status = 'approved',
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      review_note = 'Roles updated by SmartBlock administrator.'
  WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No registration role record exists for this account.';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_account_roles(uuid,text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_account_roles(uuid,text[]) TO authenticated;
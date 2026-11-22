CREATE OR REPLACE FUNCTION public.list_registered_property_owner_accounts(
  p_property_id uuid,
  p_search text DEFAULT NULL
)
RETURNS TABLE(user_id uuid, full_name text, email text, phone text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
  search_value text := pg_catalog.btrim(COALESCE(p_search, ''));
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  IF NOT (
    public.is_smartblock_staff()
    OR EXISTS (SELECT 1 FROM public.properties p WHERE p.id = p_property_id AND p.created_by = current_user_id)
    OR EXISTS (SELECT 1 FROM public.properties p WHERE p.id = p_property_id AND p.manager_user_id = current_user_id)
    OR EXISTS (
      SELECT 1 FROM public.property_owners po
      WHERE po.property_id = p_property_id AND po.ownership_status = 'active'
        AND public.can_manage_organization(po.organization_id)
    )
  ) THEN
    RAISE EXCEPTION 'You cannot manage owners for this property.' USING ERRCODE = '42501';
  END IF;
  IF pg_catalog.char_length(search_value) < 3 THEN
    RAISE EXCEPTION 'Search by at least three characters of the registered owner’s name, email, or phone.'
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
    SELECT pr.id, pr.full_name, u.email::text, pr.phone
    FROM public.profiles pr
    JOIN auth.users u ON u.id = pr.id
    JOIN public.account_role_requests rr ON rr.user_id = pr.id
    WHERE rr.status = 'approved'
      AND rr.requested_roles @> ARRAY['property_owner']::text[]
      AND pg_catalog.concat_ws(' ', pr.full_name, u.email, pr.phone)
          ILIKE '%' || search_value || '%'
    ORDER BY pg_catalog.lower(COALESCE(pr.full_name, u.email)), pg_catalog.lower(u.email)
    LIMIT 30;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_registered_property_owner_accounts(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_registered_property_owner_accounts(uuid, text) TO authenticated;


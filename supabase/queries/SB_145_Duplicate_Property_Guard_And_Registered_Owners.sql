BEGIN;

-- A real apartment building and an apartment entry must not be created twice
-- for the same normalized street address. Unit identifiers belong in the
-- address itself, so separate flats remain distinct.
DROP INDEX IF EXISTS public.properties_unique_building_identity;
CREATE UNIQUE INDEX properties_unique_building_identity
  ON public.properties (
    public.normalize_property_identity(address),
    public.normalize_property_identity(city),
    public.normalize_property_identity(country)
  )
  WHERE property_type IN ('building', 'apartment')
    AND approval_status IN ('draft', 'changes_required', 'pending_review', 'under_review', 'approved')
    AND NULLIF(pg_catalog.btrim(address), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(city), '') IS NOT NULL;

-- A property owner is linked to a registered account through the existing
-- organization membership model. Only approved owner accounts may be linked.
CREATE OR REPLACE FUNCTION public.property_owner_accounts_ready(p_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
           SELECT 1 FROM public.property_owners po
           WHERE po.property_id = p_property_id AND po.ownership_status = 'active'
         )
     AND NOT EXISTS (
           SELECT 1
           FROM public.property_owners po
           WHERE po.property_id = p_property_id
             AND po.ownership_status = 'active'
             AND NOT EXISTS (
               SELECT 1
               FROM public.organization_members om
               JOIN public.account_role_requests rr ON rr.user_id = om.user_id
               WHERE om.organization_id = po.organization_id
                 AND om.member_role = 'owner'
                 AND om.membership_status = 'active'
                 AND om.user_id IS NOT NULL
                 AND rr.status = 'approved'
                 AND rr.requested_roles @> ARRAY['property_owner']::text[]
             )
         );
$function$;

REVOKE ALL ON FUNCTION public.property_owner_accounts_ready(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.property_owner_accounts_ready(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_manage_property(target_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT public.is_smartblock_staff()
    OR (
      public.property_owner_accounts_ready(target_property_id)
      AND (
        EXISTS (
          SELECT 1 FROM public.properties p
          WHERE p.id = target_property_id AND p.manager_user_id = (SELECT auth.uid())
        )
        OR EXISTS (
          SELECT 1 FROM public.properties p
          WHERE p.id = target_property_id AND p.created_by = (SELECT auth.uid())
            AND p.approval_status IN ('draft', 'changes_required')
        )
        OR EXISTS (
          SELECT 1 FROM public.property_owners po
          WHERE po.property_id = target_property_id
            AND po.ownership_status = 'active'
            AND public.can_manage_organization(po.organization_id)
        )
      )
    );
$function$;

REVOKE ALL ON FUNCTION public.can_manage_property(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_property(uuid) TO authenticated;

-- Enforce completion at the database boundary for direct status changes too.
CREATE OR REPLACE FUNCTION public.require_registered_owners_before_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.approval_status = 'pending_review'
     AND OLD.approval_status IS DISTINCT FROM NEW.approval_status
     AND NOT public.property_owner_accounts_ready(NEW.id) THEN
    RAISE EXCEPTION 'Link every active owner to an approved SmartBlock owner account before property review.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.require_registered_owners_before_review() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS require_registered_owners_before_review ON public.properties;
CREATE TRIGGER require_registered_owners_before_review
  BEFORE UPDATE OF approval_status ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.require_registered_owners_before_review();

DROP FUNCTION IF EXISTS public.find_matching_buildings(text, text, text);
CREATE FUNCTION public.find_matching_buildings(
  p_address text,
  p_city text,
  p_country text DEFAULT 'Cyprus'
)
RETURNS TABLE (
  property_id uuid,
  name text,
  address text,
  city text,
  country text,
  total_apartments integer,
  approval_status text,
  has_manager boolean,
  property_type text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  IF pg_catalog.char_length(pg_catalog.btrim(COALESCE(p_address, ''))) < 5
     OR pg_catalog.char_length(pg_catalog.btrim(COALESCE(p_city, ''))) < 2 THEN
    RAISE EXCEPTION 'Enter the full address and city to check for an existing property.'
      USING ERRCODE = '22023';
  END IF;
  RETURN QUERY
    SELECT p.id, p.name, p.address, p.city, p.country, p.total_apartments,
           p.approval_status, p.manager_user_id IS NOT NULL, p.property_type
    FROM public.properties p
    WHERE p.property_type IN ('building', 'apartment')
      AND p.approval_status IN ('draft', 'changes_required', 'pending_review', 'under_review', 'approved')
      AND public.normalize_property_identity(p.address) = public.normalize_property_identity(p_address)
      AND public.normalize_property_identity(p.city) = public.normalize_property_identity(p_city)
      AND public.normalize_property_identity(p.country) = public.normalize_property_identity(COALESCE(p_country, 'Cyprus'))
    ORDER BY p.created_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.find_matching_buildings(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_matching_buildings(text, text, text) TO authenticated;

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

  RETURN QUERY
    SELECT pr.id, pr.full_name, u.email::text, pr.phone
    FROM public.profiles pr
    JOIN auth.users u ON u.id = pr.id
    JOIN public.account_role_requests rr ON rr.user_id = pr.id
    WHERE rr.status = 'approved'
      AND rr.requested_roles @> ARRAY['property_owner']::text[]
      AND (p_search IS NULL OR pg_catalog.btrim(p_search) = '' OR
           pg_catalog.concat_ws(' ', pr.full_name, u.email, pr.phone) ILIKE '%' || pg_catalog.btrim(p_search) || '%')
    ORDER BY pg_catalog.lower(COALESCE(pr.full_name, u.email)), pg_catalog.lower(u.email)
    LIMIT 200;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_registered_property_owner_accounts(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_registered_property_owner_accounts(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_property_owner_account_links(p_property_id uuid)
RETURNS TABLE(owner_id uuid, organization_id uuid, user_id uuid, full_name text, email text, phone text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
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
    RAISE EXCEPTION 'You cannot view owner account links for this property.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT po.id, po.organization_id, om.user_id, pr.full_name, u.email::text, pr.phone
    FROM public.property_owners po
    JOIN public.organization_members om ON om.organization_id = po.organization_id
      AND om.member_role = 'owner' AND om.membership_status = 'active' AND om.user_id IS NOT NULL
    LEFT JOIN public.profiles pr ON pr.id = om.user_id
    LEFT JOIN auth.users u ON u.id = om.user_id
    WHERE po.property_id = p_property_id AND po.ownership_status = 'active'
    ORDER BY po.created_at, pr.full_name, u.email;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_property_owner_account_links(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_property_owner_account_links(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.link_property_owner_account(p_owner_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
  owner_row public.property_owners%ROWTYPE;
  account_email text;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO owner_row FROM public.property_owners WHERE id = p_owner_id FOR UPDATE;
  IF NOT FOUND OR owner_row.ownership_status <> 'active' THEN
    RAISE EXCEPTION 'Active owner record not found.';
  END IF;
  IF NOT (
    public.is_smartblock_staff()
    OR EXISTS (
      SELECT 1 FROM public.properties p
      WHERE p.id = owner_row.property_id
        AND (p.created_by = current_user_id OR p.manager_user_id = current_user_id)
    )
    OR public.can_manage_organization(owner_row.organization_id)
  ) THEN
    RAISE EXCEPTION 'You cannot link an account to this owner record.' USING ERRCODE = '42501';
  END IF;

  SELECT u.email INTO account_email
  FROM auth.users u
  JOIN public.account_role_requests rr ON rr.user_id = u.id
  WHERE u.id = p_user_id AND rr.status = 'approved'
    AND rr.requested_roles @> ARRAY['property_owner']::text[];
  IF account_email IS NULL THEN
    RAISE EXCEPTION 'The selected account must be registered and approved as a property owner.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.property_owners other_owner
    JOIN public.organization_members om ON om.organization_id = other_owner.organization_id
      AND om.user_id = p_user_id AND om.member_role = 'owner' AND om.membership_status = 'active'
    WHERE other_owner.property_id = owner_row.property_id
      AND other_owner.ownership_status = 'active'
      AND other_owner.id <> owner_row.id
  ) THEN
    RAISE EXCEPTION 'This registered account is already linked to another owner in this property.';
  END IF;

  UPDATE public.organization_members
  SET user_id = p_user_id,
      member_role = 'owner',
      membership_status = 'active',
      invited_email = lower(account_email),
      invited_by = COALESCE(invited_by, current_user_id),
      approved_by = current_user_id,
      approved_at = now(),
      updated_at = now()
  WHERE organization_id = owner_row.organization_id
    AND user_id IS NULL
    AND membership_status <> 'revoked'
    AND lower(invited_email) = lower(account_email);

  INSERT INTO public.organization_members (
    organization_id, user_id, invited_email, member_role, membership_status,
    invited_by, approved_by, approved_at
  )
  SELECT owner_row.organization_id, p_user_id, lower(account_email), 'owner', 'active',
         current_user_id, current_user_id, now()
  WHERE NOT EXISTS (
    SELECT 1 FROM public.organization_members existing_member
    WHERE existing_member.organization_id = owner_row.organization_id
      AND existing_member.user_id = p_user_id
      AND existing_member.membership_status <> 'revoked'
  )
  ON CONFLICT (organization_id, user_id)
    WHERE user_id IS NOT NULL AND membership_status <> 'revoked'
  DO UPDATE SET member_role = 'owner', membership_status = 'active',
    approved_by = EXCLUDED.approved_by, approved_at = now(), updated_at = now();
END;
$function$;

REVOKE ALL ON FUNCTION public.link_property_owner_account(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_property_owner_account(uuid, uuid) TO authenticated;

COMMIT;


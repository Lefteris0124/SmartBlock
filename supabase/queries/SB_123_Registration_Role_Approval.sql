-- Capture the roles selected during sign-up and keep them pending until a
-- SmartBlock administrator reviews them. Registration approval is separate
-- from property-specific owner and resident access.
BEGIN;

CREATE TABLE IF NOT EXISTS public.account_role_requests (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_roles text[] NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id),
  review_note text,
  CONSTRAINT account_role_requests_roles_check CHECK (
    cardinality(requested_roles) BETWEEN 1 AND 2
    AND requested_roles <@ ARRAY['property_owner', 'tenant']::text[]
  )
);

ALTER TABLE public.account_role_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.account_role_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.account_role_requests TO authenticated;
DROP POLICY IF EXISTS account_role_requests_admin_read
  ON public.account_role_requests;
CREATE POLICY account_role_requests_admin_read
  ON public.account_role_requests FOR SELECT TO authenticated
  USING (public.is_smartblock_admin());

CREATE OR REPLACE FUNCTION public.capture_account_role_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_roles text[];
BEGIN
  IF jsonb_typeof(NEW.raw_user_meta_data -> 'requested_roles') <> 'array' THEN
    RETURN NEW;
  END IF;

  SELECT array_agg(DISTINCT role_name)
    INTO v_roles
  FROM jsonb_array_elements_text(NEW.raw_user_meta_data -> 'requested_roles')
       AS roles(role_name)
  WHERE role_name IN ('property_owner', 'tenant');

  IF COALESCE(cardinality(v_roles), 0) BETWEEN 1 AND 2 THEN
    INSERT INTO public.account_role_requests(user_id, requested_roles)
    VALUES (NEW.id, v_roles)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_auth_user_created_role_request ON auth.users;
CREATE TRIGGER on_auth_user_created_role_request
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.capture_account_role_request();

CREATE OR REPLACE FUNCTION public.submit_account_role_request(
  p_requested_roles text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_roles text[];
  v_status text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  SELECT array_agg(DISTINCT role_name)
    INTO v_roles
  FROM unnest(COALESCE(p_requested_roles, ARRAY[]::text[])) AS roles(role_name)
  WHERE role_name IN ('property_owner', 'tenant');
  IF COALESCE(cardinality(v_roles), 0) NOT BETWEEN 1 AND 2
     OR cardinality(v_roles) <> cardinality(p_requested_roles) THEN
    RAISE EXCEPTION 'Choose owner, tenant, or both.' USING ERRCODE = '22023';
  END IF;

  SELECT request.status INTO v_status
  FROM public.account_role_requests AS request
  WHERE request.user_id = v_user_id
  FOR UPDATE;
  IF v_status = 'approved' THEN
    RAISE EXCEPTION 'Your role request has already been approved.';
  ELSIF v_status = 'pending' THEN
    RAISE EXCEPTION 'Your role request is already waiting for review.';
  END IF;

  INSERT INTO public.account_role_requests(user_id, requested_roles)
  VALUES (v_user_id, v_roles)
  ON CONFLICT (user_id) DO UPDATE
    SET requested_roles = EXCLUDED.requested_roles,
        status = 'pending',
        submitted_at = now(),
        reviewed_at = NULL,
        reviewed_by = NULL,
        review_note = NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_my_account_role_request()
RETURNS TABLE (
  requested_roles text[],
  status text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  review_note text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT request.requested_roles, request.status,
         request.submitted_at, request.reviewed_at, request.review_note
  FROM public.account_role_requests AS request
  WHERE request.user_id = (SELECT auth.uid());
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_account_role_requests()
RETURNS TABLE (
  user_id uuid,
  email text,
  requested_roles text[],
  status text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  review_note text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.'
      USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT request.user_id, account.email::text, request.requested_roles,
           request.status, request.submitted_at, request.reviewed_at,
           request.review_note
    FROM public.account_role_requests AS request
    JOIN auth.users AS account ON account.id = request.user_id
    ORDER BY (request.status = 'pending') DESC, request.submitted_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_review_account_role_request(
  p_user_id uuid,
  p_status text,
  p_review_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.'
      USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Choose approved or rejected.' USING ERRCODE = '22023';
  END IF;
  UPDATE public.account_role_requests
  SET status = p_status,
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      review_note = NULLIF(btrim(p_review_note), '')
  WHERE user_id = p_user_id AND status = 'pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No pending role request was found.';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.enforce_approved_property_owner_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.created_by IS NULL OR public.is_smartblock_admin() THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.account_role_requests AS request
    WHERE request.user_id = NEW.created_by
  ) AND NOT EXISTS (
    SELECT 1 FROM public.account_role_requests AS request
    WHERE request.user_id = NEW.created_by
      AND request.status = 'approved'
      AND 'property_owner' = ANY(request.requested_roles)
  ) THEN
    RAISE EXCEPTION 'Your owner role must be approved before registering a property.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS properties_require_approved_owner_role
  ON public.properties;
CREATE TRIGGER properties_require_approved_owner_role
  BEFORE INSERT ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.enforce_approved_property_owner_role();

CREATE OR REPLACE FUNCTION public.enforce_approved_tenant_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT NEW.active OR public.is_smartblock_admin() THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.account_role_requests AS request
    WHERE request.user_id = NEW.user_id
  ) AND NOT EXISTS (
    SELECT 1 FROM public.account_role_requests AS request
    WHERE request.user_id = NEW.user_id
      AND request.status = 'approved'
      AND 'tenant' = ANY(request.requested_roles)
  ) THEN
    RAISE EXCEPTION 'The tenant role must be approved before apartment access is assigned.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS property_residents_require_approved_tenant_role
  ON public.property_residents;
CREATE TRIGGER property_residents_require_approved_tenant_role
  BEFORE INSERT OR UPDATE ON public.property_residents
  FOR EACH ROW EXECUTE FUNCTION public.enforce_approved_tenant_role();

REVOKE ALL ON FUNCTION public.capture_account_role_request() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_account_role_request(text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_account_role_request() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_account_role_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_review_account_role_request(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_account_role_request(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_account_role_request() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_account_role_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_account_role_request(uuid, text, text) TO authenticated;

COMMIT;

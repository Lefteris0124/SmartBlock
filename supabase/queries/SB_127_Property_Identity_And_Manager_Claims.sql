-- Give each apartment building one canonical record and one verified manager.
BEGIN;

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS manager_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS manager_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS manager_verified_by uuid REFERENCES auth.users(id);

CREATE OR REPLACE FUNCTION public.normalize_property_identity(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $function$
  SELECT pg_catalog.regexp_replace(
    pg_catalog.lower(pg_catalog.btrim(COALESCE(p_value, ''))),
    '[^[:alnum:]]+', '', 'g'
  );
$function$;

-- Ignore spacing and punctuation so simple address formatting differences
-- cannot create a second active building record.
CREATE UNIQUE INDEX IF NOT EXISTS properties_unique_building_identity
  ON public.properties (
    public.normalize_property_identity(address),
    public.normalize_property_identity(city),
    public.normalize_property_identity(country)
  )
  WHERE property_type = 'building'
    AND approval_status IN ('draft', 'changes_required', 'pending_review', 'under_review', 'approved')
    AND NULLIF(pg_catalog.btrim(address), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(city), '') IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.property_manager_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  authority_note text NOT NULL CHECK (char_length(btrim(authority_note)) BETWEEN 10 AND 2000),
  authority_document_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id),
  review_note text,
  UNIQUE (property_id, requester_id)
);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'smartblock-manager-proofs', 'smartblock-manager-proofs', false,
  10485760, ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = false, file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS manager_proofs_insert_own ON storage.objects;
CREATE POLICY manager_proofs_insert_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'smartblock-manager-proofs'
    AND split_part(name, '/', 1) = (SELECT auth.uid())::text
    AND split_part(name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND EXISTS (
      SELECT 1 FROM public.properties AS p
      WHERE p.id = split_part(name, '/', 2)::uuid
        AND p.property_type = 'building'
        AND p.approval_status = 'approved'
        AND p.manager_user_id IS NULL
    )
  );
DROP POLICY IF EXISTS manager_proofs_select_own_or_admin ON storage.objects;
CREATE POLICY manager_proofs_select_own_or_admin ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'smartblock-manager-proofs'
    AND (
      split_part(name, '/', 1) = (SELECT auth.uid())::text
      OR public.is_smartblock_admin()
    )
  );
DROP POLICY IF EXISTS manager_proofs_delete_own ON storage.objects;
CREATE POLICY manager_proofs_delete_own ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'smartblock-manager-proofs'
    AND split_part(name, '/', 1) = (SELECT auth.uid())::text
  );

CREATE INDEX IF NOT EXISTS property_manager_requests_pending_idx
  ON public.property_manager_requests (submitted_at)
  WHERE status = 'pending';

ALTER TABLE public.property_manager_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.property_manager_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.property_manager_requests TO authenticated;
DROP POLICY IF EXISTS property_manager_requests_read_own_or_staff
  ON public.property_manager_requests;
CREATE POLICY property_manager_requests_read_own_or_staff
  ON public.property_manager_requests FOR SELECT TO authenticated
  USING (requester_id = (SELECT auth.uid()) OR public.is_smartblock_admin());

DO $block$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'property_manager_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.property_manager_requests;
  END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION public.find_matching_buildings(
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
  has_manager boolean
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
    RAISE EXCEPTION 'Enter the full address and city to check for an existing building.'
      USING ERRCODE = '22023';
  END IF;
  RETURN QUERY
    SELECT property_row.id, property_row.name, property_row.address,
           property_row.city, property_row.country,
           property_row.total_apartments, property_row.approval_status,
           property_row.manager_user_id IS NOT NULL
    FROM public.properties AS property_row
    WHERE property_row.property_type = 'building'
      AND property_row.approval_status IN
        ('draft', 'changes_required', 'pending_review', 'under_review', 'approved')
      AND public.normalize_property_identity(property_row.address)
          = public.normalize_property_identity(p_address)
      AND public.normalize_property_identity(property_row.city)
          = public.normalize_property_identity(p_city)
      AND public.normalize_property_identity(property_row.country)
          = public.normalize_property_identity(COALESCE(p_country, 'Cyprus'))
    ORDER BY property_row.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.request_property_manager(
  p_property_id uuid,
  p_authority_note text,
  p_authority_document_path text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
  request_id uuid;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  IF pg_catalog.char_length(pg_catalog.btrim(COALESCE(p_authority_note, ''))) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'Describe your authority to manage this building (10–2000 characters).'
      USING ERRCODE = '22023';
  END IF;
  IF p_authority_document_path IS NULL
     OR p_authority_document_path NOT LIKE current_user_id::text || '/' || p_property_id::text || '/%'
     OR NOT EXISTS (
       SELECT 1 FROM storage.objects AS object_row
       WHERE object_row.bucket_id = 'smartblock-manager-proofs'
         AND object_row.name = p_authority_document_path
     ) THEN
    RAISE EXCEPTION 'Upload proof that you are authorized to manage this building.'
      USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.properties AS property_row
    WHERE property_row.id = p_property_id
      AND property_row.property_type = 'building'
      AND property_row.approval_status = 'approved'
      AND property_row.manager_user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'This building is not available for a manager claim.';
  END IF;
  INSERT INTO public.property_manager_requests (
    property_id, requester_id, authority_note, authority_document_path
  ) VALUES (
    p_property_id, current_user_id, pg_catalog.btrim(p_authority_note),
    p_authority_document_path
  )
  ON CONFLICT (property_id, requester_id) DO UPDATE
    SET authority_note = EXCLUDED.authority_note,
        authority_document_path = EXCLUDED.authority_document_path,
        status = 'pending', submitted_at = now(), reviewed_at = NULL,
        reviewed_by = NULL, review_note = NULL
  RETURNING id INTO request_id;
  RETURN request_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_property_manager_requests()
RETURNS TABLE (
  request_id uuid,
  property_id uuid,
  requester_id uuid,
  requester_email text,
  authority_note text,
  status text,
  submitted_at timestamptz,
  property_name text,
  property_address text,
  property_city text,
  authority_document_path text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT request.id, request.property_id, request.requester_id,
           account.email::text, request.authority_note, request.status,
           request.submitted_at, property_row.name, property_row.address,
           property_row.city, request.authority_document_path
    FROM public.property_manager_requests AS request
    JOIN auth.users AS account ON account.id = request.requester_id
    JOIN public.properties AS property_row ON property_row.id = request.property_id
    ORDER BY (request.status = 'pending') DESC, request.submitted_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_review_property_manager_request(
  p_request_id uuid,
  p_status text,
  p_review_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  request_row public.property_manager_requests%ROWTYPE;
  property_row public.properties%ROWTYPE;
BEGIN
  IF NOT public.is_smartblock_admin() THEN
    RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Choose approved or rejected.' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO request_row
  FROM public.property_manager_requests
  WHERE id = p_request_id AND status = 'pending'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No pending manager request was found.'; END IF;
  SELECT * INTO property_row
  FROM public.properties WHERE id = request_row.property_id FOR UPDATE;
  IF p_status = 'approved' THEN
    IF property_row.approval_status <> 'approved' OR property_row.manager_user_id IS NOT NULL THEN
      RAISE EXCEPTION 'The building already has a manager or is not approved.';
    END IF;
    UPDATE public.properties
    SET manager_user_id = request_row.requester_id,
        manager_verified_at = now(), manager_verified_by = (SELECT auth.uid()),
        updated_at = now()
    WHERE id = property_row.id;
    UPDATE public.property_manager_requests
    SET status = 'rejected', reviewed_at = now(),
        reviewed_by = (SELECT auth.uid()),
        review_note = 'Another manager was verified for this building.'
    WHERE property_id = property_row.id
      AND id <> request_row.id
      AND status = 'pending';
  END IF;
  UPDATE public.property_manager_requests
  SET status = p_status, reviewed_at = now(), reviewed_by = (SELECT auth.uid()),
      review_note = NULLIF(pg_catalog.btrim(p_review_note), '')
  WHERE id = request_row.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_access_property(target_property_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT public.is_smartblock_staff()
    OR EXISTS (SELECT 1 FROM public.properties AS p
      WHERE p.id = target_property_id AND p.created_by = (SELECT auth.uid()))
    OR EXISTS (SELECT 1 FROM public.properties AS p
      WHERE p.id = target_property_id AND p.manager_user_id = (SELECT auth.uid()))
    OR EXISTS (SELECT 1 FROM public.properties AS p
      WHERE p.id = target_property_id AND p.organization_id IS NOT NULL
        AND public.can_access_organization(p.organization_id))
    OR EXISTS (SELECT 1 FROM public.property_owners AS o
      WHERE o.property_id = target_property_id AND o.ownership_status = 'active'
        AND public.can_access_organization(o.organization_id));
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_property(target_property_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT public.is_smartblock_staff()
    OR EXISTS (SELECT 1 FROM public.properties AS p
      WHERE p.id = target_property_id AND p.manager_user_id = (SELECT auth.uid()))
    OR EXISTS (SELECT 1 FROM public.properties AS p
      WHERE p.id = target_property_id AND p.created_by = (SELECT auth.uid())
        AND p.approval_status IN ('draft', 'changes_required'))
    OR EXISTS (SELECT 1 FROM public.property_owners AS o
      WHERE o.property_id = target_property_id AND o.ownership_status = 'active'
        AND public.can_manage_organization(o.organization_id));
$function$;

REVOKE ALL ON FUNCTION public.find_matching_buildings(text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.request_property_manager(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_property_manager_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_review_property_manager_request(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_matching_buildings(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_property_manager(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_property_manager_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_property_manager_request(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_property(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_property(uuid) TO authenticated;

COMMIT;

-- Close the last authorization gaps in property and manager registration.
BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_approved_property_owner_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
BEGIN
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
    IF NOT EXISTS (
      SELECT 1 FROM storage.objects AS object_row
      WHERE object_row.bucket_id = 'smartblock-manager-proofs'
        AND object_row.name = request_row.authority_document_path
    ) THEN
      RAISE EXCEPTION 'The manager appointment proof is missing; ask the user to upload it again.';
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

REVOKE ALL ON FUNCTION public.admin_review_property_manager_request(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_property_manager_request(uuid, text, text)
  TO authenticated;

COMMIT;

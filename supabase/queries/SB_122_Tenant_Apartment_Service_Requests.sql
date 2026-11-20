-- Let verified residents report a problem for their assigned apartment only.
BEGIN;

CREATE TABLE IF NOT EXISTS public.property_residents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  resident_email text NOT NULL,
  apartment_number text NOT NULL CHECK (length(btrim(apartment_number)) BETWEEN 1 AND 30),
  active boolean NOT NULL DEFAULT true,
  assigned_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (property_id, user_id, apartment_number)
);

CREATE INDEX IF NOT EXISTS property_residents_user_property_idx
  ON public.property_residents(user_id, property_id)
  WHERE active;
CREATE INDEX IF NOT EXISTS property_residents_property_apartment_idx
  ON public.property_residents(property_id, apartment_number)
  WHERE active;

ALTER TABLE public.property_residents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.property_residents FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.property_residents TO authenticated;
DROP POLICY IF EXISTS property_residents_select_managers ON public.property_residents;
CREATE POLICY property_residents_select_managers
  ON public.property_residents FOR SELECT TO authenticated
  USING (public.can_manage_property(property_id));

ALTER TABLE public.property_service_requests
  ADD COLUMN IF NOT EXISTS apartment_number text NOT NULL DEFAULT 'common_area';
ALTER TABLE public.property_service_requests
  DROP CONSTRAINT IF EXISTS property_service_requests_apartment_number_check;
ALTER TABLE public.property_service_requests
  ADD CONSTRAINT property_service_requests_apartment_number_check
  CHECK (length(btrim(apartment_number)) BETWEEN 1 AND 30);
CREATE INDEX IF NOT EXISTS property_service_requests_property_apartment_idx
  ON public.property_service_requests(property_id, apartment_number, created_at DESC);

CREATE OR REPLACE FUNCTION public.list_my_resident_properties()
RETURNS TABLE (
  property_id uuid,
  property_name text,
  property_type text,
  property_address text,
  property_city text,
  total_apartments integer,
  apartment_number text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT p.id, p.name, p.property_type, p.address, p.city,
         p.total_apartments, r.apartment_number
  FROM public.property_residents AS r
  JOIN public.properties AS p ON p.id = r.property_id
  WHERE r.user_id = (SELECT auth.uid())
    AND r.active
    AND p.approval_status = 'approved'
  ORDER BY p.name, r.apartment_number;
$function$;

CREATE OR REPLACE FUNCTION public.list_property_residents(p_property_id uuid)
RETURNS TABLE (
  resident_id uuid,
  resident_email text,
  apartment_number text,
  active boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_property(p_property_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT r.user_id, r.resident_email, r.apartment_number, r.active, r.created_at
  FROM public.property_residents AS r
  WHERE r.property_id = p_property_id
    AND r.active
  ORDER BY r.apartment_number, r.resident_email;
END;
$function$;

CREATE OR REPLACE FUNCTION public.assign_property_resident(
  p_property_id uuid,
  p_resident_email text,
  p_apartment_number text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid;
  v_email text := lower(btrim(p_resident_email));
  v_apartment text := btrim(p_apartment_number);
  v_total_apartments integer;
  v_resident_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_property(p_property_id) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
  END IF;
  IF v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RAISE EXCEPTION 'Enter a valid tenant email address.' USING ERRCODE = '22023';
  END IF;
  IF length(v_apartment) < 1 OR length(v_apartment) > 30 THEN
    RAISE EXCEPTION 'Enter a valid apartment number.' USING ERRCODE = '22023';
  END IF;

  SELECT p.total_apartments INTO v_total_apartments
  FROM public.properties AS p WHERE p.id = p_property_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Property not found.' USING ERRCODE = 'P0002';
  END IF;
  IF v_total_apartments IS NOT NULL AND v_apartment !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'Use an apartment number between 1 and %.', v_total_apartments USING ERRCODE = '22023';
  END IF;
  IF v_total_apartments IS NOT NULL AND v_apartment::integer NOT BETWEEN 1 AND v_total_apartments THEN
    RAISE EXCEPTION 'Apartment number must be between 1 and %.', v_total_apartments USING ERRCODE = '22023';
  END IF;

  SELECT u.id INTO v_user_id
  FROM auth.users AS u
  WHERE lower(u.email) = v_email
  LIMIT 1;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No SmartBlock account uses this email. Ask the tenant to register first.' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.property_residents(property_id, user_id, resident_email, apartment_number, active, assigned_by)
  VALUES (p_property_id, v_user_id, v_email, v_apartment, true, auth.uid())
  ON CONFLICT (property_id, user_id, apartment_number)
  DO UPDATE SET resident_email = EXCLUDED.resident_email,
                active = true,
                assigned_by = EXCLUDED.assigned_by;

  SELECT r.id INTO v_resident_id
  FROM public.property_residents AS r
  WHERE r.property_id = p_property_id
    AND r.user_id = v_user_id
    AND r.apartment_number = v_apartment;
  RETURN v_resident_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.deactivate_property_resident(p_resident_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_property_id uuid;
BEGIN
  SELECT r.property_id INTO v_property_id
  FROM public.property_residents AS r WHERE r.id = p_resident_id;
  IF v_property_id IS NULL OR NOT public.can_manage_property(v_property_id) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.property_residents SET active = false WHERE id = p_resident_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_resident_services(p_property_id uuid)
RETURNS TABLE (service_id uuid, title text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.property_residents AS r
    WHERE r.property_id = p_property_id
      AND r.user_id = (SELECT auth.uid())
      AND r.active
  ) THEN
    RAISE EXCEPTION 'Active apartment access is required.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT s.id, s.title
  FROM public.property_management_services AS s
  WHERE s.property_id = p_property_id AND s.active
  ORDER BY s.title;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_resident_service_request(
  p_property_id uuid,
  p_apartment_number text,
  p_service_id uuid,
  p_request_type text,
  p_priority text,
  p_title text,
  p_description text,
  p_location text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_requester uuid := auth.uid();
  v_request_id uuid;
  v_title text := btrim(p_title);
  v_description text := btrim(p_description);
  v_location text := btrim(COALESCE(p_location, ''));
BEGIN
  IF v_requester IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.property_residents AS r
    WHERE r.property_id = p_property_id
      AND r.user_id = v_requester
      AND r.active
      AND (r.apartment_number = p_apartment_number OR p_apartment_number = 'common_area')
  ) THEN
    RAISE EXCEPTION 'You can only report a problem for your assigned apartment or a common area.' USING ERRCODE = '42501';
  END IF;
  IF p_request_type NOT IN ('service','damage_report','maintenance','cleaning','safety','other') THEN
    RAISE EXCEPTION 'Invalid request type.' USING ERRCODE = '22023';
  END IF;
  IF p_priority NOT IN ('normal','urgent','emergency') THEN
    RAISE EXCEPTION 'Invalid request priority.' USING ERRCODE = '22023';
  END IF;
  IF length(v_title) NOT BETWEEN 2 AND 200 OR length(v_description) NOT BETWEEN 2 AND 2000 THEN
    RAISE EXCEPTION 'Enter a short title and a description (2 to 2000 characters).' USING ERRCODE = '22023';
  END IF;
  IF p_service_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.property_management_services AS s
    WHERE s.id = p_service_id AND s.property_id = p_property_id AND s.active
  ) THEN
    RAISE EXCEPTION 'Selected service is unavailable for this property.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.property_service_requests(
    property_id, service_id, requester_id, title, description,
    request_type, priority, location, apartment_number
  ) VALUES (
    p_property_id, p_service_id, v_requester, v_title, v_description,
    p_request_type, p_priority, v_location, p_apartment_number
  ) RETURNING id INTO v_request_id;
  RETURN v_request_id;
END;
$function$;

DROP POLICY IF EXISTS property_service_requests_select ON public.property_service_requests;
CREATE POLICY property_service_requests_select
  ON public.property_service_requests FOR SELECT TO authenticated
  USING (
    public.can_access_property(property_id)
    OR requester_id = (SELECT auth.uid())
  );

REVOKE ALL ON FUNCTION public.list_my_resident_properties() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_property_residents(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_property_resident(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.deactivate_property_resident(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_resident_services(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_resident_service_request(uuid, text, uuid, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_resident_properties() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_property_residents(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_property_resident(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deactivate_property_resident(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_resident_services(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_resident_service_request(uuid, text, uuid, text, text, text, text, text) TO authenticated;

COMMIT;

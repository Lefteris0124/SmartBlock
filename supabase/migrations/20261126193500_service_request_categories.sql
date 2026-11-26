-- SmartBlock service categories
ALTER TABLE public.property_service_requests
  ADD COLUMN IF NOT EXISTS service_category text NOT NULL DEFAULT 'other';
ALTER TABLE public.property_management_services
  ADD COLUMN IF NOT EXISTS service_category text NOT NULL DEFAULT 'other';

ALTER TABLE public.property_service_requests
  DROP CONSTRAINT IF EXISTS property_service_requests_service_category_check;
ALTER TABLE public.property_service_requests
  ADD CONSTRAINT property_service_requests_service_category_check
  CHECK (service_category IN ('plumbing','building_work','electrical','furniture_assembly','painting','cleaning','safety','other'));

ALTER TABLE public.property_management_services
  DROP CONSTRAINT IF EXISTS property_management_services_service_category_check;
ALTER TABLE public.property_management_services
  ADD CONSTRAINT property_management_services_service_category_check
  CHECK (service_category IN ('plumbing','building_work','electrical','furniture_assembly','painting','cleaning','safety','other'));

CREATE OR REPLACE FUNCTION public.list_resident_services_with_categories(p_property_id uuid)
RETURNS TABLE(service_id uuid, title text, service_category text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.property_residents r
    WHERE r.property_id = p_property_id AND r.user_id = (SELECT auth.uid()) AND r.active
  ) THEN
    RAISE EXCEPTION 'Active apartment access is required.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT s.id, s.title, s.service_category
  FROM public.property_management_services s
  WHERE s.property_id = p_property_id AND s.active
  ORDER BY s.title;
END;
$$;
REVOKE ALL ON FUNCTION public.list_resident_services_with_categories(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_resident_services_with_categories(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_resident_service_request_v2(
  p_property_id uuid,
  p_apartment_number text,
  p_service_id uuid,
  p_request_type text,
  p_priority text,
  p_title text,
  p_description text,
  p_issue_scope text,
  p_location text,
  p_service_category text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_apartment_number text := CASE WHEN p_issue_scope = 'building' THEN 'common_area' ELSE p_apartment_number END;
  v_request_id uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  IF p_issue_scope NOT IN ('unit','building') THEN
    RAISE EXCEPTION 'Invalid issue scope.' USING ERRCODE = '22023';
  END IF;
  IF p_service_category NOT IN ('plumbing','building_work','electrical','furniture_assembly','painting','cleaning','safety','other') THEN
    RAISE EXCEPTION 'Invalid service category.' USING ERRCODE = '22023';
  END IF;
  v_request_id := public.submit_resident_service_request(
    p_property_id, v_apartment_number, p_service_id, p_request_type,
    p_priority, p_title, p_description, p_issue_scope, p_location
  );
  UPDATE public.property_service_requests
  SET service_category = p_service_category
  WHERE id = v_request_id AND requester_id = (SELECT auth.uid());
  RETURN v_request_id;
END;
$$;
REVOKE ALL ON FUNCTION public.submit_resident_service_request_v2(uuid,text,uuid,text,text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_resident_service_request_v2(uuid,text,uuid,text,text,text,text,text,text,text) TO authenticated;
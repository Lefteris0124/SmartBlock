BEGIN;

ALTER TABLE public.property_service_requests
  ADD COLUMN IF NOT EXISTS issue_scope text NOT NULL DEFAULT 'unit';
ALTER TABLE public.property_service_requests
  DROP CONSTRAINT IF EXISTS property_service_requests_issue_scope_check;
ALTER TABLE public.property_service_requests
  ADD CONSTRAINT property_service_requests_issue_scope_check
  CHECK (issue_scope IN ('unit','building'));

UPDATE public.property_service_requests
SET issue_scope = CASE WHEN apartment_number = 'common_area' THEN 'building' ELSE 'unit' END;

CREATE OR REPLACE FUNCTION public.submit_resident_service_request(
  p_property_id uuid,
  p_apartment_number text,
  p_service_id uuid,
  p_request_type text,
  p_priority text,
  p_title text,
  p_description text,
  p_issue_scope text,
  p_location text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_request_id uuid;
  v_apartment_number text := CASE WHEN p_issue_scope = 'building' THEN 'common_area' ELSE p_apartment_number END;
BEGIN
  IF p_issue_scope NOT IN ('unit','building') THEN
    RAISE EXCEPTION 'Invalid issue scope.' USING ERRCODE = '22023';
  END IF;
  IF p_request_type = 'damage_report' AND p_issue_scope = 'unit'
     AND v_apartment_number = 'common_area' THEN
    RAISE EXCEPTION 'Choose a unit for an apartment problem.' USING ERRCODE = '22023';
  END IF;

  v_request_id := public.submit_resident_service_request(
    p_property_id,
    v_apartment_number,
    p_service_id,
    p_request_type,
    p_priority,
    p_title,
    p_description,
    p_location
  );

  UPDATE public.property_service_requests
  SET issue_scope = p_issue_scope
  WHERE id = v_request_id AND requester_id = (SELECT auth.uid());

  RETURN v_request_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_resident_service_request(uuid,text,uuid,text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_resident_service_request(uuid,text,uuid,text,text,text,text,text,text) TO authenticated;

COMMIT;
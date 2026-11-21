-- Enforce the identity fields server-side so direct RPC calls cannot bypass
-- the application's duplicate-building check.
CREATE OR REPLACE FUNCTION public.create_property_draft_with_units(
    p_name text,
    p_property_type text,
    p_address text,
    p_city text,
    p_country text,
    p_management_model text,
    p_other_description text DEFAULT NULL,
    p_total_apartments integer DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    new_property_id uuid;
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
    END IF;
    IF p_property_type = 'building' AND (
      COALESCE(p_total_apartments, 0) < 1
      OR public.normalize_property_identity(p_address) = ''
      OR public.normalize_property_identity(p_city) = ''
    ) THEN
        RAISE EXCEPTION 'A building needs a full address, city, and apartment count.'
          USING ERRCODE = '22023';
    END IF;
    IF p_total_apartments IS NOT NULL AND p_total_apartments < 1 THEN
        RAISE EXCEPTION 'Apartment count must be at least 1.';
    END IF;
    IF p_property_type = 'other' AND NULLIF(btrim(p_other_description), '') IS NULL THEN
        RAISE EXCEPTION 'Describe the other property type.';
    END IF;

    INSERT INTO public.properties (
        organization_id, property_type, other_description, name, address,
        city, country, management_model, approval_status, created_by,
        total_apartments
    )
    VALUES (
        NULL, p_property_type, NULLIF(btrim(p_other_description), ''),
        btrim(p_name), btrim(p_address), NULLIF(btrim(p_city), ''),
        COALESCE(NULLIF(btrim(p_country), ''), 'Cyprus'), p_management_model,
        'draft', current_user_id, p_total_apartments
    )
    RETURNING id INTO new_property_id;
    RETURN new_property_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_property_draft_with_units(
  text, text, text, text, text, text, text, integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_property_draft_with_units(
  text, text, text, text, text, text, text, integer
) TO authenticated;

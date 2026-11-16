-- SB_103_Create_Property_With_Initial_Ownership
-- Creates a property and its initial ownership record in one database transaction.

CREATE OR REPLACE FUNCTION public.create_property_with_initial_ownership(
    p_organization_id uuid,
    p_name text,
    p_property_type text,
    p_address text,
    p_city text,
    p_management_model text,
    p_ownership_percentage numeric
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

    IF NOT public.can_manage_organization(p_organization_id) THEN
        RAISE EXCEPTION 'You cannot manage this organization.' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.properties (
        organization_id,
        property_type,
        name,
        address,
        city,
        management_model,
        approval_status,
        created_by
    )
    VALUES (
        p_organization_id,
        p_property_type,
        btrim(p_name),
        btrim(p_address),
        NULLIF(btrim(p_city), ''),
        p_management_model,
        'draft',
        current_user_id
    )
    RETURNING id INTO new_property_id;

    INSERT INTO public.property_owners (
        property_id,
        organization_id,
        ownership_percentage,
        is_primary_representative,
        ownership_status,
        created_by
    )
    VALUES (
        new_property_id,
        p_organization_id,
        p_ownership_percentage,
        true,
        'active',
        current_user_id
    );

    RETURN new_property_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_property_with_initial_ownership(
    uuid, text, text, text, text, text, numeric
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_property_with_initial_ownership(
    uuid, text, text, text, text, text, numeric
) TO authenticated;

-- SB_104_Submit_Property_For_Review
-- Lets the organization creator/representative submit a complete draft property
-- after the owning organization has been approved.

CREATE OR REPLACE FUNCTION public.submit_property_for_review(p_property_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    property_organization_id uuid;
    property_creator_id uuid;
    property_status text;
    organization_status text;
    active_ownership_total numeric;
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
    END IF;

    SELECT p.organization_id, p.created_by, p.approval_status, o.approval_status
    INTO property_organization_id, property_creator_id, property_status, organization_status
    FROM public.properties AS p
    JOIN public.organizations AS o ON o.id = p.organization_id
    WHERE p.id = p_property_id
    FOR UPDATE OF p;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Property not found.' USING ERRCODE = 'P0002';
    END IF;

    IF property_creator_id <> current_user_id
       OR NOT public.can_manage_organization(property_organization_id) THEN
        RAISE EXCEPTION 'You cannot submit this property.' USING ERRCODE = '42501';
    END IF;

    IF organization_status <> 'approved' THEN
        RAISE EXCEPTION 'The organization must be approved before property review.';
    END IF;

    IF property_status NOT IN ('draft', 'changes_required') THEN
        RAISE EXCEPTION 'Only draft properties can be submitted for review.';
    END IF;

    SELECT COALESCE(SUM(po.ownership_percentage), 0)
    INTO active_ownership_total
    FROM public.property_owners AS po
    WHERE po.property_id = p_property_id
      AND po.ownership_status = 'active';

    IF active_ownership_total <> 100 THEN
        RAISE EXCEPTION 'Active ownership shares must total 100%% before submission.';
    END IF;

    UPDATE public.properties
    SET approval_status = 'pending_review',
        updated_at = now()
    WHERE id = p_property_id;

    RETURN p_property_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_property_for_review(uuid)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_property_for_review(uuid)
TO authenticated;

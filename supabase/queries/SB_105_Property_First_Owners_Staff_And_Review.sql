-- SB_105_Property_First_Owners_Staff_And_Review
-- Makes properties independently creatable, adds phone-based owner matching,
-- and introduces database-verified SmartBlock staff access.

BEGIN;

CREATE TABLE IF NOT EXISTS public.smartblock_staff (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    staff_role text NOT NULL DEFAULT 'admin'
        CHECK (staff_role IN ('admin', 'reviewer')),
    is_active boolean NOT NULL DEFAULT true,
    assigned_by uuid REFERENCES auth.users(id),
    assigned_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.smartblock_staff ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.smartblock_staff FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_smartblock_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.smartblock_staff AS staff
        WHERE staff.user_id = (SELECT auth.uid())
          AND staff.is_active
          AND staff.staff_role IN ('admin', 'reviewer')
    );
$function$;

REVOKE ALL ON FUNCTION public.is_smartblock_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_smartblock_staff() TO authenticated;

DROP POLICY IF EXISTS organizations_select_accessible ON public.organizations;
CREATE POLICY organizations_select_accessible
ON public.organizations FOR SELECT TO authenticated
USING (public.can_access_organization(id));

DROP POLICY IF EXISTS properties_select_accessible ON public.properties;
CREATE POLICY properties_select_accessible
ON public.properties FOR SELECT TO authenticated
USING (public.can_access_property(id));

ALTER TABLE public.organizations
    ADD COLUMN IF NOT EXISTS phone_e164 text;

ALTER TABLE public.organizations
    DROP CONSTRAINT IF EXISTS organizations_phone_e164_check;
ALTER TABLE public.organizations
    ADD CONSTRAINT organizations_phone_e164_check
    CHECK (phone_e164 IS NULL OR phone_e164 ~ '^\+[1-9][0-9]{6,14}$');

CREATE UNIQUE INDEX IF NOT EXISTS idx_organizations_phone_e164
    ON public.organizations (phone_e164)
    WHERE phone_e164 IS NOT NULL;

ALTER TABLE public.properties
    ALTER COLUMN organization_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS other_description text;

UPDATE public.properties
SET other_description = 'Unspecified'
WHERE property_type = 'other'
  AND NULLIF(btrim(other_description), '') IS NULL;

ALTER TABLE public.properties
    DROP CONSTRAINT IF EXISTS properties_property_type_check;
ALTER TABLE public.properties
    ADD CONSTRAINT properties_property_type_check
    CHECK (property_type IN (
        'apartment', 'building', 'house', 'shop', 'office',
        'warehouse', 'land', 'other'
    ));

ALTER TABLE public.properties
    DROP CONSTRAINT IF EXISTS properties_other_description_check;
ALTER TABLE public.properties
    ADD CONSTRAINT properties_other_description_check
    CHECK (
        (property_type = 'other' AND NULLIF(btrim(other_description), '') IS NOT NULL)
        OR property_type <> 'other'
    );

CREATE OR REPLACE FUNCTION public.can_access_organization(target_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT public.is_smartblock_staff()
        OR EXISTS (
            SELECT 1 FROM public.organizations AS organization_row
            WHERE organization_row.id = target_organization_id
              AND organization_row.created_by = (SELECT auth.uid())
        )
        OR EXISTS (
            SELECT 1 FROM public.organization_members AS membership
            WHERE membership.organization_id = target_organization_id
              AND membership.user_id = (SELECT auth.uid())
              AND membership.membership_status = 'active'
        )
        OR EXISTS (
            SELECT 1
            FROM public.property_owners AS owner_row
            JOIN public.properties AS property_row
              ON property_row.id = owner_row.property_id
            WHERE owner_row.organization_id = target_organization_id
              AND owner_row.ownership_status = 'active'
              AND property_row.created_by = (SELECT auth.uid())
        );
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_organization(target_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT public.is_smartblock_staff()
        OR EXISTS (
            SELECT 1 FROM public.organizations AS organization_row
            WHERE organization_row.id = target_organization_id
              AND organization_row.created_by = (SELECT auth.uid())
        )
        OR EXISTS (
            SELECT 1 FROM public.organization_members AS membership
            WHERE membership.organization_id = target_organization_id
              AND membership.user_id = (SELECT auth.uid())
              AND membership.membership_status = 'active'
              AND membership.member_role IN ('owner', 'representative')
        );
$function$;

CREATE OR REPLACE FUNCTION public.can_access_property(target_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT public.is_smartblock_staff()
        OR EXISTS (
            SELECT 1 FROM public.properties AS property_row
            WHERE property_row.id = target_property_id
              AND property_row.created_by = (SELECT auth.uid())
        )
        OR EXISTS (
            SELECT 1 FROM public.properties AS property_row
            WHERE property_row.id = target_property_id
              AND property_row.organization_id IS NOT NULL
              AND public.can_access_organization(property_row.organization_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.property_owners AS owner_row
            WHERE owner_row.property_id = target_property_id
              AND owner_row.ownership_status = 'active'
              AND public.can_access_organization(owner_row.organization_id)
        );
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_property(target_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT public.is_smartblock_staff()
        OR EXISTS (
            SELECT 1 FROM public.properties AS property_row
            WHERE property_row.id = target_property_id
              AND property_row.created_by = (SELECT auth.uid())
              AND property_row.approval_status IN ('draft', 'changes_required')
        )
        OR EXISTS (
            SELECT 1
            FROM public.property_owners AS owner_row
            WHERE owner_row.property_id = target_property_id
              AND owner_row.ownership_status = 'active'
              AND public.can_manage_organization(owner_row.organization_id)
        );
$function$;

REVOKE ALL ON FUNCTION public.can_access_organization(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_organization(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_access_property(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_property(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_organization(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_organization(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_property(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_property(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_property_draft(
    p_name text,
    p_property_type text,
    p_address text,
    p_city text,
    p_country text,
    p_management_model text,
    p_other_description text DEFAULT NULL
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

    IF p_property_type = 'other' AND NULLIF(btrim(p_other_description), '') IS NULL THEN
        RAISE EXCEPTION 'Describe the other property type.';
    END IF;

    INSERT INTO public.properties (
        organization_id, property_type, other_description, name, address,
        city, country, management_model, approval_status, created_by
    )
    VALUES (
        NULL, p_property_type, NULLIF(btrim(p_other_description), ''),
        btrim(p_name), btrim(p_address), NULLIF(btrim(p_city), ''),
        COALESCE(NULLIF(btrim(p_country), ''), 'Cyprus'), p_management_model,
        'draft', current_user_id
    )
    RETURNING id INTO new_property_id;

    RETURN new_property_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_property_draft(text, text, text, text, text, text, text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_property_draft(text, text, text, text, text, text, text)
TO authenticated;

CREATE OR REPLACE FUNCTION public.add_property_owner_by_phone(
    p_property_id uuid,
    p_phone_e164 text,
    p_display_name text,
    p_organization_type text,
    p_ownership_percentage numeric,
    p_is_primary_representative boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    property_creator_id uuid;
    property_status text;
    matched_organization_id uuid;
    matched_display_name text;
    matched_approval_status text;
    has_primary_owner boolean;
    active_share_total numeric(7, 2);
    was_created boolean := false;
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
    END IF;

    SELECT p.created_by, p.approval_status
    INTO property_creator_id, property_status
    FROM public.properties AS p
    WHERE p.id = p_property_id
    FOR UPDATE;

    IF NOT FOUND OR property_creator_id <> current_user_id
       OR property_status NOT IN ('draft', 'changes_required') THEN
        RAISE EXCEPTION 'Only the creator can add owners to a draft property.'
            USING ERRCODE = '42501';
    END IF;

    IF p_phone_e164 IS NULL OR p_phone_e164 !~ '^\+[1-9][0-9]{6,14}$' THEN
        RAISE EXCEPTION 'Enter the phone in international format, e.g. +35799123456.';
    END IF;

    IF p_ownership_percentage <= 0 OR p_ownership_percentage > 100 THEN
        RAISE EXCEPTION 'Ownership share must be between 0.01 and 100.';
    END IF;

    SELECT COALESCE(SUM(po.ownership_percentage), 0)
    INTO active_share_total
    FROM public.property_owners AS po
    WHERE po.property_id = p_property_id
      AND po.ownership_status = 'active';

    IF active_share_total + p_ownership_percentage > 100 THEN
        RAISE EXCEPTION 'Ownership shares cannot exceed 100%%.';
    END IF;

    SELECT o.id, o.display_name, o.approval_status
    INTO matched_organization_id, matched_display_name, matched_approval_status
    FROM public.organizations AS o
    WHERE o.phone_e164 = p_phone_e164
    FOR UPDATE;

    IF matched_organization_id IS NULL THEN
        IF NULLIF(btrim(p_display_name), '') IS NULL THEN
            RAISE EXCEPTION 'Enter the owner name because this phone is not registered.';
        END IF;
        IF p_organization_type NOT IN ('individual', 'company') THEN
            RAISE EXCEPTION 'Invalid owner type.';
        END IF;

        INSERT INTO public.organizations (
            organization_type, display_name, phone_e164, approval_status, created_by
        )
        VALUES (
            p_organization_type, btrim(p_display_name), p_phone_e164,
            'pending_review', current_user_id
        )
        RETURNING id, display_name, approval_status
        INTO matched_organization_id, matched_display_name, matched_approval_status;
        was_created := true;
    ELSIF matched_approval_status IN ('rejected', 'suspended') THEN
        RAISE EXCEPTION 'This owner record cannot currently be linked.';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.property_owners AS po
        WHERE po.property_id = p_property_id
          AND po.ownership_status = 'active'
          AND po.is_primary_representative
    ) INTO has_primary_owner;

    IF NOT has_primary_owner AND p_is_primary_representative = false THEN
        p_is_primary_representative := true;
    END IF;

    INSERT INTO public.property_owners (
        property_id, organization_id, ownership_percentage,
        is_primary_representative, ownership_status, created_by
    )
    VALUES (
        p_property_id, matched_organization_id, p_ownership_percentage,
        p_is_primary_representative, 'active', current_user_id
    );

    UPDATE public.properties
    SET organization_id = COALESCE(organization_id, matched_organization_id),
        updated_at = now()
    WHERE id = p_property_id;

    RETURN jsonb_build_object(
        'organization_id', matched_organization_id,
        'display_name', matched_display_name,
        'approval_status', matched_approval_status,
        'created', was_created
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.add_property_owner_by_phone(uuid, text, text, text, numeric, boolean)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.add_property_owner_by_phone(uuid, text, text, text, numeric, boolean)
TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_property_for_review(p_property_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    property_creator_id uuid;
    property_status text;
    owner_organization_id uuid;
    organization_status text;
    active_ownership_total numeric;
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
    END IF;

    SELECT p.created_by, p.approval_status, p.organization_id
    INTO property_creator_id, property_status, owner_organization_id
    FROM public.properties AS p
    WHERE p.id = p_property_id
    FOR UPDATE;

    IF NOT FOUND OR property_creator_id <> current_user_id THEN
        RAISE EXCEPTION 'You cannot submit this property.' USING ERRCODE = '42501';
    END IF;

    IF property_status NOT IN ('draft', 'changes_required') THEN
        RAISE EXCEPTION 'Only draft properties can be submitted for review.';
    END IF;

    SELECT po.organization_id
    INTO owner_organization_id
    FROM public.property_owners AS po
    WHERE po.property_id = p_property_id
      AND po.ownership_status = 'active'
      AND po.is_primary_representative
    LIMIT 1;

    IF owner_organization_id IS NULL THEN
        RAISE EXCEPTION 'Add a primary owner organization before submission.';
    END IF;

    SELECT o.approval_status INTO organization_status
    FROM public.organizations AS o WHERE o.id = owner_organization_id;

    IF organization_status <> 'approved' THEN
        RAISE EXCEPTION 'The primary owner organization must be approved before property review.';
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
    SET organization_id = owner_organization_id,
        approval_status = 'pending_review',
        updated_at = now()
    WHERE id = p_property_id;

    RETURN p_property_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_property_for_review(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_property_for_review(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.review_organization(
    p_organization_id uuid,
    p_status text,
    p_review_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NOT public.is_smartblock_staff() THEN
        RAISE EXCEPTION 'SmartBlock staff access is required.' USING ERRCODE = '42501';
    END IF;
    IF p_status NOT IN ('approved', 'changes_required', 'rejected', 'suspended') THEN
        RAISE EXCEPTION 'Invalid organization review status.';
    END IF;

    UPDATE public.organizations
    SET approval_status = p_status,
        review_notes = NULLIF(btrim(p_review_notes), ''),
        reviewed_by = (SELECT auth.uid()),
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_organization_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found.'; END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.review_property(
    p_property_id uuid,
    p_status text,
    p_review_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NOT public.is_smartblock_staff() THEN
        RAISE EXCEPTION 'SmartBlock staff access is required.' USING ERRCODE = '42501';
    END IF;
    IF p_status NOT IN ('approved', 'changes_required', 'rejected', 'suspended') THEN
        RAISE EXCEPTION 'Invalid property review status.';
    END IF;

    UPDATE public.properties
    SET approval_status = p_status,
        review_notes = NULLIF(btrim(p_review_notes), ''),
        reviewed_by = (SELECT auth.uid()),
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_property_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Property not found.'; END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.review_organization(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.review_property(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_organization(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_property(uuid, text, text) TO authenticated;

COMMIT;

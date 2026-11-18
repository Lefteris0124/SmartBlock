-- SB_109_Apartment_Area_Ownership_Deeds
-- Captures property unit counts, owners' area declarations, and private deed photos.

BEGIN;

ALTER TABLE public.properties
    ADD COLUMN IF NOT EXISTS total_apartments integer;
ALTER TABLE public.properties
    DROP CONSTRAINT IF EXISTS properties_total_apartments_check;
ALTER TABLE public.properties
    ADD CONSTRAINT properties_total_apartments_check
    CHECK (total_apartments IS NULL OR total_apartments > 0);

ALTER TABLE public.property_owners
    ADD COLUMN IF NOT EXISTS apartment_count integer,
    ADD COLUMN IF NOT EXISTS area_sqm numeric(10, 2),
    ADD COLUMN IF NOT EXISTS title_deed_photo_path text,
    ADD COLUMN IF NOT EXISTS area_declaration_confirmed_at timestamptz,
    ADD COLUMN IF NOT EXISTS area_declaration_confirmed_by uuid REFERENCES auth.users(id);

ALTER TABLE public.property_owners
    ALTER COLUMN ownership_percentage TYPE numeric(7, 4);
ALTER TABLE public.property_owners
    DROP CONSTRAINT IF EXISTS property_owners_area_declaration_check;
ALTER TABLE public.property_owners
    ADD CONSTRAINT property_owners_area_declaration_check
    CHECK (
        (apartment_count IS NULL AND area_sqm IS NULL
            AND title_deed_photo_path IS NULL
            AND area_declaration_confirmed_at IS NULL
            AND area_declaration_confirmed_by IS NULL)
        OR
        (apartment_count IS NOT NULL AND apartment_count > 0
            AND area_sqm IS NOT NULL AND area_sqm > 0
            AND title_deed_photo_path IS NOT NULL
            AND area_declaration_confirmed_at IS NOT NULL
            AND area_declaration_confirmed_by IS NOT NULL)
    );

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'smartblock-title-deeds',
    'smartblock-title-deeds',
    false,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']::text[];

CREATE OR REPLACE FUNCTION public.can_manage_owner_organization(target_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT public.is_smartblock_admin()
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

CREATE OR REPLACE FUNCTION public.my_manageable_organization_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT organization_row.id
    FROM public.organizations AS organization_row
    WHERE public.can_manage_owner_organization(organization_row.id);
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_property_owner_declaration(
    target_owner_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT public.is_smartblock_admin()
        OR EXISTS (
            SELECT 1 FROM public.property_owners AS owner_row
            JOIN public.properties AS property_row ON property_row.id = owner_row.property_id
            WHERE owner_row.id = target_owner_id
              AND public.can_manage_owner_organization(owner_row.organization_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.property_owners AS owner_row
            JOIN public.properties AS property_row ON property_row.id = owner_row.property_id
            WHERE owner_row.id = target_owner_id
              AND property_row.created_by = (SELECT auth.uid())
              AND property_row.approval_status IN ('draft', 'changes_required')
        );
$function$;

REVOKE ALL ON FUNCTION public.can_manage_owner_organization(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.my_manageable_organization_ids() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_property_owner_declaration(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_owner_organization(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_manageable_organization_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_property_owner_declaration(uuid) TO authenticated;

DROP POLICY IF EXISTS smartblock_deed_select ON storage.objects;
CREATE POLICY smartblock_deed_select ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'smartblock-title-deeds'
    AND EXISTS (
        SELECT 1 FROM public.property_owners AS owner_row
        WHERE owner_row.id::text = split_part(name, '/', 2)
          AND owner_row.property_id::text = split_part(name, '/', 1)
          AND public.can_manage_property_owner_declaration(owner_row.id)
    )
);

DROP POLICY IF EXISTS smartblock_deed_insert ON storage.objects;
CREATE POLICY smartblock_deed_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'smartblock-title-deeds'
    AND EXISTS (
        SELECT 1 FROM public.property_owners AS owner_row
        WHERE owner_row.id::text = split_part(name, '/', 2)
          AND owner_row.property_id::text = split_part(name, '/', 1)
          AND public.can_manage_property_owner_declaration(owner_row.id)
    )
);

DROP POLICY IF EXISTS smartblock_deed_update ON storage.objects;
CREATE POLICY smartblock_deed_update ON storage.objects
FOR UPDATE TO authenticated
USING (
    bucket_id = 'smartblock-title-deeds'
    AND EXISTS (
        SELECT 1 FROM public.property_owners AS owner_row
        WHERE owner_row.id::text = split_part(name, '/', 2)
          AND owner_row.property_id::text = split_part(name, '/', 1)
          AND public.can_manage_property_owner_declaration(owner_row.id)
    )
)
WITH CHECK (
    bucket_id = 'smartblock-title-deeds'
    AND EXISTS (
        SELECT 1 FROM public.property_owners AS owner_row
        WHERE owner_row.id::text = split_part(name, '/', 2)
          AND owner_row.property_id::text = split_part(name, '/', 1)
          AND public.can_manage_property_owner_declaration(owner_row.id)
    )
);

DROP POLICY IF EXISTS smartblock_deed_delete ON storage.objects;
CREATE POLICY smartblock_deed_delete ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'smartblock-title-deeds'
    AND EXISTS (
        SELECT 1 FROM public.property_owners AS owner_row
        WHERE owner_row.id::text = split_part(name, '/', 2)
          AND owner_row.property_id::text = split_part(name, '/', 1)
          AND public.can_manage_owner_organization(owner_row.organization_id)
    )
);

DROP TRIGGER IF EXISTS trg_check_property_ownership_percentage ON public.property_owners;

CREATE OR REPLACE FUNCTION public.enforce_property_owner_apartment_count()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
    total_apartments integer;
    already_declared integer;
BEGIN
    IF NEW.ownership_status <> 'active' OR NEW.apartment_count IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT p.total_apartments INTO total_apartments
    FROM public.properties AS p WHERE p.id = NEW.property_id;

    SELECT COALESCE(SUM(owner_row.apartment_count), 0)::integer
    INTO already_declared
    FROM public.property_owners AS owner_row
    WHERE owner_row.property_id = NEW.property_id
      AND owner_row.ownership_status = 'active'
      AND owner_row.apartment_count IS NOT NULL
      AND owner_row.id <> NEW.id;

    IF total_apartments IS NOT NULL
       AND already_declared + NEW.apartment_count > total_apartments THEN
        RAISE EXCEPTION 'Declared apartments exceed the property total of %.', total_apartments;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_enforce_property_owner_apartment_count
BEFORE INSERT OR UPDATE OF property_id, ownership_status, apartment_count
ON public.property_owners
FOR EACH ROW EXECUTE FUNCTION public.enforce_property_owner_apartment_count();

CREATE OR REPLACE FUNCTION public.recalculate_property_area_shares(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    active_count integer;
    incomplete_count integer;
    declared_apartments integer;
    expected_apartments integer;
    total_area numeric;
    allocated numeric := 0;
    row_number integer := 0;
    owner_row record;
    calculated_share numeric(7, 4);
BEGIN
    SELECT p.total_apartments INTO expected_apartments
    FROM public.properties AS p WHERE p.id = p_property_id;

    SELECT COUNT(*)::integer,
           COUNT(*) FILTER (
               WHERE owner_row.apartment_count IS NULL
                  OR owner_row.area_sqm IS NULL
                  OR owner_row.title_deed_photo_path IS NULL
                  OR owner_row.area_declaration_confirmed_at IS NULL
           )::integer,
           COALESCE(SUM(owner_row.apartment_count), 0)::integer,
           COALESCE(SUM(owner_row.area_sqm), 0)
    INTO active_count, incomplete_count, declared_apartments, total_area
    FROM public.property_owners AS owner_row
    WHERE owner_row.property_id = p_property_id
      AND owner_row.ownership_status = 'active';

    IF active_count = 0 OR incomplete_count > 0 OR total_area <= 0 THEN
        RETURN;
    END IF;
    IF expected_apartments IS NOT NULL
       AND declared_apartments <> expected_apartments THEN
        RETURN;
    END IF;

    FOR owner_row IN
        SELECT id, area_sqm
        FROM public.property_owners
        WHERE property_id = p_property_id AND ownership_status = 'active'
        ORDER BY id
    LOOP
        row_number := row_number + 1;
        IF row_number = active_count THEN
            calculated_share := 100.0000 - allocated;
        ELSE
            calculated_share := round(owner_row.area_sqm * 100.0 / total_area, 4);
            allocated := allocated + calculated_share;
        END IF;
        UPDATE public.property_owners
        SET ownership_percentage = calculated_share
        WHERE id = owner_row.id
          AND ownership_percentage IS DISTINCT FROM calculated_share;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trigger_recalculate_property_area_shares()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
    PERFORM public.recalculate_property_area_shares(
        CASE WHEN TG_OP = 'DELETE' THEN OLD.property_id ELSE NEW.property_id END
    );
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_recalculate_property_area_shares ON public.property_owners;
CREATE TRIGGER trg_recalculate_property_area_shares
AFTER INSERT OR UPDATE OF property_id, ownership_status, apartment_count,
    area_sqm, title_deed_photo_path, area_declaration_confirmed_at
ON public.property_owners
FOR EACH ROW EXECUTE FUNCTION public.trigger_recalculate_property_area_shares();

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
    IF p_property_type = 'building' AND COALESCE(p_total_apartments, 0) < 1 THEN
        RAISE EXCEPTION 'Enter the number of apartments in the building.';
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

REVOKE ALL ON FUNCTION public.create_property_draft(text, text, text, text, text, text, text)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_property_draft_with_units(text, text, text, text, text, text, text, integer)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_property_draft_with_units(text, text, text, text, text, text, text, integer)
TO authenticated;

CREATE OR REPLACE FUNCTION public.create_property_owner_registration(
    p_property_id uuid,
    p_phone_e164 text,
    p_display_name text,
    p_organization_type text,
    p_is_primary_representative boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    property_row public.properties%ROWTYPE;
    matched_organization_id uuid;
    matched_display_name text;
    matched_approval_status text;
    active_count integer;
    new_owner_id uuid;
    was_created boolean := false;
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO property_row FROM public.properties
    WHERE id = p_property_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Property not found.'; END IF;
    IF NOT public.is_smartblock_admin()
       AND NOT (property_row.created_by = current_user_id
                AND property_row.approval_status IN ('draft', 'changes_required'))
       AND NOT EXISTS (
           SELECT 1 FROM public.property_owners AS owner_row
           WHERE owner_row.property_id = p_property_id
             AND owner_row.ownership_status = 'active'
             AND public.can_manage_owner_organization(owner_row.organization_id)
       ) THEN
        RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
    END IF;
    IF property_row.property_type = 'building'
       AND property_row.total_apartments IS NULL THEN
        RAISE EXCEPTION 'Set the number of apartments before adding owners.';
    END IF;
    IF p_phone_e164 IS NULL OR p_phone_e164 !~ '^\+[1-9][0-9]{6,14}$' THEN
        RAISE EXCEPTION 'Enter the phone in international format, e.g. +35799123456.';
    END IF;

    SELECT o.id, o.display_name, o.approval_status
    INTO matched_organization_id, matched_display_name, matched_approval_status
    FROM public.organizations AS o
    WHERE o.phone_e164 = p_phone_e164 FOR UPDATE;

    IF matched_organization_id IS NULL THEN
        IF NULLIF(btrim(p_display_name), '') IS NULL THEN
            RAISE EXCEPTION 'Enter the owner name because this phone is not registered.';
        END IF;
        IF p_organization_type NOT IN ('individual', 'company') THEN
            RAISE EXCEPTION 'Invalid owner type.';
        END IF;
        INSERT INTO public.organizations (
            organization_type, display_name, phone_e164, approval_status, created_by
        ) VALUES (
            p_organization_type, btrim(p_display_name), p_phone_e164,
            'pending_review', current_user_id
        )
        RETURNING id, display_name, approval_status
        INTO matched_organization_id, matched_display_name, matched_approval_status;
        was_created := true;
    ELSIF matched_approval_status IN ('rejected', 'suspended') THEN
        RAISE EXCEPTION 'This owner record cannot currently be linked.';
    END IF;

    SELECT COUNT(*)::integer INTO active_count
    FROM public.property_owners
    WHERE property_id = p_property_id AND ownership_status = 'active';
    IF NOT EXISTS (
        SELECT 1 FROM public.property_owners
        WHERE property_id = p_property_id
          AND ownership_status = 'active'
          AND is_primary_representative
    ) THEN
        p_is_primary_representative := true;
    END IF;

    INSERT INTO public.property_owners (
        property_id, organization_id, ownership_percentage,
        is_primary_representative, ownership_status, created_by
    ) VALUES (
        p_property_id, matched_organization_id,
        CASE WHEN active_count = 0 THEN 100 ELSE 1 END,
        p_is_primary_representative, 'active', current_user_id
    ) RETURNING id INTO new_owner_id;

    UPDATE public.properties
    SET organization_id = COALESCE(organization_id, matched_organization_id),
        updated_at = now()
    WHERE id = p_property_id;

    RETURN jsonb_build_object(
        'owner_id', new_owner_id,
        'organization_id', matched_organization_id,
        'display_name', matched_display_name,
        'approval_status', matched_approval_status,
        'created', was_created
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_property_owner_area_declaration(
    p_owner_id uuid,
    p_apartment_count integer,
    p_area_sqm numeric,
    p_title_deed_photo_path text
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    owner_row public.property_owners%ROWTYPE;
    property_total_apartments integer;
    other_apartments integer;
BEGIN
    SELECT * INTO owner_row FROM public.property_owners
    WHERE id = p_owner_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Owner record not found.'; END IF;
    IF NOT public.can_manage_property_owner_declaration(owner_row.id) THEN
        RAISE EXCEPTION 'Only this owner organization or a SmartBlock admin can submit its declaration.'
            USING ERRCODE = '42501';
    END IF;
    IF p_apartment_count IS NULL OR p_apartment_count < 1 THEN
        RAISE EXCEPTION 'Apartment count must be at least 1.';
    END IF;
    IF p_area_sqm IS NULL OR p_area_sqm <= 0 THEN
        RAISE EXCEPTION 'Enter a positive area in square metres.';
    END IF;
    IF p_title_deed_photo_path IS NULL
       OR split_part(p_title_deed_photo_path, '/', 1) <> owner_row.property_id::text
       OR split_part(p_title_deed_photo_path, '/', 2) <> owner_row.id::text
       OR split_part(p_title_deed_photo_path, '/', 3) = ''
       OR split_part(p_title_deed_photo_path, '/', 4) <> '' THEN
        RAISE EXCEPTION 'Invalid title deed image path.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM storage.objects AS file_row
        WHERE file_row.bucket_id = 'smartblock-title-deeds'
          AND file_row.name = p_title_deed_photo_path
    ) THEN
        RAISE EXCEPTION 'Upload the title deed photo before saving the declaration.';
    END IF;

    SELECT p.total_apartments INTO property_total_apartments
    FROM public.properties AS p WHERE p.id = owner_row.property_id;
    SELECT COALESCE(SUM(apartment_count), 0)::integer INTO other_apartments
    FROM public.property_owners
    WHERE property_id = owner_row.property_id
      AND ownership_status = 'active'
      AND apartment_count IS NOT NULL
      AND id <> owner_row.id;
    IF property_total_apartments IS NOT NULL
       AND other_apartments + p_apartment_count > property_total_apartments THEN
        RAISE EXCEPTION 'The declarations exceed the property total of % apartments.', property_total_apartments;
    END IF;

    UPDATE public.property_owners
    SET apartment_count = p_apartment_count,
        area_sqm = round(p_area_sqm, 2),
        title_deed_photo_path = p_title_deed_photo_path,
        area_declaration_confirmed_at = now(),
        area_declaration_confirmed_by = (SELECT auth.uid()),
        updated_at = now()
    WHERE id = p_owner_id;

    SELECT ownership_percentage INTO p_area_sqm
    FROM public.property_owners WHERE id = p_owner_id;
    RETURN p_area_sqm;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rollback_property_owner_registration(p_owner_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE owner_row public.property_owners%ROWTYPE;
BEGIN
    SELECT * INTO owner_row FROM public.property_owners
    WHERE id = p_owner_id FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF owner_row.title_deed_photo_path IS NOT NULL
       OR owner_row.area_sqm IS NOT NULL THEN
        RAISE EXCEPTION 'This owner declaration cannot be rolled back.' USING ERRCODE = '42501';
    END IF;
    IF owner_row.created_by <> (SELECT auth.uid())
       AND NOT public.is_smartblock_admin()
       AND NOT public.can_manage_owner_organization(owner_row.organization_id) THEN
        RAISE EXCEPTION 'Owner organization access is required.' USING ERRCODE = '42501';
    END IF;
    DELETE FROM public.property_owners WHERE id = p_owner_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_property_for_review(p_property_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    property_row public.properties%ROWTYPE;
    owner_organization_id uuid;
    organization_status text;
    active_ownership_total numeric;
    active_owner_count integer;
    incomplete_owner_count integer;
    declared_apartments integer;
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO property_row FROM public.properties
    WHERE id = p_property_id FOR UPDATE;
    IF NOT FOUND OR property_row.created_by <> current_user_id THEN
        RAISE EXCEPTION 'You cannot submit this property.' USING ERRCODE = '42501';
    END IF;
    IF property_row.approval_status NOT IN ('draft', 'changes_required') THEN
        RAISE EXCEPTION 'Only draft properties can be submitted for review.';
    END IF;
    IF property_row.property_type = 'building'
       AND COALESCE(property_row.total_apartments, 0) < 1 THEN
        RAISE EXCEPTION 'Enter the total number of apartments first.';
    END IF;

    SELECT po.organization_id INTO owner_organization_id
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

    SELECT COUNT(*)::integer,
           COUNT(*) FILTER (
               WHERE apartment_count IS NULL OR area_sqm IS NULL
                  OR title_deed_photo_path IS NULL
                  OR area_declaration_confirmed_at IS NULL
           )::integer,
           COALESCE(SUM(apartment_count), 0)::integer,
           COALESCE(SUM(ownership_percentage), 0)
    INTO active_owner_count, incomplete_owner_count,
         declared_apartments, active_ownership_total
    FROM public.property_owners
    WHERE property_id = p_property_id AND ownership_status = 'active';

    IF active_owner_count = 0 OR incomplete_owner_count > 0 THEN
        RAISE EXCEPTION 'Every active owner must declare units and area and upload a title deed photo.';
    END IF;
    IF property_row.total_apartments IS NOT NULL
       AND declared_apartments <> property_row.total_apartments THEN
        RAISE EXCEPTION 'Declared apartment count (%) must equal the property total (%).',
            declared_apartments, property_row.total_apartments;
    END IF;
    IF active_ownership_total <> 100 THEN
        RAISE EXCEPTION 'Area-based ownership shares must total 100%% before submission.';
    END IF;

    UPDATE public.properties
    SET organization_id = owner_organization_id,
        approval_status = 'pending_review',
        updated_at = now()
    WHERE id = p_property_id;
    RETURN p_property_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_property_owner_registration(uuid, text, text, text, boolean)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_property_owner_area_declaration(uuid, integer, numeric, text)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rollback_property_owner_registration(uuid)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_property_owner_registration(uuid, text, text, text, boolean)
TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_property_owner_area_declaration(uuid, integer, numeric, text)
TO authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_property_owner_registration(uuid)
TO authenticated;
REVOKE ALL ON FUNCTION public.add_property_owner_by_phone(uuid, text, text, text, numeric, boolean)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_property_for_review(uuid) TO authenticated;

COMMIT;


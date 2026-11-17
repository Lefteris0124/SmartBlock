-- SB_108_SmartBlock_Admin_Controls
-- Secure, app-level administration for SmartBlock administrators.

BEGIN;

CREATE OR REPLACE FUNCTION public.is_smartblock_admin()
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
          AND staff.staff_role = 'admin'
    );
$function$;

REVOKE ALL ON FUNCTION public.is_smartblock_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_smartblock_admin() TO authenticated;

-- Admins can manage all product data. Reviewers retain only review permissions.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
    public.organizations,
    public.organization_members,
    public.property_portfolios,
    public.properties,
    public.property_owners,
    public.property_votes,
    public.property_vote_options,
    public.property_vote_ballots,
    public.property_charge_runs,
    public.property_charge_entries,
    public.property_rent_contracts,
    public.property_rent_installments,
    public.property_notes
TO authenticated;

DROP POLICY IF EXISTS smartblock_admin_all ON public.organizations;
CREATE POLICY smartblock_admin_all ON public.organizations
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.organization_members;
CREATE POLICY smartblock_admin_all ON public.organization_members
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_portfolios;
CREATE POLICY smartblock_admin_all ON public.property_portfolios
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.properties;
CREATE POLICY smartblock_admin_all ON public.properties
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_owners;
CREATE POLICY smartblock_admin_all ON public.property_owners
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_votes;
CREATE POLICY smartblock_admin_all ON public.property_votes
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_vote_options;
CREATE POLICY smartblock_admin_all ON public.property_vote_options
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_vote_ballots;
CREATE POLICY smartblock_admin_all ON public.property_vote_ballots
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_charge_runs;
CREATE POLICY smartblock_admin_all ON public.property_charge_runs
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_charge_entries;
CREATE POLICY smartblock_admin_all ON public.property_charge_entries
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_rent_contracts;
CREATE POLICY smartblock_admin_all ON public.property_rent_contracts
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_rent_installments;
CREATE POLICY smartblock_admin_all ON public.property_rent_installments
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());
DROP POLICY IF EXISTS smartblock_admin_all ON public.property_notes;
CREATE POLICY smartblock_admin_all ON public.property_notes
    FOR ALL TO authenticated
    USING (public.is_smartblock_admin())
    WITH CHECK (public.is_smartblock_admin());

CREATE OR REPLACE FUNCTION public.admin_delete_property(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NOT public.is_smartblock_admin() THEN
        RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE = '42501';
    END IF;

    DELETE FROM public.property_charge_entries AS entry
    USING public.property_charge_runs AS run
    WHERE entry.run_id = run.id AND run.property_id = p_property_id;

    DELETE FROM public.property_owners
    WHERE property_id = p_property_id;

    DELETE FROM public.properties
    WHERE id = p_property_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Property not found.';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_organization(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NOT public.is_smartblock_admin() THEN
        RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE = '42501';
    END IF;

    IF EXISTS (SELECT 1 FROM public.properties WHERE organization_id = p_organization_id)
       OR EXISTS (SELECT 1 FROM public.property_owners WHERE organization_id = p_organization_id) THEN
        RAISE EXCEPTION 'Organization is linked to properties or ownership records. Remove those links first.';
    END IF;

    DELETE FROM public.organization_members WHERE organization_id = p_organization_id;
    DELETE FROM public.property_portfolios WHERE organization_id = p_organization_id;
    DELETE FROM public.organizations WHERE id = p_organization_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Organization not found.';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_property(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_delete_organization(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_property(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_organization(uuid) TO authenticated;

COMMIT;


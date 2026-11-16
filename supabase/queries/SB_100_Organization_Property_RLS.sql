-- SB_100_Organization_Property_RLS
-- Establishes a conservative authenticated-user access baseline for the new organization/property tables.
-- Reads are limited to active organization members; inserts are limited to organization members with an active role.
-- No update or delete policies are added for organizations, portfolios, properties, or ownership records.
-- Invitation acceptance is the only permitted organization_members update.

BEGIN;

CREATE OR REPLACE FUNCTION public.can_access_organization(target_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        EXISTS (
            SELECT 1
            FROM public.organizations AS organization_row
            WHERE organization_row.id = target_organization_id
              AND organization_row.created_by = (SELECT auth.uid())
        )
        OR EXISTS (
            SELECT 1
            FROM public.organization_members AS membership
            WHERE membership.organization_id = target_organization_id
              AND membership.user_id = (SELECT auth.uid())
              AND membership.membership_status = 'active'
        );
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_organization(target_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        EXISTS (
            SELECT 1
            FROM public.organizations AS organization_row
            WHERE organization_row.id = target_organization_id
              AND organization_row.created_by = (SELECT auth.uid())
        )
        OR EXISTS (
            SELECT 1
            FROM public.organization_members AS membership
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
    SELECT
        EXISTS (
            SELECT 1
            FROM public.properties AS property_row
            WHERE property_row.id = target_property_id
              AND public.can_access_organization(property_row.organization_id)
        )
        OR EXISTS (
            SELECT 1
            FROM public.property_owners AS owner_row
            WHERE owner_row.property_id = target_property_id
              AND owner_row.ownership_status = 'active'
              AND public.can_access_organization(owner_row.organization_id)
        );
$function$;

REVOKE ALL ON FUNCTION public.can_access_organization(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_organization(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_access_property(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_organization(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_organization(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_property(uuid) TO authenticated;

-- Remove broad default grants, then grant only the operations backed by policies below.
REVOKE ALL ON TABLE
    public.organizations,
    public.organization_members,
    public.property_portfolios,
    public.properties,
    public.property_owners
FROM anon, authenticated;

GRANT SELECT, INSERT ON TABLE
    public.organizations,
    public.organization_members,
    public.property_portfolios,
    public.properties,
    public.property_owners
TO authenticated;

GRANT UPDATE (user_id, membership_status)
ON TABLE public.organization_members
TO authenticated;

-- Organizations: creators can see and submit their own organization for review.
DROP POLICY IF EXISTS organizations_select_accessible ON public.organizations;
CREATE POLICY organizations_select_accessible
ON public.organizations
FOR SELECT TO authenticated
USING (public.can_access_organization(id));

DROP POLICY IF EXISTS organizations_insert_own ON public.organizations;
CREATE POLICY organizations_insert_own
ON public.organizations
FOR INSERT TO authenticated
WITH CHECK (
    created_by = (SELECT auth.uid())
    AND approval_status IN ('draft', 'pending_review')
    AND reviewed_by IS NULL
    AND reviewed_at IS NULL
);

-- Memberships: active organization members can view the roster; invitees can view their own pending invite.
DROP POLICY IF EXISTS organization_members_select_accessible ON public.organization_members;
CREATE POLICY organization_members_select_accessible
ON public.organization_members
FOR SELECT TO authenticated
USING (
    public.can_access_organization(organization_id)
    OR (
        membership_status = 'pending_invitation'
        AND user_id IS NULL
        AND lower(invited_email) = lower((SELECT auth.jwt() ->> 'email'))
    )
);

DROP POLICY IF EXISTS organization_members_insert_representative_invite ON public.organization_members;
CREATE POLICY organization_members_insert_representative_invite
ON public.organization_members
FOR INSERT TO authenticated
WITH CHECK (
    public.can_manage_organization(organization_id)
    AND invited_by = (SELECT auth.uid())
    AND member_role = 'representative'
    AND membership_status = 'pending_invitation'
    AND user_id IS NULL
    AND invited_email IS NOT NULL
    AND approved_by IS NULL
    AND approved_at IS NULL
);

DROP POLICY IF EXISTS organization_members_accept_invitation ON public.organization_members;
CREATE POLICY organization_members_accept_invitation
ON public.organization_members
FOR UPDATE TO authenticated
USING (
    membership_status = 'pending_invitation'
    AND user_id IS NULL
    AND lower(invited_email) = lower((SELECT auth.jwt() ->> 'email'))
)
WITH CHECK (
    user_id = (SELECT auth.uid())
    AND membership_status = 'active'
    AND lower(invited_email) = lower((SELECT auth.jwt() ->> 'email'))
);

-- Portfolios and properties: organization members can read; active representatives can create.
DROP POLICY IF EXISTS property_portfolios_select_accessible ON public.property_portfolios;
CREATE POLICY property_portfolios_select_accessible
ON public.property_portfolios
FOR SELECT TO authenticated
USING (public.can_access_organization(organization_id));

DROP POLICY IF EXISTS property_portfolios_insert_managed ON public.property_portfolios;
CREATE POLICY property_portfolios_insert_managed
ON public.property_portfolios
FOR INSERT TO authenticated
WITH CHECK (
    public.can_manage_organization(organization_id)
    AND created_by = (SELECT auth.uid())
);

DROP POLICY IF EXISTS properties_select_accessible ON public.properties;
CREATE POLICY properties_select_accessible
ON public.properties
FOR SELECT TO authenticated
USING (public.can_access_property(id));

DROP POLICY IF EXISTS properties_insert_managed ON public.properties;
CREATE POLICY properties_insert_managed
ON public.properties
FOR INSERT TO authenticated
WITH CHECK (
    public.can_manage_organization(organization_id)
    AND created_by = (SELECT auth.uid())
    AND approval_status = 'draft'
    AND reviewed_by IS NULL
    AND reviewed_at IS NULL
);

-- Co-owners can see the ownership roster for a property they can access.
DROP POLICY IF EXISTS property_owners_select_accessible ON public.property_owners;
CREATE POLICY property_owners_select_accessible
ON public.property_owners
FOR SELECT TO authenticated
USING (public.can_access_property(property_id));

DROP POLICY IF EXISTS property_owners_insert_managed ON public.property_owners;
CREATE POLICY property_owners_insert_managed
ON public.property_owners
FOR INSERT TO authenticated
WITH CHECK (
    created_by = (SELECT auth.uid())
    AND public.can_manage_organization(organization_id)
    AND EXISTS (
        SELECT 1
        FROM public.properties AS property_row
        WHERE property_row.id = property_id
          AND public.can_manage_organization(property_row.organization_id)
    )
);

COMMIT;
-- Archived query SB_093_Create_Organization_Members
-- Already executed successfully in Supabase. Do not run again.

CREATE TABLE public.organization_members (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    user_id uuid REFERENCES public.profiles(id),
    invited_email text,
    member_role text NOT NULL CHECK (member_role IN ('owner', 'representative')),
    membership_status text NOT NULL DEFAULT 'pending_owner_approval' CHECK (
        membership_status IN ('pending_owner_approval', 'pending_invitation', 'active', 'revoked')
    ),
    invited_by uuid REFERENCES public.profiles(id),
    approved_by uuid REFERENCES public.profiles(id),
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (user_id IS NOT NULL OR invited_email IS NOT NULL),
    CHECK (member_role <> 'owner' OR user_id IS NOT NULL)
);

CREATE INDEX idx_org_members_organization
    ON public.organization_members(organization_id);

CREATE INDEX idx_org_members_user
    ON public.organization_members(user_id);

CREATE UNIQUE INDEX idx_org_members_unique_user
    ON public.organization_members(organization_id, user_id)
    WHERE user_id IS NOT NULL AND membership_status <> 'revoked';

CREATE UNIQUE INDEX idx_org_members_unique_email
    ON public.organization_members(organization_id, lower(invited_email))
    WHERE invited_email IS NOT NULL AND membership_status <> 'revoked';

ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
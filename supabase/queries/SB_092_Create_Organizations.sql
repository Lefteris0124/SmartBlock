-- Archived query SB_092_Create_Organizations
-- Already executed successfully in Supabase. Do not run again.

CREATE TABLE public.organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_type text NOT NULL CHECK (organization_type IN ('individual', 'company')),
    display_name text NOT NULL,
    legal_name text,
    country text NOT NULL DEFAULT 'Cyprus',
    approval_status text NOT NULL DEFAULT 'pending_review' CHECK (
        approval_status IN (
            'draft', 'pending_review', 'under_review', 'changes_required',
            'approved', 'rejected', 'suspended'
        )
    ),
    created_by uuid NOT NULL REFERENCES public.profiles(id),
    reviewed_by uuid REFERENCES public.profiles(id),
    reviewed_at timestamptz,
    review_notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_organizations_created_by
    ON public.organizations(created_by);

CREATE INDEX idx_organizations_approval_status
    ON public.organizations(approval_status);

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
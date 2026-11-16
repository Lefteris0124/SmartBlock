-- Archived query SB_095_Create_Properties
-- Already executed successfully in Supabase. Do not run again.

ALTER TABLE public.property_portfolios
    ADD CONSTRAINT uq_property_portfolios_id_organization
    UNIQUE (id, organization_id);

CREATE TABLE public.properties (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    portfolio_id uuid,
    apartment_id uuid UNIQUE REFERENCES public.apartments(id) ON DELETE RESTRICT,
    property_type text NOT NULL CHECK (
        property_type IN ('apartment', 'house', 'shop', 'office', 'warehouse', 'land', 'other')
    ),
    name text NOT NULL,
    address text,
    city text,
    country text NOT NULL DEFAULT 'Cyprus',
    management_model text NOT NULL DEFAULT 'self_service' CHECK (
        management_model IN ('managed', 'assisted', 'self_service')
    ),
    expense_approval_threshold numeric(12, 2) NOT NULL DEFAULT 0
        CHECK (expense_approval_threshold >= 0),
    approval_status text NOT NULL DEFAULT 'draft' CHECK (
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
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_property_portfolio_organization
        FOREIGN KEY (portfolio_id, organization_id)
        REFERENCES public.property_portfolios(id, organization_id),
    CONSTRAINT chk_property_location
        CHECK (
            (apartment_id IS NOT NULL AND property_type = 'apartment')
            OR (apartment_id IS NULL AND address IS NOT NULL)
        )
);

CREATE INDEX idx_properties_organization
    ON public.properties(organization_id);

CREATE INDEX idx_properties_portfolio
    ON public.properties(portfolio_id);

CREATE INDEX idx_properties_approval_status
    ON public.properties(approval_status);

ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
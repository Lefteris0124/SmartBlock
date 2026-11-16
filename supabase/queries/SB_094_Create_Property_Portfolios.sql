-- Archived query SB_094_Create_Property_Portfolios
-- Already executed successfully in Supabase. Do not run again.

CREATE TABLE public.property_portfolios (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    name text NOT NULL,
    description text,
    created_by uuid NOT NULL REFERENCES public.profiles(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_property_portfolios_organization
    ON public.property_portfolios(organization_id);

CREATE UNIQUE INDEX idx_property_portfolios_unique_name
    ON public.property_portfolios(organization_id, lower(name));

ALTER TABLE public.property_portfolios ENABLE ROW LEVEL SECURITY;
-- Archived query SB_096_Create_Property_Owners
-- Already executed successfully in Supabase. Do not run again.

CREATE TABLE public.property_owners (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    ownership_percentage numeric(5, 2) NOT NULL
        CHECK (ownership_percentage > 0 AND ownership_percentage <= 100),
    is_primary_representative boolean NOT NULL DEFAULT false,
    ownership_status text NOT NULL DEFAULT 'active' CHECK (
        ownership_status IN ('active', 'transferred', 'inactive')
    ),
    start_date date NOT NULL DEFAULT CURRENT_DATE,
    end_date date,
    created_by uuid NOT NULL REFERENCES public.profiles(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_property_owner_dates
        CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX idx_property_owners_property
    ON public.property_owners(property_id);

CREATE INDEX idx_property_owners_organization
    ON public.property_owners(organization_id);

CREATE UNIQUE INDEX idx_property_one_primary_representative
    ON public.property_owners(property_id)
    WHERE is_primary_representative = true AND ownership_status = 'active';

CREATE OR REPLACE FUNCTION public.check_property_ownership_percentage()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    total_percentage numeric;
BEGIN
    SELECT COALESCE(SUM(ownership_percentage), 0)
    INTO total_percentage
    FROM public.property_owners
    WHERE property_id = NEW.property_id
      AND ownership_status = 'active'
      AND id <> NEW.id;

    IF NEW.ownership_status = 'active' THEN
        total_percentage := total_percentage + NEW.ownership_percentage;
    END IF;

    IF total_percentage > 100 THEN
        RAISE EXCEPTION 'Total active ownership percentage cannot exceed 100%%';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_property_ownership_percentage
BEFORE INSERT OR UPDATE ON public.property_owners
FOR EACH ROW
EXECUTE FUNCTION public.check_property_ownership_percentage();

ALTER TABLE public.property_owners ENABLE ROW LEVEL SECURITY;
-- SB_098_Fix_Property_Ownership_Integrity
-- Adds a property/organization integrity constraint and serializes ownership
-- percentage checks per property. Does not change existing owner rows.

BEGIN;

-- Refuse to apply if existing rows violate the constraints this script adds.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.property_owners AS po
        JOIN public.properties AS p ON p.id = po.property_id
        WHERE po.organization_id IS DISTINCT FROM p.organization_id
    ) THEN
        RAISE EXCEPTION 'SB_098 stopped: property_owners contains property/organization mismatches.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.property_owners
        WHERE ownership_status = 'active'
        GROUP BY property_id
        HAVING SUM(ownership_percentage) > 100
    ) THEN
        RAISE EXCEPTION 'SB_098 stopped: at least one property has active ownership above 100%%.';
    END IF;
END;
$$;

-- PostgreSQL requires a unique key matching the composite foreign key target.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.properties'::regclass
          AND conname = 'uq_properties_id_organization'
    ) THEN
        ALTER TABLE public.properties
            ADD CONSTRAINT uq_properties_id_organization
            UNIQUE (id, organization_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.property_owners'::regclass
          AND conname = 'fk_property_owners_property_organization'
    ) THEN
        ALTER TABLE public.property_owners
            ADD CONSTRAINT fk_property_owners_property_organization
            FOREIGN KEY (property_id, organization_id)
            REFERENCES public.properties (id, organization_id)
            ON DELETE RESTRICT;
    END IF;
END;
$$;

-- The existing trigger calls this function before INSERT and UPDATE.
-- Advisory locks serialize changes for the same property before the sum is read.
CREATE OR REPLACE FUNCTION public.check_property_ownership_percentage()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
    total_percentage numeric;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.property_id IS DISTINCT FROM OLD.property_id THEN
        -- Lock both properties in a stable order to avoid deadlocks on transfers.
        IF NEW.property_id < OLD.property_id THEN
            PERFORM pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended(NEW.property_id::text, 0)
            );
            PERFORM pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended(OLD.property_id::text, 0)
            );
        ELSE
            PERFORM pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended(OLD.property_id::text, 0)
            );
            PERFORM pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended(NEW.property_id::text, 0)
            );
        END IF;
    ELSE
        PERFORM pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(NEW.property_id::text, 0)
        );
    END IF;

    SELECT COALESCE(SUM(ownership_percentage), 0)
    INTO total_percentage
    FROM public.property_owners
    WHERE property_id = NEW.property_id
      AND ownership_status = 'active'
      AND id IS DISTINCT FROM NEW.id;

    IF NEW.ownership_status = 'active' THEN
        total_percentage := total_percentage + NEW.ownership_percentage;
    END IF;

    IF total_percentage > 100 THEN
        RAISE EXCEPTION 'Total active ownership percentage cannot exceed 100%%';
    END IF;

    RETURN NEW;
END;
$$;

COMMIT;
-- SB_099_Allow_CoOwner_Organizations
-- Keep a property's portfolio organization distinct from each co-owner organization.
-- Removes only the over-restrictive composite FK and its supporting unique key.
-- The original single-column FKs remain in place.

BEGIN;

ALTER TABLE public.property_owners
    DROP CONSTRAINT IF EXISTS fk_property_owners_property_organization;

ALTER TABLE public.properties
    DROP CONSTRAINT IF EXISTS uq_properties_id_organization;

COMMIT;
-- SB_102_Enforce_Active_Owner_Uniqueness
-- A property may have only one active ownership row per organization.
-- Transferred and inactive historical rows remain available for audit.

CREATE UNIQUE INDEX IF NOT EXISTS idx_property_owners_one_active_organization
    ON public.property_owners (property_id, organization_id)
    WHERE ownership_status = 'active';

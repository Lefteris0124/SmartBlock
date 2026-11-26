CREATE INDEX IF NOT EXISTS lease_tenant_requests_contract_created_idx
  ON public.lease_tenant_requests(contract_id,created_at DESC);
CREATE INDEX IF NOT EXISTS lease_tenant_requests_property_created_idx
  ON public.lease_tenant_requests(property_id,created_at DESC);
CREATE INDEX IF NOT EXISTS lease_tenant_requests_reviewed_by_idx
  ON public.lease_tenant_requests(reviewed_by);
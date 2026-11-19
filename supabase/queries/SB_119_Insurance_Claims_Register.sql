-- Add a manager-only insurance-claim register tied to the building's policy.
ALTER TABLE public.property_insurance_policies
  ADD CONSTRAINT property_insurance_policies_id_property_key
  UNIQUE (id, property_id);

CREATE TABLE IF NOT EXISTS public.property_insurance_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL,
  policy_id uuid NOT NULL,
  claim_reference text NOT NULL DEFAULT '',
  incident_date date NOT NULL,
  reported_on date NOT NULL DEFAULT current_date,
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 2 AND 2000),
  claimed_amount numeric(12,2) CHECK (claimed_amount >= 0),
  approved_amount numeric(12,2) CHECK (approved_amount >= 0),
  status text NOT NULL DEFAULT 'reported'
    CHECK (status IN ('reported','under_review','accepted','rejected','paid','closed')),
  document_path text,
  notes text NOT NULL DEFAULT '',
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT property_insurance_claims_policy_property_fkey
    FOREIGN KEY (policy_id, property_id)
    REFERENCES public.property_insurance_policies(id, property_id)
    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS property_insurance_claims_property_status_idx
  ON public.property_insurance_claims(property_id, status, reported_on DESC);

ALTER TABLE public.property_insurance_claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS property_insurance_claims_select ON public.property_insurance_claims;
CREATE POLICY property_insurance_claims_select
  ON public.property_insurance_claims FOR SELECT TO authenticated
  USING (public.can_manage_property(property_id));
DROP POLICY IF EXISTS property_insurance_claims_insert ON public.property_insurance_claims;
CREATE POLICY property_insurance_claims_insert
  ON public.property_insurance_claims FOR INSERT TO authenticated
  WITH CHECK (created_by = (SELECT auth.uid()) AND public.can_manage_property(property_id));
DROP POLICY IF EXISTS property_insurance_claims_update ON public.property_insurance_claims;
CREATE POLICY property_insurance_claims_update
  ON public.property_insurance_claims FOR UPDATE TO authenticated
  USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id));
DROP POLICY IF EXISTS property_insurance_claims_delete ON public.property_insurance_claims;
CREATE POLICY property_insurance_claims_delete
  ON public.property_insurance_claims FOR DELETE TO authenticated
  USING (public.can_manage_property(property_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.property_insurance_claims TO authenticated;

DROP TRIGGER IF EXISTS property_insurance_claims_audit ON public.property_insurance_claims;
CREATE TRIGGER property_insurance_claims_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.property_insurance_claims
  FOR EACH ROW EXECUTE FUNCTION public.capture_property_management_audit();

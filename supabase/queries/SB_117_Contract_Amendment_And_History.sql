-- Keep one active management contract per property and retain reviewed amendments.
ALTER TABLE public.property_management_contracts
  ADD CONSTRAINT property_management_contracts_id_property_key
  UNIQUE (id, property_id);

CREATE UNIQUE INDEX IF NOT EXISTS property_management_contracts_one_active_per_property
  ON public.property_management_contracts(property_id)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.property_management_contract_amendments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL,
  contract_id uuid NOT NULL,
  amendment_reference text NOT NULL DEFAULT '',
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 200),
  effective_on date NOT NULL,
  changes_summary text NOT NULL DEFAULT '',
  monthly_fee_new numeric(12,2) CHECK (monthly_fee_new >= 0),
  vat_rate_new numeric(5,2) CHECK (vat_rate_new BETWEEN 0 AND 100),
  source_document_path text,
  approval_status text NOT NULL DEFAULT 'pending'
    CHECK (approval_status IN ('pending','approved','rejected')),
  decided_by uuid REFERENCES auth.users(id),
  decided_at timestamptz,
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT property_management_contract_amendments_contract_property_fkey
    FOREIGN KEY (contract_id, property_id)
    REFERENCES public.property_management_contracts(id, property_id)
    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS property_management_contract_amendments_property_date_idx
  ON public.property_management_contract_amendments(property_id, effective_on DESC);

ALTER TABLE public.property_management_contract_amendments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS property_management_contract_amendments_select
  ON public.property_management_contract_amendments;
CREATE POLICY property_management_contract_amendments_select
  ON public.property_management_contract_amendments
  FOR SELECT TO authenticated
  USING (public.can_access_property(property_id));

DROP POLICY IF EXISTS property_management_contract_amendments_insert
  ON public.property_management_contract_amendments;
CREATE POLICY property_management_contract_amendments_insert
  ON public.property_management_contract_amendments
  FOR INSERT TO authenticated
  WITH CHECK (created_by = (SELECT auth.uid()) AND public.can_manage_property(property_id));

DROP POLICY IF EXISTS property_management_contract_amendments_update
  ON public.property_management_contract_amendments;
CREATE POLICY property_management_contract_amendments_update
  ON public.property_management_contract_amendments
  FOR UPDATE TO authenticated
  USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id));

DROP POLICY IF EXISTS property_management_contract_amendments_delete
  ON public.property_management_contract_amendments;
CREATE POLICY property_management_contract_amendments_delete
  ON public.property_management_contract_amendments
  FOR DELETE TO authenticated
  USING (public.can_manage_property(property_id));

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.property_management_contract_amendments TO authenticated;

DROP TRIGGER IF EXISTS property_management_contract_amendments_audit
  ON public.property_management_contract_amendments;
CREATE TRIGGER property_management_contract_amendments_audit
  AFTER INSERT OR UPDATE OR DELETE
  ON public.property_management_contract_amendments
  FOR EACH ROW EXECUTE FUNCTION public.capture_property_management_audit();

CREATE OR REPLACE FUNCTION public.review_property_contract_amendment(
  p_amendment_id uuid,
  p_approval_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_property_id uuid;
  v_contract_id uuid;
  v_status text;
  v_monthly_fee numeric;
  v_vat_rate numeric;
BEGIN
  IF p_approval_status NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'An amendment can only be approved or rejected.' USING ERRCODE = '22023';
  END IF;

  SELECT a.property_id, a.contract_id, a.approval_status,
         a.monthly_fee_new, a.vat_rate_new
    INTO v_property_id, v_contract_id, v_status, v_monthly_fee, v_vat_rate
  FROM public.property_management_contract_amendments AS a
  WHERE a.id = p_amendment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Amendment not found.' USING ERRCODE = 'P0002';
  END IF;

  IF NOT COALESCE(public.can_manage_property(v_property_id), false) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending amendment can be reviewed.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.property_management_contract_amendments
  SET approval_status = p_approval_status,
      decided_by = auth.uid(),
      decided_at = now()
  WHERE id = p_amendment_id;

  IF p_approval_status = 'approved' THEN
    UPDATE public.property_management_contracts
    SET monthly_fee = COALESCE(v_monthly_fee, monthly_fee),
        vat_rate = COALESCE(v_vat_rate, vat_rate),
        updated_at = now()
    WHERE id = v_contract_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.review_property_contract_amendment(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_property_contract_amendment(uuid, text)
  TO authenticated;

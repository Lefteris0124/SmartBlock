-- Turn the service catalogue into a request -> quote -> approval -> work -> expense flow.
CREATE TABLE IF NOT EXISTS public.property_service_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  service_id uuid REFERENCES public.property_management_services(id) ON DELETE SET NULL,
  requester_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 200),
  description text NOT NULL DEFAULT '',
  supplier text NOT NULL DEFAULT '',
  quote_amount numeric(12,2) CHECK (quote_amount > 0),
  quote_notes text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested','quoted','approved','rejected','in_progress','completed')),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  expense_id uuid REFERENCES public.property_operating_expenses(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS property_service_requests_property_status_idx
  ON public.property_service_requests(property_id, status, created_at DESC);

ALTER TABLE public.property_service_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS property_service_requests_select ON public.property_service_requests;
CREATE POLICY property_service_requests_select
  ON public.property_service_requests FOR SELECT TO authenticated
  USING (public.can_access_property(property_id));
DROP POLICY IF EXISTS property_service_requests_insert ON public.property_service_requests;
CREATE POLICY property_service_requests_insert
  ON public.property_service_requests FOR INSERT TO authenticated
  WITH CHECK (requester_id = (SELECT auth.uid()) AND public.can_access_property(property_id));
DROP POLICY IF EXISTS property_service_requests_update ON public.property_service_requests;
CREATE POLICY property_service_requests_update
  ON public.property_service_requests FOR UPDATE TO authenticated
  USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id));
DROP POLICY IF EXISTS property_service_requests_delete ON public.property_service_requests;
CREATE POLICY property_service_requests_delete
  ON public.property_service_requests FOR DELETE TO authenticated
  USING (public.can_manage_property(property_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.property_service_requests TO authenticated;

DROP TRIGGER IF EXISTS property_service_requests_audit ON public.property_service_requests;
CREATE TRIGGER property_service_requests_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.property_service_requests
  FOR EACH ROW EXECUTE FUNCTION public.capture_property_management_audit();

CREATE OR REPLACE FUNCTION public.transition_property_service_request(
  p_request_id uuid,
  p_next_status text,
  p_quote_amount numeric DEFAULT NULL,
  p_quote_notes text DEFAULT NULL,
  p_supplier text DEFAULT NULL,
  p_confirm_below_reserve boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_property_id uuid;
  v_service_id uuid;
  v_title text;
  v_description text;
  v_supplier text;
  v_quote numeric;
  v_status text;
  v_expense_id uuid;
  v_opening_balance numeric := 0;
  v_minimum_reserve numeric := 0;
  v_require_approval boolean := false;
  v_received numeric := 0;
  v_paid_expenses numeric := 0;
  v_other_expenses numeric := 0;
  v_other_services numeric := 0;
  v_projected numeric := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
  END IF;

  SELECT r.property_id, r.service_id, r.title, r.description, r.supplier,
         r.quote_amount, r.status, r.expense_id
    INTO v_property_id, v_service_id, v_title, v_description, v_supplier,
         v_quote, v_status, v_expense_id
  FROM public.property_service_requests AS r
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service request not found.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT COALESCE(public.can_manage_property(v_property_id), false) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
  END IF;

  IF v_status = 'requested' AND p_next_status = 'quoted' THEN
    IF p_quote_amount IS NULL OR p_quote_amount <= 0 THEN
      RAISE EXCEPTION 'Enter a positive quote amount.' USING ERRCODE = '22023';
    END IF;
    UPDATE public.property_service_requests
    SET status = 'quoted',
        quote_amount = p_quote_amount,
        quote_notes = COALESCE(p_quote_notes, ''),
        supplier = COALESCE(p_supplier, ''),
        updated_at = now()
    WHERE id = p_request_id;
    RETURN jsonb_build_object('updated', true, 'status', 'quoted');
  END IF;

  IF v_status = 'quoted' AND p_next_status IN ('approved','rejected') THEN
    IF p_next_status = 'approved' THEN
      IF v_quote IS NULL OR v_quote <= 0 THEN
        RAISE EXCEPTION 'A positive quote is required before approval.' USING ERRCODE = '22023';
      END IF;

      PERFORM pg_advisory_xact_lock(hashtextextended(v_property_id::text, 0));

      SELECT COALESCE(s.opening_balance, 0),
             COALESCE(s.minimum_operating_reserve, 0),
             COALESCE(s.require_approval_below_reserve, false)
        INTO v_opening_balance, v_minimum_reserve, v_require_approval
      FROM public.property_finance_settings AS s
      WHERE s.property_id = v_property_id
      FOR UPDATE;
      IF NOT FOUND THEN
        v_opening_balance := 0;
        v_minimum_reserve := 0;
        v_require_approval := false;
      END IF;

      SELECT COALESCE(SUM(e.amount_paid), 0)
        INTO v_received
      FROM public.property_charge_entries AS e
      JOIN public.property_charge_runs AS run ON run.id = e.run_id
      WHERE run.property_id = v_property_id;

      SELECT COALESCE(SUM(e.amount), 0)
        INTO v_paid_expenses
      FROM public.property_operating_expenses AS e
      WHERE e.property_id = v_property_id AND e.status = 'paid';

      SELECT COALESCE(SUM(e.amount), 0)
        INTO v_other_expenses
      FROM public.property_operating_expenses AS e
      WHERE e.property_id = v_property_id
        AND e.status IN ('approved','awaiting_approval');

      SELECT COALESCE(SUM(r.quote_amount), 0)
        INTO v_other_services
      FROM public.property_service_requests AS r
      WHERE r.property_id = v_property_id
        AND r.status IN ('approved','in_progress');

      v_projected := v_opening_balance + v_received - v_paid_expenses
        - v_other_expenses - v_other_services - v_quote;

      IF v_require_approval
         AND v_projected < v_minimum_reserve
         AND NOT COALESCE(p_confirm_below_reserve, false) THEN
        RETURN jsonb_build_object(
          'updated', false,
          'needs_confirmation', true,
          'projected_balance', v_projected,
          'minimum_reserve', v_minimum_reserve
        );
      END IF;
    END IF;

    UPDATE public.property_service_requests
    SET status = p_next_status,
        approved_by = CASE WHEN p_next_status = 'approved' THEN auth.uid() ELSE NULL END,
        approved_at = CASE WHEN p_next_status = 'approved' THEN now() ELSE NULL END,
        updated_at = now()
    WHERE id = p_request_id;
    RETURN jsonb_build_object('updated', true, 'status', p_next_status);
  END IF;

  IF v_status = 'approved' AND p_next_status = 'in_progress' THEN
    UPDATE public.property_service_requests
    SET status = 'in_progress', updated_at = now()
    WHERE id = p_request_id;
    RETURN jsonb_build_object('updated', true, 'status', 'in_progress');
  END IF;

  IF v_status = 'in_progress' AND p_next_status = 'completed' THEN
    INSERT INTO public.property_operating_expenses (
      property_id, service_id, category, description, supplier, amount,
      currency, expense_date, status, notes
    ) VALUES (
      v_property_id, v_service_id, 'service',
      v_title || CASE WHEN length(btrim(v_description)) > 0 THEN ' — ' || v_description ELSE '' END,
      NULLIF(v_supplier, ''), v_quote, 'EUR', current_date, 'awaiting_approval',
      'Created from completed service request ' || p_request_id::text
    ) RETURNING id INTO v_expense_id;

    UPDATE public.property_service_requests
    SET status = 'completed', expense_id = v_expense_id, updated_at = now()
    WHERE id = p_request_id;
    RETURN jsonb_build_object('updated', true, 'status', 'completed', 'expense_id', v_expense_id);
  END IF;

  RAISE EXCEPTION 'Invalid service request transition: % to %.', v_status, p_next_status
    USING ERRCODE = '22023';
END;
$$;

REVOKE ALL ON FUNCTION public.transition_property_service_request(uuid, text, numeric, text, text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_property_service_request(uuid, text, numeric, text, text, boolean)
  TO authenticated;

-- Keep the reserve check current as approved service quotes become commitments.
CREATE OR REPLACE FUNCTION public.mark_property_expense_paid(
  p_expense_id uuid,
  p_confirm_below_reserve boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_property_id uuid;
  v_amount numeric;
  v_status text;
  v_opening_balance numeric := 0;
  v_minimum_reserve numeric := 0;
  v_require_approval boolean := false;
  v_received numeric := 0;
  v_paid_expenses numeric := 0;
  v_other_commitments numeric := 0;
  v_service_commitments numeric := 0;
  v_balance numeric := 0;
  v_projected_balance numeric := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
  END IF;

  SELECT e.property_id, e.amount, e.status
    INTO v_property_id, v_amount, v_status
  FROM public.property_operating_expenses AS e
  WHERE e.id = p_expense_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Expense not found.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT COALESCE(public.can_manage_property(v_property_id), false) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved expense can be paid.' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_property_id::text, 0));
  SELECT COALESCE(s.opening_balance, 0),
         COALESCE(s.minimum_operating_reserve, 0),
         COALESCE(s.require_approval_below_reserve, false)
    INTO v_opening_balance, v_minimum_reserve, v_require_approval
  FROM public.property_finance_settings AS s
  WHERE s.property_id = v_property_id
  FOR UPDATE;
  IF NOT FOUND THEN
    v_opening_balance := 0;
    v_minimum_reserve := 0;
    v_require_approval := false;
  END IF;

  SELECT COALESCE(SUM(e.amount_paid), 0)
    INTO v_received
  FROM public.property_charge_entries AS e
  JOIN public.property_charge_runs AS r ON r.id = e.run_id
  WHERE r.property_id = v_property_id;
  SELECT COALESCE(SUM(e.amount), 0)
    INTO v_paid_expenses
  FROM public.property_operating_expenses AS e
  WHERE e.property_id = v_property_id AND e.status = 'paid';
  SELECT COALESCE(SUM(e.amount), 0)
    INTO v_other_commitments
  FROM public.property_operating_expenses AS e
  WHERE e.property_id = v_property_id
    AND e.status IN ('approved','awaiting_approval')
    AND e.id <> p_expense_id;
  SELECT COALESCE(SUM(r.quote_amount), 0)
    INTO v_service_commitments
  FROM public.property_service_requests AS r
  WHERE r.property_id = v_property_id
    AND r.status IN ('approved','in_progress');

  v_balance := v_opening_balance + v_received - v_paid_expenses;
  v_projected_balance := v_balance - v_amount - v_other_commitments - v_service_commitments;

  IF v_require_approval
     AND v_projected_balance < v_minimum_reserve
     AND NOT COALESCE(p_confirm_below_reserve, false) THEN
    RETURN jsonb_build_object(
      'paid', false,
      'needs_confirmation', true,
      'projected_balance', v_projected_balance,
      'minimum_reserve', v_minimum_reserve
    );
  END IF;

  UPDATE public.property_operating_expenses
  SET status = 'paid', paid_at = now(), updated_at = now()
  WHERE id = p_expense_id;

  RETURN jsonb_build_object(
    'paid', true,
    'needs_confirmation', false,
    'projected_balance', v_projected_balance,
    'minimum_reserve', v_minimum_reserve
  );
END;
$$;

REVOKE ALL ON FUNCTION public.mark_property_expense_paid(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_property_expense_paid(uuid, boolean) TO authenticated;

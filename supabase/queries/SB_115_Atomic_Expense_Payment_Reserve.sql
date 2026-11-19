-- Record an operating-expense payment atomically and enforce the configured
-- cash-reserve confirmation rule on the server.
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

  -- Serialize balance checks for expenses belonging to the same property.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_property_id::text, 0));

  SELECT
    COALESCE(s.opening_balance, 0),
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
  WHERE e.property_id = v_property_id
    AND e.status = 'paid';

  SELECT COALESCE(SUM(e.amount), 0)
    INTO v_other_commitments
  FROM public.property_operating_expenses AS e
  WHERE e.property_id = v_property_id
    AND e.status = 'approved'
    AND e.id <> p_expense_id;

  v_balance := v_opening_balance + v_received - v_paid_expenses;
  v_projected_balance := v_balance - v_amount - v_other_commitments;

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
  SET status = 'paid',
      paid_at = now(),
      updated_at = now()
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

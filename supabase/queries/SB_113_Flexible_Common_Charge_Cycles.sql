-- Allow each common-charge run to declare its agreed billing period.
ALTER TABLE public.property_charge_runs
  ADD COLUMN IF NOT EXISTS billing_cycle text NOT NULL DEFAULT 'monthly';
ALTER TABLE public.property_charge_runs
  DROP CONSTRAINT IF EXISTS property_charge_runs_billing_cycle_check;
ALTER TABLE public.property_charge_runs
  ADD CONSTRAINT property_charge_runs_billing_cycle_check
  CHECK (billing_cycle IN ('monthly','quarterly','semiannual','annual','custom'));

DROP FUNCTION IF EXISTS public.create_property_charge_run(uuid,text,text,numeric,date,text);

CREATE FUNCTION public.create_property_charge_run(
  p_property_id uuid,
  p_period_label text,
  p_description text,
  p_total_amount numeric,
  p_due_date date,
  p_currency text DEFAULT 'EUR',
  p_billing_cycle text DEFAULT 'monthly'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
  new_run_id uuid;
  owner_row record;
  owner_count integer;
  index_row integer := 0;
  remaining_amount numeric(12,2);
  allocation numeric(12,2);
  active_share_total numeric(7,2);
BEGIN
  IF current_user_id IS NULL OR NOT public.can_manage_property(p_property_id) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
  END IF;
  IF p_total_amount <= 0 OR length(btrim(p_period_label)) = 0 THEN
    RAISE EXCEPTION 'Enter a period and a positive amount.';
  END IF;
  IF p_billing_cycle IS NULL OR p_billing_cycle NOT IN ('monthly','quarterly','semiannual','annual','custom') THEN
    RAISE EXCEPTION 'Invalid common-charge billing cycle.';
  END IF;

  SELECT count(*), COALESCE(sum(ownership_percentage), 0)
  INTO owner_count, active_share_total
  FROM public.property_owners
  WHERE property_id = p_property_id AND ownership_status = 'active';
  IF owner_count = 0 OR active_share_total <> 100 THEN
    RAISE EXCEPTION 'Active ownership shares must total 100%% before common charges are created.';
  END IF;

  INSERT INTO public.property_charge_runs (
    property_id, period_label, description, total_amount, currency,
    due_date, created_by, billing_cycle
  ) VALUES (
    p_property_id, btrim(p_period_label), NULLIF(btrim(p_description), ''),
    p_total_amount, upper(p_currency), p_due_date, current_user_id, p_billing_cycle
  ) RETURNING id INTO new_run_id;

  remaining_amount := round(p_total_amount, 2);
  FOR owner_row IN
    SELECT po.id, po.ownership_percentage,
      row_number() OVER (ORDER BY po.created_at, po.id) AS row_number
    FROM public.property_owners AS po
    WHERE po.property_id = p_property_id AND po.ownership_status = 'active'
    ORDER BY po.created_at, po.id
  LOOP
    index_row := index_row + 1;
    IF index_row = owner_count THEN
      allocation := remaining_amount;
    ELSE
      allocation := floor(p_total_amount * owner_row.ownership_percentage) / 100;
      remaining_amount := remaining_amount - allocation;
    END IF;
    INSERT INTO public.property_charge_entries (run_id, property_owner_id, amount_due)
    VALUES (new_run_id, owner_row.id, allocation);
  END LOOP;
  RETURN new_run_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_property_charge_run(uuid,text,text,numeric,date,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_property_charge_run(uuid,text,text,numeric,date,text,text) TO authenticated;

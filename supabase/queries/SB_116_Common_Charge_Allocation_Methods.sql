-- Allow each common-charge run to use declared ownership shares, floor area,
-- or apartment counts for allocating its total across active owners.
ALTER TABLE public.property_charge_runs
  ADD COLUMN IF NOT EXISTS allocation_method text NOT NULL DEFAULT 'ownership_share';

ALTER TABLE public.property_charge_runs
  DROP CONSTRAINT IF EXISTS property_charge_runs_allocation_method_check;

ALTER TABLE public.property_charge_runs
  ADD CONSTRAINT property_charge_runs_allocation_method_check
  CHECK (allocation_method IN ('ownership_share', 'floor_area', 'per_apartment'));

DROP FUNCTION IF EXISTS public.create_property_charge_run(
  uuid, text, text, numeric, date, text, text
);

CREATE FUNCTION public.create_property_charge_run(
  p_property_id uuid,
  p_period_label text,
  p_description text,
  p_total_amount numeric,
  p_due_date date,
  p_currency text DEFAULT 'EUR',
  p_billing_cycle text DEFAULT 'monthly',
  p_allocation_method text DEFAULT 'ownership_share'
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
  invalid_basis_count integer;
  index_row integer := 0;
  remaining_amount numeric(12,2);
  allocation numeric(12,2);
  allocation_basis numeric;
  allocation_total numeric;
  active_share_total numeric;
BEGIN
  IF current_user_id IS NULL OR NOT public.can_manage_property(p_property_id) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
  END IF;

  IF p_total_amount <= 0 OR length(btrim(p_period_label)) = 0 THEN
    RAISE EXCEPTION 'Enter a period and a positive amount.';
  END IF;

  IF p_billing_cycle IS NULL
     OR p_billing_cycle NOT IN ('monthly','quarterly','semiannual','annual','custom') THEN
    RAISE EXCEPTION 'Invalid common-charge billing cycle.';
  END IF;

  IF p_allocation_method IS NULL
     OR p_allocation_method NOT IN ('ownership_share','floor_area','per_apartment') THEN
    RAISE EXCEPTION 'Invalid common-charge allocation method.';
  END IF;

  SELECT
    count(*),
    COALESCE(sum(po.ownership_percentage), 0),
    COALESCE(sum(
      CASE p_allocation_method
        WHEN 'ownership_share' THEN po.ownership_percentage::numeric
        WHEN 'floor_area' THEN po.area_sqm
        ELSE po.apartment_count::numeric
      END
    ), 0),
    count(*) FILTER (
      WHERE CASE p_allocation_method
        WHEN 'floor_area' THEN po.area_sqm IS NULL OR po.area_sqm <= 0
        WHEN 'per_apartment' THEN po.apartment_count IS NULL OR po.apartment_count <= 0
        ELSE false
      END
    )
  INTO owner_count, active_share_total, allocation_total, invalid_basis_count
  FROM public.property_owners AS po
  WHERE po.property_id = p_property_id
    AND po.ownership_status = 'active';

  IF owner_count = 0 THEN
    RAISE EXCEPTION 'Add active property owners before creating common charges.';
  END IF;

  IF p_allocation_method = 'ownership_share' AND active_share_total <> 100 THEN
    RAISE EXCEPTION 'Active ownership shares must total 100%% before using ownership-share allocation.';
  END IF;

  IF invalid_basis_count > 0 OR allocation_total <= 0 THEN
    RAISE EXCEPTION 'Every active owner must have a positive value for the selected allocation method.';
  END IF;

  INSERT INTO public.property_charge_runs (
    property_id, period_label, description, total_amount, currency,
    due_date, created_by, billing_cycle, allocation_method
  ) VALUES (
    p_property_id, btrim(p_period_label), NULLIF(btrim(p_description), ''),
    p_total_amount, upper(p_currency), p_due_date, current_user_id,
    p_billing_cycle, p_allocation_method
  ) RETURNING id INTO new_run_id;

  remaining_amount := round(p_total_amount, 2);
  FOR owner_row IN
    SELECT
      po.id,
      CASE p_allocation_method
        WHEN 'ownership_share' THEN po.ownership_percentage::numeric
        WHEN 'floor_area' THEN po.area_sqm
        ELSE po.apartment_count::numeric
      END AS allocation_basis
    FROM public.property_owners AS po
    WHERE po.property_id = p_property_id
      AND po.ownership_status = 'active'
    ORDER BY po.created_at, po.id
  LOOP
    index_row := index_row + 1;
    IF index_row = owner_count THEN
      allocation := remaining_amount;
    ELSE
      allocation := floor(
        (round(p_total_amount, 2) * owner_row.allocation_basis / allocation_total) * 100
      ) / 100;
      remaining_amount := remaining_amount - allocation;
    END IF;

    INSERT INTO public.property_charge_entries (run_id, property_owner_id, amount_due)
    VALUES (new_run_id, owner_row.id, allocation);
  END LOOP;

  RETURN new_run_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_property_charge_run(
  uuid, text, text, numeric, date, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_property_charge_run(
  uuid, text, text, numeric, date, text, text, text
) TO authenticated;

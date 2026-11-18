BEGIN;

CREATE TABLE IF NOT EXISTS public.property_payment_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    charge_entry_id uuid REFERENCES public.property_charge_entries(id) ON DELETE CASCADE,
    rent_installment_id uuid REFERENCES public.property_rent_installments(id) ON DELETE CASCADE,
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    payment_method text NOT NULL CHECK (payment_method IN ('cash','bank_transfer','card','cheque','other')),
    reference text,
    notes text,
    paid_at timestamptz NOT NULL DEFAULT now(),
    recorded_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT property_payment_records_one_target CHECK (
        (charge_entry_id IS NOT NULL)::integer + (rent_installment_id IS NOT NULL)::integer = 1
    )
);

CREATE INDEX IF NOT EXISTS property_payment_records_charge_idx
    ON public.property_payment_records(charge_entry_id, paid_at DESC);
CREATE INDEX IF NOT EXISTS property_payment_records_rent_idx
    ON public.property_payment_records(rent_installment_id, paid_at DESC);

ALTER TABLE public.property_payment_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS property_payment_records_read ON public.property_payment_records;
CREATE POLICY property_payment_records_read ON public.property_payment_records
    FOR SELECT TO authenticated
    USING (public.can_manage_property(property_id) OR public.is_smartblock_admin());
REVOKE ALL ON public.property_payment_records FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.property_payment_records TO authenticated;

DROP FUNCTION IF EXISTS public.record_property_charge_payment(uuid, numeric);
DROP FUNCTION IF EXISTS public.record_property_rent_payment(uuid, numeric);

CREATE OR REPLACE FUNCTION public.record_property_charge_payment(
    p_entry_id uuid,
    p_amount numeric,
    p_method text,
    p_reference text DEFAULT NULL,
    p_notes text DEFAULT NULL,
    p_paid_at timestamptz DEFAULT now()
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    entry_row public.property_charge_entries%ROWTYPE;
    target_property_id uuid;
    new_amount numeric(12,2);
    payment_id uuid;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Payment must be positive.'; END IF;
    IF p_method NOT IN ('cash','bank_transfer','card','cheque','other') THEN RAISE EXCEPTION 'Invalid payment method.'; END IF;
    SELECT run.property_id INTO target_property_id
    FROM public.property_charge_entries AS entry
    JOIN public.property_charge_runs AS run ON run.id = entry.run_id
    WHERE entry.id = p_entry_id;
    IF target_property_id IS NULL OR NOT public.can_manage_property(target_property_id) THEN
        RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO entry_row FROM public.property_charge_entries WHERE id = p_entry_id FOR UPDATE;
    new_amount := entry_row.amount_paid + p_amount;
    IF new_amount > entry_row.amount_due THEN RAISE EXCEPTION 'Payment exceeds the outstanding balance.'; END IF;
    INSERT INTO public.property_payment_records(property_id, charge_entry_id, amount, payment_method, reference, notes, paid_at, recorded_by)
    VALUES (target_property_id, p_entry_id, p_amount, p_method, NULLIF(btrim(p_reference),''), NULLIF(btrim(p_notes),''), COALESCE(p_paid_at,now()), auth.uid())
    RETURNING id INTO payment_id;
    UPDATE public.property_charge_entries
    SET amount_paid = new_amount,
        status = CASE WHEN new_amount = amount_due THEN 'paid' WHEN new_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        updated_at = now()
    WHERE id = p_entry_id;
    RETURN payment_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_property_rent_payment(
    p_installment_id uuid,
    p_amount numeric,
    p_method text,
    p_reference text DEFAULT NULL,
    p_notes text DEFAULT NULL,
    p_paid_at timestamptz DEFAULT now()
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    installment_row public.property_rent_installments%ROWTYPE;
    target_property_id uuid;
    new_amount numeric(12,2);
    payment_id uuid;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Payment must be positive.'; END IF;
    IF p_method NOT IN ('cash','bank_transfer','card','cheque','other') THEN RAISE EXCEPTION 'Invalid payment method.'; END IF;
    SELECT contract.property_id INTO target_property_id
    FROM public.property_rent_installments AS installment
    JOIN public.property_rent_contracts AS contract ON contract.id = installment.contract_id
    WHERE installment.id = p_installment_id;
    IF target_property_id IS NULL OR NOT public.can_manage_property(target_property_id) THEN
        RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO installment_row FROM public.property_rent_installments WHERE id = p_installment_id FOR UPDATE;
    new_amount := installment_row.amount_paid + p_amount;
    IF new_amount > installment_row.amount_due THEN RAISE EXCEPTION 'Payment exceeds the outstanding balance.'; END IF;
    INSERT INTO public.property_payment_records(property_id, rent_installment_id, amount, payment_method, reference, notes, paid_at, recorded_by)
    VALUES (target_property_id, p_installment_id, p_amount, p_method, NULLIF(btrim(p_reference),''), NULLIF(btrim(p_notes),''), COALESCE(p_paid_at,now()), auth.uid())
    RETURNING id INTO payment_id;
    UPDATE public.property_rent_installments
    SET amount_paid = new_amount,
        status = CASE WHEN new_amount = amount_due THEN 'paid' WHEN new_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        paid_at = CASE WHEN new_amount = amount_due THEN COALESCE(p_paid_at,now()) ELSE paid_at END
    WHERE id = p_installment_id;
    RETURN payment_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_property_charge_payment(uuid,numeric,text,text,text,timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_property_rent_payment(uuid,numeric,text,text,text,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_property_charge_payment(uuid,numeric,text,text,text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_property_rent_payment(uuid,numeric,text,text,text,timestamptz) TO authenticated;

COMMIT;

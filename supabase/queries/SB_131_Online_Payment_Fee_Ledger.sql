-- Snapshot SmartBlock's scheduled fee with each online payment. The resident
-- still pays the outstanding balance; the property ledger records the net due.
BEGIN;

ALTER TABLE public.property_online_payment_sessions
  ADD COLUMN IF NOT EXISTS platform_fee_percent numeric(5,2) NOT NULL DEFAULT 0
    CHECK (platform_fee_percent BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS platform_fee_amount numeric(12,2) NOT NULL DEFAULT 0
    CHECK (platform_fee_amount >= 0),
  ADD COLUMN IF NOT EXISTS net_to_property_amount numeric(12,2) NOT NULL DEFAULT 0
    CHECK (net_to_property_amount >= 0);

UPDATE public.property_online_payment_sessions
SET net_to_property_amount = amount
WHERE net_to_property_amount = 0 AND platform_fee_amount = 0;

ALTER TABLE public.property_payment_records
  ADD COLUMN IF NOT EXISTS platform_fee_percent numeric(5,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS platform_fee_amount numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS net_to_property_amount numeric(12,2) NOT NULL DEFAULT 0;

UPDATE public.property_payment_records
SET net_to_property_amount = amount
WHERE net_to_property_amount = 0 AND platform_fee_amount = 0;

DO $block$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'property_payment_records_fee_split_check'
      AND conrelid = 'public.property_payment_records'::regclass
  ) THEN
    ALTER TABLE public.property_payment_records
      ADD CONSTRAINT property_payment_records_fee_split_check
      CHECK (
        platform_fee_percent BETWEEN 0 AND 100
        AND platform_fee_amount >= 0
        AND net_to_property_amount >= 0
        AND round(platform_fee_amount + net_to_property_amount, 2) = round(amount, 2)
      );
  END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION public.prepare_property_online_payment(
  p_target_type text,
  p_target_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := (SELECT auth.uid());
  target_property_id uuid;
  target_amount numeric(12,2);
  amount_paid numeric(12,2);
  target_label text;
  owner_organization_id uuid;
  payment_row public.property_online_payment_sessions%ROWTYPE;
  balance numeric(12,2);
  active_fee_percent numeric(5,2);
  fee_amount numeric(12,2);
  property_amount numeric(12,2);
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
  END IF;
  IF p_target_type IS NULL OR p_target_type NOT IN ('charge','rent') THEN
    RAISE EXCEPTION 'Invalid payment type.';
  END IF;

  IF p_target_type = 'charge' THEN
    SELECT run.property_id, entry.amount_due, entry.amount_paid,
           owner.organization_id, 'Κοινόχρηστα · ' || run.period_label
    INTO target_property_id, target_amount, amount_paid,
         owner_organization_id, target_label
    FROM public.property_charge_entries AS entry
    JOIN public.property_charge_runs AS run ON run.id = entry.run_id
    JOIN public.property_owners AS owner ON owner.id = entry.property_owner_id
    WHERE entry.id = p_target_id
    FOR UPDATE OF entry;
    IF target_property_id IS NULL OR NOT (
      public.can_access_organization(owner_organization_id)
      OR public.can_manage_property(target_property_id)
    ) THEN
      RAISE EXCEPTION 'You cannot pay this common charge.' USING ERRCODE = '42501';
    END IF;
  ELSE
    SELECT contract.property_id, installment.amount_due, installment.amount_paid,
           'Ενοίκιο · ' || contract.unit_reference || ' · ' || installment.period_start::text
    INTO target_property_id, target_amount, amount_paid, target_label
    FROM public.property_rent_installments AS installment
    JOIN public.property_rent_contracts AS contract ON contract.id = installment.contract_id
    WHERE installment.id = p_target_id
    FOR UPDATE OF installment;
    IF target_property_id IS NULL OR NOT public.can_manage_property(target_property_id) THEN
      RAISE EXCEPTION 'Property management access is required to pay this rent installment.'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  balance := target_amount - amount_paid;
  IF balance <= 0 THEN RAISE EXCEPTION 'This balance is already paid.'; END IF;

  UPDATE public.property_online_payment_sessions
  SET status = 'expired'
  WHERE target_type = p_target_type AND target_id = p_target_id
    AND ((status = 'open' AND expires_at <= now())
      OR (status = 'creating' AND created_at < now() - interval '5 minutes'));

  SELECT * INTO payment_row
  FROM public.property_online_payment_sessions
  WHERE target_type = p_target_type AND target_id = p_target_id
    AND status IN ('creating','open') AND expires_at > now()
  FOR UPDATE;

  IF FOUND THEN
    IF payment_row.created_by <> current_user_id THEN
      RAISE EXCEPTION 'A checkout for this balance is already open.';
    END IF;
    RETURN jsonb_build_object(
      'id', payment_row.id,
      'amount', payment_row.amount,
      'currency', payment_row.currency,
      'description', target_label,
      'status', payment_row.status,
      'is_new', false,
      'platform_fee_percent', payment_row.platform_fee_percent,
      'platform_fee_amount', payment_row.platform_fee_amount,
      'net_to_property_amount', payment_row.net_to_property_amount,
      'stripe_checkout_session_id', payment_row.stripe_checkout_session_id
    );
  END IF;

  SELECT rates.online_payment_fee_percent INTO active_fee_percent
  FROM public.smartblock_current_billing_rates() AS rates;
  active_fee_percent := COALESCE(active_fee_percent, 0);
  fee_amount := round(balance * active_fee_percent / 100, 2);
  property_amount := balance - fee_amount;

  INSERT INTO public.property_online_payment_sessions(
    property_id, target_type, target_id, amount, currency, status, created_by,
    platform_fee_percent, platform_fee_amount, net_to_property_amount
  ) VALUES (
    target_property_id, p_target_type, p_target_id, balance, 'EUR', 'creating', current_user_id,
    active_fee_percent, fee_amount, property_amount
  ) RETURNING * INTO payment_row;

  RETURN jsonb_build_object(
    'id', payment_row.id,
    'amount', payment_row.amount,
    'currency', payment_row.currency,
    'description', target_label,
    'status', payment_row.status,
    'is_new', true,
    'platform_fee_percent', payment_row.platform_fee_percent,
    'platform_fee_amount', payment_row.platform_fee_amount,
    'net_to_property_amount', payment_row.net_to_property_amount,
    'stripe_checkout_session_id', payment_row.stripe_checkout_session_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_property_online_payment(
  p_payment_id uuid,
  p_checkout_session_id text,
  p_payment_intent_id text,
  p_amount_paid_minor bigint,
  p_currency text,
  p_payment_method text,
  p_paid_at timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  payment_row public.property_online_payment_sessions%ROWTYPE;
  entry_amount_due numeric(12,2);
  entry_amount_paid numeric(12,2);
  new_amount numeric(12,2);
  payment_id uuid;
BEGIN
  SELECT * INTO payment_row
  FROM public.property_online_payment_sessions
  WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Online payment session was not found.'; END IF;
  IF payment_row.status = 'paid' THEN
    IF payment_row.stripe_payment_intent_id = p_payment_intent_id
       AND payment_row.stripe_checkout_session_id = p_checkout_session_id THEN
      SELECT id INTO payment_id FROM public.property_payment_records
      WHERE stripe_payment_intent_id = p_payment_intent_id;
      RETURN payment_id;
    END IF;
    RAISE EXCEPTION 'Session has already been paid with a different payment.';
  END IF;
  IF payment_row.status <> 'open'
     OR payment_row.stripe_checkout_session_id IS DISTINCT FROM p_checkout_session_id THEN
    RAISE EXCEPTION 'Checkout session is not open or does not match.';
  END IF;
  IF p_amount_paid_minor <> round(payment_row.amount * 100)::bigint
     OR upper(p_currency) <> payment_row.currency THEN
    RAISE EXCEPTION 'Stripe payment amount or currency does not match the saved balance.';
  END IF;
  IF p_payment_method NOT IN ('card','apple_pay','google_pay') THEN
    RAISE EXCEPTION 'Unsupported Stripe payment method.';
  END IF;

  IF payment_row.target_type = 'charge' THEN
    SELECT amount_due, amount_paid INTO entry_amount_due, entry_amount_paid
    FROM public.property_charge_entries WHERE id = payment_row.target_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Charge entry no longer exists.'; END IF;
  ELSE
    SELECT amount_due, amount_paid INTO entry_amount_due, entry_amount_paid
    FROM public.property_rent_installments WHERE id = payment_row.target_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Rent installment no longer exists.'; END IF;
  END IF;

  new_amount := entry_amount_paid + payment_row.amount;
  IF new_amount > entry_amount_due THEN
    RAISE EXCEPTION 'Balance changed after Checkout started; refund is required.';
  END IF;

  INSERT INTO public.property_payment_records(
    property_id, charge_entry_id, rent_installment_id, amount, payment_method,
    reference, paid_at, recorded_by, stripe_checkout_session_id,
    stripe_payment_intent_id, platform_fee_percent, platform_fee_amount,
    net_to_property_amount
  ) VALUES (
    payment_row.property_id,
    CASE WHEN payment_row.target_type = 'charge' THEN payment_row.target_id END,
    CASE WHEN payment_row.target_type = 'rent' THEN payment_row.target_id END,
    payment_row.amount, p_payment_method, 'Stripe ' || p_payment_intent_id,
    COALESCE(p_paid_at, now()), payment_row.created_by,
    p_checkout_session_id, p_payment_intent_id, payment_row.platform_fee_percent,
    payment_row.platform_fee_amount, payment_row.net_to_property_amount
  ) RETURNING id INTO payment_id;

  IF payment_row.target_type = 'charge' THEN
    UPDATE public.property_charge_entries
    SET amount_paid = new_amount,
        status = CASE WHEN new_amount = amount_due THEN 'paid' WHEN new_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        updated_at = now()
    WHERE id = payment_row.target_id;
  ELSE
    UPDATE public.property_rent_installments
    SET amount_paid = new_amount,
        status = CASE WHEN new_amount = amount_due THEN 'paid' WHEN new_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        paid_at = CASE WHEN new_amount = amount_due THEN COALESCE(p_paid_at, now()) ELSE paid_at END
    WHERE id = payment_row.target_id;
  END IF;

  UPDATE public.property_online_payment_sessions
  SET status = 'paid', stripe_payment_intent_id = p_payment_intent_id,
      paid_at = COALESCE(p_paid_at, now())
  WHERE id = p_payment_id;
  RETURN payment_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.prepare_property_online_payment(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_property_online_payment(uuid,text,text,bigint,text,text,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_property_online_payment(text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_property_online_payment(uuid,text,text,bigint,text,text,timestamptz) TO service_role;

COMMIT;


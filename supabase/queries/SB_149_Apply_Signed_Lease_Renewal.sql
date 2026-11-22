CREATE OR REPLACE FUNCTION public.sign_lease_renewal(
  p_renewal_id uuid,
  p_signer_name text,
  p_confirm boolean
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  renewal_row public.lease_renewals%ROWTYPE;
  event_kind text;
  month_count integer;
BEGIN
  IF actor IS NULL OR p_confirm IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Sign in and explicit electronic acceptance are required.' USING ERRCODE = '42501';
  END IF;
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(p_signer_name,''))) < 3 THEN
    RAISE EXCEPTION 'Enter your full legal name.' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO renewal_row FROM public.lease_renewals WHERE id = p_renewal_id FOR UPDATE;
  IF NOT FOUND OR renewal_row.status <> 'awaiting_signatures' THEN
    RAISE EXCEPTION 'This renewal is not awaiting signatures.' USING ERRCODE = '22023';
  END IF;
  IF actor = renewal_row.owner_user_id AND renewal_row.owner_signed_at IS NULL THEN
    UPDATE public.lease_renewals
      SET owner_signed_at = now(), owner_signed_name = pg_catalog.btrim(p_signer_name), updated_at = now()
      WHERE id = p_renewal_id;
    event_kind := 'owner_signed';
  ELSIF actor = renewal_row.tenant_user_id AND renewal_row.tenant_signed_at IS NULL THEN
    UPDATE public.lease_renewals
      SET tenant_signed_at = now(), tenant_signed_name = pg_catalog.btrim(p_signer_name), updated_at = now()
      WHERE id = p_renewal_id;
    event_kind := 'tenant_signed';
  ELSE
    RAISE EXCEPTION 'Only the assigned owner or tenant can sign, and each party can sign once.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO renewal_row FROM public.lease_renewals WHERE id = p_renewal_id;
  IF renewal_row.owner_signed_at IS NOT NULL AND renewal_row.tenant_signed_at IS NOT NULL THEN
    IF renewal_row.end_date > renewal_row.start_date + INTERVAL '10 years' THEN
      RAISE EXCEPTION 'A lease renewal cannot exceed ten years.' USING ERRCODE = '22023';
    END IF;
    UPDATE public.lease_renewals SET status = 'signed', updated_at = now() WHERE id = p_renewal_id;
    UPDATE public.property_rent_contracts
      SET monthly_rent = renewal_row.monthly_rent,
          start_date = renewal_row.start_date,
          end_date = renewal_row.end_date,
          due_day = renewal_row.rent_due_day,
          status = 'active'
      WHERE id = renewal_row.source_contract_id;

    month_count :=
      (pg_catalog.date_part('year', renewal_row.end_date)::integer - pg_catalog.date_part('year', renewal_row.start_date)::integer) * 12
      + pg_catalog.date_part('month', renewal_row.end_date)::integer - pg_catalog.date_part('month', renewal_row.start_date)::integer;
    INSERT INTO public.property_rent_installments AS existing_installment(contract_id, period_start, due_date, amount_due)
    SELECT renewal_row.source_contract_id,
      (pg_catalog.date_trunc('month', renewal_row.start_date::timestamp) + pg_catalog.make_interval(months => s.month_no))::date,
      GREATEST(
        ((pg_catalog.date_trunc('month', renewal_row.start_date::timestamp) + pg_catalog.make_interval(months => s.month_no))::date + (renewal_row.rent_due_day - 1)),
        CASE WHEN s.month_no = 0 THEN renewal_row.start_date
          ELSE ((pg_catalog.date_trunc('month', renewal_row.start_date::timestamp) + pg_catalog.make_interval(months => s.month_no))::date + (renewal_row.rent_due_day - 1)) END
      ),
      renewal_row.monthly_rent
    FROM pg_catalog.generate_series(0, month_count) AS s(month_no)
    WHERE (pg_catalog.date_trunc('month', renewal_row.start_date::timestamp) + pg_catalog.make_interval(months => s.month_no))::date <= renewal_row.end_date
    ON CONFLICT (contract_id, period_start) DO UPDATE
      SET due_date = EXCLUDED.due_date,
          amount_due = EXCLUDED.amount_due
      WHERE existing_installment.amount_paid = 0
        AND existing_installment.status NOT IN ('paid', 'cancelled');
  END IF;

  INSERT INTO public.lease_renewal_events(renewal_id, actor_user_id, event_type, actor_name, terms_sha256)
    VALUES (p_renewal_id, actor, event_kind, pg_catalog.btrim(p_signer_name), renewal_row.terms_sha256);
  RETURN (SELECT status FROM public.lease_renewals WHERE id = p_renewal_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.sign_lease_renewal(uuid,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sign_lease_renewal(uuid,text,boolean) TO authenticated;


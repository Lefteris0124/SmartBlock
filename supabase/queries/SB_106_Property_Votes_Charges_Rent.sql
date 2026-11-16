-- SB_106_Property_Votes_Charges_Rent
-- First usable property modules for voting, common-charge cycles, and rentals.

BEGIN;

CREATE TABLE public.property_votes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (length(btrim(title)) > 0),
    question text NOT NULL CHECK (length(btrim(question)) > 0),
    status text NOT NULL DEFAULT 'open'
        CHECK (status IN ('draft', 'open', 'closed')),
    opens_at timestamptz NOT NULL DEFAULT now(),
    closes_at timestamptz,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT property_votes_close_after_open CHECK (closes_at IS NULL OR closes_at > opens_at)
);

CREATE TABLE public.property_vote_options (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vote_id uuid NOT NULL REFERENCES public.property_votes(id) ON DELETE CASCADE,
    label text NOT NULL CHECK (length(btrim(label)) > 0),
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (vote_id, label)
);

CREATE TABLE public.property_vote_ballots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vote_id uuid NOT NULL REFERENCES public.property_votes(id) ON DELETE CASCADE,
    option_id uuid NOT NULL REFERENCES public.property_vote_options(id) ON DELETE CASCADE,
    voter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    cast_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (vote_id, voter_id)
);

CREATE TABLE public.property_charge_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    period_label text NOT NULL CHECK (length(btrim(period_label)) > 0),
    description text,
    total_amount numeric(12, 2) NOT NULL CHECK (total_amount > 0),
    currency text NOT NULL DEFAULT 'EUR' CHECK (currency ~ '^[A-Z]{3}$'),
    due_date date NOT NULL,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    created_by uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (property_id, period_label)
);

CREATE TABLE public.property_charge_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES public.property_charge_runs(id) ON DELETE CASCADE,
    property_owner_id uuid NOT NULL REFERENCES public.property_owners(id) ON DELETE RESTRICT,
    amount_due numeric(12, 2) NOT NULL CHECK (amount_due >= 0),
    amount_paid numeric(12, 2) NOT NULL DEFAULT 0
        CHECK (amount_paid >= 0 AND amount_paid <= amount_due),
    status text NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'partial', 'paid')),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_id, property_owner_id)
);

CREATE TABLE public.property_rent_contracts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    unit_reference text NOT NULL CHECK (length(btrim(unit_reference)) > 0),
    tenant_name text NOT NULL CHECK (length(btrim(tenant_name)) > 0),
    tenant_phone_e164 text CHECK (
        tenant_phone_e164 IS NULL OR tenant_phone_e164 ~ '^\+[1-9][0-9]{6,14}$'
    ),
    monthly_rent numeric(12, 2) NOT NULL CHECK (monthly_rent > 0),
    currency text NOT NULL DEFAULT 'EUR' CHECK (currency ~ '^[A-Z]{3}$'),
    start_date date NOT NULL,
    end_date date,
    due_day integer NOT NULL DEFAULT 1 CHECK (due_day BETWEEN 1 AND 28),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended', 'cancelled')),
    created_by uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT property_rent_contract_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE public.property_rent_installments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id uuid NOT NULL REFERENCES public.property_rent_contracts(id) ON DELETE CASCADE,
    period_start date NOT NULL,
    due_date date NOT NULL,
    amount_due numeric(12, 2) NOT NULL CHECK (amount_due > 0),
    amount_paid numeric(12, 2) NOT NULL DEFAULT 0
        CHECK (amount_paid >= 0 AND amount_paid <= amount_due),
    status text NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'partial', 'paid')),
    paid_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (contract_id, period_start)
);

CREATE INDEX idx_property_votes_property ON public.property_votes(property_id, created_at DESC);
CREATE INDEX idx_property_charge_runs_property ON public.property_charge_runs(property_id, created_at DESC);
CREATE INDEX idx_property_rent_contracts_property ON public.property_rent_contracts(property_id, created_at DESC);

ALTER TABLE public.property_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_vote_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_vote_ballots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_charge_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_charge_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_rent_contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_rent_installments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
    public.property_votes,
    public.property_vote_options,
    public.property_vote_ballots,
    public.property_charge_runs,
    public.property_charge_entries,
    public.property_rent_contracts,
    public.property_rent_installments
FROM anon, authenticated;

GRANT SELECT, INSERT ON TABLE
    public.property_votes,
    public.property_vote_options,
    public.property_charge_runs,
    public.property_rent_contracts
TO authenticated;

GRANT SELECT ON TABLE
    public.property_vote_ballots,
    public.property_charge_entries,
    public.property_rent_installments
TO authenticated;

CREATE POLICY property_votes_select ON public.property_votes
FOR SELECT TO authenticated USING (public.can_access_property(property_id));
CREATE POLICY property_votes_insert ON public.property_votes
FOR INSERT TO authenticated WITH CHECK (
    created_by = (SELECT auth.uid())
    AND public.can_manage_property(property_id)
);

CREATE POLICY property_vote_options_select ON public.property_vote_options
FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM public.property_votes AS vote
        WHERE vote.id = vote_id
          AND public.can_access_property(vote.property_id)
    )
);
CREATE POLICY property_vote_options_insert ON public.property_vote_options
FOR INSERT TO authenticated WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.property_votes AS vote
        WHERE vote.id = vote_id
          AND vote.created_by = (SELECT auth.uid())
          AND public.can_manage_property(vote.property_id)
    )
);

CREATE POLICY property_vote_ballots_select ON public.property_vote_ballots
FOR SELECT TO authenticated USING (
    voter_id = (SELECT auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.property_votes AS vote
        WHERE vote.id = vote_id
          AND public.can_manage_property(vote.property_id)
    )
);

CREATE POLICY property_charge_runs_select ON public.property_charge_runs
FOR SELECT TO authenticated USING (public.can_access_property(property_id));
CREATE POLICY property_charge_runs_insert ON public.property_charge_runs
FOR INSERT TO authenticated WITH CHECK (
    created_by = (SELECT auth.uid())
    AND public.can_manage_property(property_id)
);

CREATE POLICY property_charge_entries_select ON public.property_charge_entries
FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM public.property_charge_runs AS run
        WHERE run.id = run_id
          AND public.can_access_property(run.property_id)
    )
);
CREATE POLICY property_rent_contracts_select ON public.property_rent_contracts
FOR SELECT TO authenticated USING (public.can_access_property(property_id));
CREATE POLICY property_rent_contracts_insert ON public.property_rent_contracts
FOR INSERT TO authenticated WITH CHECK (
    created_by = (SELECT auth.uid())
    AND public.can_manage_property(property_id)
);

CREATE POLICY property_rent_installments_select ON public.property_rent_installments
FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM public.property_rent_contracts AS contract
        WHERE contract.id = contract_id
          AND public.can_access_property(contract.property_id)
    )
);
CREATE OR REPLACE FUNCTION public.create_property_charge_run(
    p_property_id uuid,
    p_period_label text,
    p_description text,
    p_total_amount numeric,
    p_due_date date,
    p_currency text DEFAULT 'EUR'
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
    remaining_amount numeric(12, 2);
    allocation numeric(12, 2);
    active_share_total numeric(7, 2);
BEGIN
    IF current_user_id IS NULL OR NOT public.can_manage_property(p_property_id) THEN
        RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
    END IF;
    IF p_total_amount <= 0 OR length(btrim(p_period_label)) = 0 THEN
        RAISE EXCEPTION 'Enter a period and a positive amount.';
    END IF;

    SELECT count(*), COALESCE(sum(ownership_percentage), 0)
    INTO owner_count, active_share_total
    FROM public.property_owners
    WHERE property_id = p_property_id AND ownership_status = 'active';

    IF owner_count = 0 OR active_share_total <> 100 THEN
        RAISE EXCEPTION 'Active ownership shares must total 100%% before common charges are created.';
    END IF;

    INSERT INTO public.property_charge_runs (
        property_id, period_label, description, total_amount,
        currency, due_date, created_by
    ) VALUES (
        p_property_id, btrim(p_period_label), NULLIF(btrim(p_description), ''),
        p_total_amount, upper(p_currency), p_due_date, current_user_id
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

CREATE OR REPLACE FUNCTION public.cast_property_vote(
    p_vote_id uuid,
    p_option_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    vote_property_id uuid;
    vote_status text;
    close_time timestamptz;
    new_ballot_id uuid;
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
    END IF;

    SELECT property_id, status, closes_at
    INTO vote_property_id, vote_status, close_time
    FROM public.property_votes WHERE id = p_vote_id;

    IF NOT FOUND OR NOT public.can_access_property(vote_property_id) THEN
        RAISE EXCEPTION 'You cannot access this vote.' USING ERRCODE = '42501';
    END IF;
    IF vote_status <> 'open' OR (close_time IS NOT NULL AND close_time <= now()) THEN
        RAISE EXCEPTION 'This vote is closed.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.property_vote_options
        WHERE id = p_option_id AND vote_id = p_vote_id
    ) THEN
        RAISE EXCEPTION 'The selected option does not belong to this vote.';
    END IF;

    INSERT INTO public.property_vote_ballots (vote_id, option_id, voter_id)
    VALUES (p_vote_id, p_option_id, current_user_id)
    RETURNING id INTO new_ballot_id;
    RETURN new_ballot_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_property_rent_contract(
    p_property_id uuid,
    p_unit_reference text,
    p_tenant_name text,
    p_tenant_phone_e164 text,
    p_monthly_rent numeric,
    p_currency text,
    p_start_date date,
    p_end_date date,
    p_due_day integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    current_user_id uuid := (SELECT auth.uid());
    contract_id uuid;
BEGIN
    IF current_user_id IS NULL OR NOT public.can_manage_property(p_property_id) THEN
        RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
    END IF;
    IF p_monthly_rent <= 0 OR p_due_day NOT BETWEEN 1 AND 28 THEN
        RAISE EXCEPTION 'Enter a positive rent and a due day from 1 to 28.';
    END IF;

    INSERT INTO public.property_rent_contracts (
        property_id, unit_reference, tenant_name, tenant_phone_e164,
        monthly_rent, currency, start_date, end_date, due_day, created_by
    ) VALUES (
        p_property_id, btrim(p_unit_reference), btrim(p_tenant_name),
        NULLIF(btrim(p_tenant_phone_e164), ''), p_monthly_rent,
        upper(COALESCE(NULLIF(btrim(p_currency), ''), 'EUR')),
        p_start_date, p_end_date, p_due_day, current_user_id
    ) RETURNING id INTO contract_id;

    INSERT INTO public.property_rent_installments (
        contract_id, period_start, due_date, amount_due
    )
    SELECT contract_id,
           date_trunc('month', p_start_date::timestamp)::date + (series.month_offset || ' months')::interval,
           GREATEST(
               (date_trunc('month', p_start_date::timestamp)::date + (series.month_offset || ' months')::interval)::date + (p_due_day - 1),
               CASE WHEN series.month_offset = 0 THEN p_start_date ELSE p_start_date END
           ),
           p_monthly_rent
    FROM generate_series(0, 11) AS series(month_offset)
    WHERE p_end_date IS NULL
       OR date_trunc('month', p_start_date::timestamp)::date + (series.month_offset || ' months')::interval <= p_end_date;

    RETURN contract_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_property_rent_payment(
    p_installment_id uuid,
    p_amount numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    installment_row public.property_rent_installments%ROWTYPE;
    target_property_id uuid;
    new_amount numeric(12, 2);
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Payment must be positive.'; END IF;
    SELECT contract.property_id INTO target_property_id
    FROM public.property_rent_installments AS installment
    JOIN public.property_rent_contracts AS contract ON contract.id = installment.contract_id
    WHERE installment.id = p_installment_id;
    IF target_property_id IS NULL OR NOT public.can_manage_property(target_property_id) THEN
        RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO installment_row FROM public.property_rent_installments
    WHERE id = p_installment_id FOR UPDATE;
    new_amount := installment_row.amount_paid + p_amount;
    IF new_amount > installment_row.amount_due THEN RAISE EXCEPTION 'Payment exceeds the outstanding balance.'; END IF;
    UPDATE public.property_rent_installments
    SET amount_paid = new_amount,
        status = CASE WHEN new_amount = amount_due THEN 'paid' WHEN new_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        paid_at = CASE WHEN new_amount = amount_due THEN now() ELSE paid_at END
    WHERE id = p_installment_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_property_charge_payment(
    p_entry_id uuid,
    p_amount numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    entry_row public.property_charge_entries%ROWTYPE;
    new_amount numeric(12,2);
    property_id uuid;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Payment must be positive.'; END IF;
    SELECT run.property_id INTO property_id
    FROM public.property_charge_entries AS entry
    JOIN public.property_charge_runs AS run ON run.id = entry.run_id
    WHERE entry.id = p_entry_id;
    IF property_id IS NULL OR NOT public.can_manage_property(property_id) THEN
        RAISE EXCEPTION 'Property management access is required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO entry_row FROM public.property_charge_entries
    WHERE id = p_entry_id FOR UPDATE;
    new_amount := entry_row.amount_paid + p_amount;
    IF new_amount > entry_row.amount_due THEN
        RAISE EXCEPTION 'Payment exceeds the outstanding balance.';
    END IF;

    UPDATE public.property_charge_entries
    SET amount_paid = new_amount,
        status = CASE
            WHEN new_amount = amount_due THEN 'paid'
            WHEN new_amount > 0 THEN 'partial'
            ELSE 'unpaid'
        END,
        updated_at = now()
    WHERE id = p_entry_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_property_charge_run(uuid, text, text, numeric, date, text)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cast_property_vote(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_property_rent_contract(uuid, text, text, text, numeric, text, date, date, integer)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_property_charge_payment(uuid, numeric)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_property_rent_payment(uuid, numeric)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_property_charge_run(uuid, text, text, numeric, date, text)
TO authenticated;
GRANT EXECUTE ON FUNCTION public.cast_property_vote(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_property_rent_contract(uuid, text, text, text, numeric, text, date, date, integer)
TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_property_charge_payment(uuid, numeric)
TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_property_rent_payment(uuid, numeric)
TO authenticated;

COMMIT;

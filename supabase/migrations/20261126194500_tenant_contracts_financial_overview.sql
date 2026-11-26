CREATE TABLE IF NOT EXISTS public.lease_tenant_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  contract_id uuid NOT NULL REFERENCES public.property_rent_contracts(id) ON DELETE CASCADE,
  tenant_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_type text NOT NULL CHECK (request_type IN ('early_termination','renewal')),
  requested_end_date date,
  message text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','reviewed','accepted','declined','withdrawn')),
  decision_note text,
  reviewed_by uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.lease_tenant_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lease_tenant_requests_parties_read ON public.lease_tenant_requests;
CREATE POLICY lease_tenant_requests_parties_read ON public.lease_tenant_requests
FOR SELECT TO authenticated
USING (tenant_user_id=(SELECT auth.uid()) OR public.can_manage_property(property_id) OR public.is_smartblock_staff());
DROP POLICY IF EXISTS lease_tenant_requests_managers_update ON public.lease_tenant_requests;
CREATE POLICY lease_tenant_requests_managers_update ON public.lease_tenant_requests
FOR UPDATE TO authenticated
USING (public.can_manage_property(property_id) OR public.is_smartblock_staff())
WITH CHECK (public.can_manage_property(property_id) OR public.is_smartblock_staff());
GRANT SELECT ON public.lease_tenant_requests TO authenticated;

CREATE OR REPLACE FUNCTION public.my_tenant_lease_contracts()
RETURNS TABLE(contract_id uuid,property_id uuid,property_name text,property_address text,unit_reference text,monthly_rent numeric,currency text,start_date date,end_date date,due_day integer,contract_status text,deposit_amount numeric,common_charges text,furniture_and_inventory text,included_services text,special_terms text,payment_terms text,owner_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT rc.id,rc.property_id,p.name,concat_ws(', ',p.address,p.city,p.country),
    rc.unit_reference,rc.monthly_rent,rc.currency,rc.start_date,rc.end_date,rc.due_day,rc.status,
    COALESCE(lco.deposit_amount,lr.deposit_amount),COALESCE(lco.common_charges,lr.common_charges),
    COALESCE(lco.furniture_and_inventory,lr.furniture_and_inventory),COALESCE(lco.included_services,lr.included_services),
    COALESCE(lco.special_terms,lr.special_terms),COALESCE(lco.payment_terms,lr.payment_terms),COALESCE(lco.owner_name,lr.owner_name)
  FROM public.property_rent_contracts rc
  JOIN public.properties p ON p.id=rc.property_id
  LEFT JOIN LATERAL (
    SELECT x.deposit_amount,x.common_charges,x.furniture_and_inventory,x.included_services,x.special_terms,x.payment_terms,x.owner_name
    FROM public.lease_contract_offers x
    WHERE x.rent_contract_id=rc.id AND x.tenant_user_id=(SELECT auth.uid())
    ORDER BY x.created_at DESC LIMIT 1
  ) lco ON true
  LEFT JOIN LATERAL (
    SELECT x.deposit_amount,x.common_charges,x.furniture_and_inventory,x.included_services,x.special_terms,x.payment_terms,x.owner_name
    FROM public.lease_renewals x
    WHERE x.source_contract_id=rc.id AND x.tenant_user_id=(SELECT auth.uid())
    ORDER BY x.created_at DESC LIMIT 1
  ) lr ON true
  WHERE rc.tenant_user_id=(SELECT auth.uid())
  ORDER BY rc.end_date NULLS LAST,p.name,rc.unit_reference;
END;
$$;
REVOKE ALL ON FUNCTION public.my_tenant_lease_contracts() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_tenant_lease_contracts() TO authenticated;

CREATE OR REPLACE FUNCTION public.create_tenant_lease_request(p_contract_id uuid,p_request_type text,p_message text DEFAULT '',p_requested_end_date date DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_property_id uuid; v_id uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501'; END IF;
  IF p_request_type NOT IN ('early_termination','renewal') THEN RAISE EXCEPTION 'Invalid lease request type.' USING ERRCODE='22023'; END IF;
  SELECT rc.property_id INTO v_property_id FROM public.property_rent_contracts rc
  WHERE rc.id=p_contract_id AND rc.tenant_user_id=(SELECT auth.uid())
    AND (rc.end_date IS NULL OR rc.end_date>=current_date)
    AND rc.status IN ('active','signed','current') FOR SHARE;
  IF v_property_id IS NULL THEN RAISE EXCEPTION 'An active rental contract for your account was not found.' USING ERRCODE='42501'; END IF;
  IF p_request_type='early_termination' AND p_requested_end_date IS NULL THEN RAISE EXCEPTION 'Select a requested termination date.' USING ERRCODE='22023'; END IF;
  INSERT INTO public.lease_tenant_requests(property_id,contract_id,tenant_user_id,request_type,requested_end_date,message)
  VALUES(v_property_id,p_contract_id,(SELECT auth.uid()),p_request_type,p_requested_end_date,left(btrim(COALESCE(p_message,'')),2000))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_tenant_lease_request(uuid,text,text,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_tenant_lease_request(uuid,text,text,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.notify_lease_tenant_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_tenant text; v_el text; v_en text;
BEGIN
  SELECT COALESCE(NULLIF(btrim(p.full_name),''),u.email,'Ένοικος') INTO v_tenant
  FROM public.profiles p JOIN auth.users u ON u.id=p.id WHERE p.id=NEW.tenant_user_id;
  v_el:=CASE WHEN NEW.request_type='renewal' THEN v_tenant||' ζητά ανανέωση μίσθωσης.' ELSE v_tenant||' ζητά πρόωρη διακοπή μίσθωσης.' END;
  v_en:=CASE WHEN NEW.request_type='renewal' THEN v_tenant||' requested a lease renewal.' ELSE v_tenant||' requested early lease termination.' END;
  INSERT INTO public.user_notifications(user_id,property_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
  SELECT r.user_id,NEW.property_id,'lease_request',
    CASE WHEN NEW.request_type='renewal' THEN 'Αίτημα ανανέωσης μίσθωσης' ELSE 'Αίτημα πρόωρης διακοπής μίσθωσης' END,
    CASE WHEN NEW.request_type='renewal' THEN 'Lease renewal request' ELSE 'Early lease termination request' END,
    v_el,v_en,'lease_renewal_requests',NEW.id
  FROM (
    SELECT DISTINCT om.user_id FROM public.property_owners po
    JOIN public.organization_members om ON om.organization_id=po.organization_id
    WHERE po.property_id=NEW.property_id AND po.ownership_status='active' AND om.membership_status='active'
    UNION SELECT p.id FROM public.profiles p WHERE p.global_role='central_admin'
  ) r WHERE r.user_id IS NOT NULL;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS lease_tenant_request_notify ON public.lease_tenant_requests;
CREATE TRIGGER lease_tenant_request_notify AFTER INSERT ON public.lease_tenant_requests
FOR EACH ROW EXECUTE FUNCTION public.notify_lease_tenant_request();

CREATE OR REPLACE FUNCTION public.my_tenant_financial_summary()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_user uuid := (SELECT auth.uid());
  v_rent_paid numeric(12,2);
  v_rent_due numeric(12,2);
  v_common_paid numeric(12,2);
  v_common_due numeric(12,2);
  v_damage_paid numeric(12,2);
  v_damage_due numeric(12,2);
  v_deposit_agreed numeric(12,2);
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501'; END IF;

  SELECT COALESCE(sum(ri.amount_paid),0),
         COALESCE(sum(CASE WHEN ri.due_date<=current_date THEN greatest(ri.amount_due-ri.amount_paid,0) ELSE 0 END),0)
    INTO v_rent_paid,v_rent_due
  FROM public.property_rent_installments ri
  JOIN public.property_rent_contracts rc ON rc.id=ri.contract_id
  WHERE rc.tenant_user_id=v_user;

  SELECT COALESCE(sum(COALESCE(pa.paid,0)),0),
         COALESCE(sum(CASE WHEN ac.due_date<=current_date THEN greatest(ac.amount-COALESCE(pa.paid,0),0) ELSE 0 END),0),
         COALESCE(sum(CASE WHEN lower(COALESCE(ac.charge_type,'')||' '||COALESCE(ac.description,'')) ~ '(damage|repair|βλαβ|ζημι|επισκευ)' THEN COALESCE(pa.paid,0) ELSE 0 END),0),
         COALESCE(sum(CASE WHEN ac.due_date<=current_date AND lower(COALESCE(ac.charge_type,'')||' '||COALESCE(ac.description,'')) ~ '(damage|repair|βλαβ|ζημι|επισκευ)' THEN greatest(ac.amount-COALESCE(pa.paid,0),0) ELSE 0 END),0)
    INTO v_common_paid,v_common_due,v_damage_paid,v_damage_due
  FROM public.apartment_charges ac
  JOIN public.building_memberships m ON m.building_id=ac.building_id AND m.apartment_id=ac.apartment_id
     AND m.user_id=v_user AND m.active
  LEFT JOIN LATERAL (
    SELECT sum(a.amount) paid FROM public.payment_allocations a
    JOIN public.payments p ON p.id=a.payment_id
    WHERE a.charge_id=ac.id AND p.status='confirmed'
  ) pa ON true;

  SELECT COALESCE(sum(COALESCE((
    SELECT x.deposit_amount FROM public.lease_contract_offers x
    WHERE x.rent_contract_id=rc.id AND x.tenant_user_id=v_user
    ORDER BY x.created_at DESC LIMIT 1
  ),(
    SELECT x.deposit_amount FROM public.lease_renewals x
    WHERE x.source_contract_id=rc.id AND x.tenant_user_id=v_user
    ORDER BY x.created_at DESC LIMIT 1
  ),0)),0)
  INTO v_deposit_agreed
  FROM public.property_rent_contracts rc
  WHERE rc.tenant_user_id=v_user;

  RETURN jsonb_build_object(
    'rent_paid',v_rent_paid,'rent_due',v_rent_due,
    'common_charges_paid',v_common_paid,'common_charges_due',v_common_due,
    'damage_paid_recorded',v_damage_paid,'damage_due_recorded',v_damage_due,
    'deposit_agreed',v_deposit_agreed
  );
END;
$$;
REVOKE ALL ON FUNCTION public.my_tenant_financial_summary() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_tenant_financial_summary() TO authenticated;
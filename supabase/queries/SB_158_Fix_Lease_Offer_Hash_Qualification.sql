CREATE OR REPLACE FUNCTION public.get_lease_contract_offer(p_token text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  actor_email text;
  offer public.lease_contract_offers%ROWTYPE;
  property_row public.properties%ROWTYPE;
BEGIN
  IF actor IS NULL OR length(coalesce(p_token,'')) < 32 THEN
    RAISE EXCEPTION 'Sign in with the invited email to view this contract.' USING ERRCODE='42501';
  END IF;
  SELECT lower(u.email::text) INTO actor_email FROM auth.users u WHERE u.id=actor;
  SELECT * INTO offer FROM public.lease_contract_offers o
    WHERE o.invite_token_sha256=pg_catalog.encode(extensions.digest(p_token,'sha256'),'hex')
      AND lower(o.tenant_email)=actor_email
      AND o.status IN ('awaiting_tenant','accepted')
      AND (o.status='accepted' OR o.invite_expires_at>now());
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This invitation is invalid, expired, or belongs to another email.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO property_row FROM public.properties p WHERE p.id=offer.property_id;
  INSERT INTO public.lease_contract_offer_events(offer_id,actor_user_id,event_type,terms_sha256)
  VALUES(offer.id,actor,'viewed',offer.terms_sha256);
  RETURN (pg_catalog.to_jsonb(offer) - ARRAY['invite_token_sha256']) ||
    pg_catalog.jsonb_build_object(
      'property_name',property_row.name,
      'property_address',pg_catalog.concat_ws(', ',property_row.address,property_row.city,property_row.country)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_lease_contract_offer(
  p_property_id uuid,p_unit_reference text,p_owner_name text,p_owner_id_type text,p_owner_id_number text,
  p_tenant_name text,p_tenant_email text,p_tenant_phone_e164 text,p_monthly_rent numeric,
  p_deposit_amount numeric,p_common_charges numeric,p_start_date date,p_end_date date,
  p_rent_due_day integer,p_furniture_and_inventory text,p_included_services text,p_special_terms text,
  p_guarantor_name text,p_guarantor_terms text,p_owner_confirm boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  actor_email text;
  property_row public.properties%ROWTYPE;
  offer_id uuid;
  raw_token text := pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
  terms text;
  payment_clause text :=
    'Το ενοίκιο, η εγγύηση και οι συμφωνημένες πληρωμές καταχωρούνται και διεκπεραιώνονται μέσω του SmartBlock με τους διαθέσιμους τρόπους πληρωμής. Το SmartBlock παρέχει το ψηφιακό κανάλι διαχείρισης και δεν αποτελεί συμβαλλόμενο μέρος της μίσθωσης.';
BEGIN
  IF actor IS NULL OR p_owner_confirm IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Sign in and confirm the lease terms before sending.' USING ERRCODE='42501';
  END IF;
  IF NOT public.can_manage_property(p_property_id) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE='42501';
  END IF;
  IF length(btrim(coalesce(p_unit_reference,'')))=0 OR length(btrim(coalesce(p_owner_name,'')))<3
     OR length(btrim(coalesce(p_owner_id_type,'')))<2 OR length(btrim(coalesce(p_owner_id_number,'')))<3
     OR length(btrim(coalesce(p_tenant_name,'')))<3 OR position('@' in coalesce(p_tenant_email,''))<2
     OR coalesce(p_monthly_rent,0)<=0 OR coalesce(p_deposit_amount,-1)<0 OR coalesce(p_common_charges,-1)<0
     OR p_start_date IS NULL OR p_end_date IS NULL OR p_end_date<=p_start_date
     OR p_end_date>p_start_date+interval '10 years' OR p_rent_due_day NOT BETWEEN 1 AND 28 THEN
    RAISE EXCEPTION 'Complete the required lease details with valid values.' USING ERRCODE='22023';
  END IF;
  IF p_tenant_phone_e164 IS NOT NULL AND btrim(p_tenant_phone_e164)<>'' AND p_tenant_phone_e164 !~ '^\+[1-9][0-9]{6,14}$' THEN
    RAISE EXCEPTION 'Use the international phone format, for example +35799123456.' USING ERRCODE='22023';
  END IF;
  SELECT u.email::text INTO actor_email FROM auth.users u WHERE u.id=actor;
  IF actor_email IS NULL OR lower(actor_email)=lower(btrim(p_tenant_email)) THEN
    RAISE EXCEPTION 'Owner and tenant must use different email accounts.' USING ERRCODE='22023';
  END IF;
  SELECT * INTO property_row FROM public.properties p WHERE p.id=p_property_id;
  terms:=pg_catalog.jsonb_build_object(
    'property_id',p_property_id,'property_name',property_row.name,
    'property_address',pg_catalog.concat_ws(', ',property_row.address,property_row.city,property_row.country),
    'unit_reference',btrim(p_unit_reference),'owner_user_id',actor,'owner_name',btrim(p_owner_name),
    'owner_email',actor_email,'owner_id_type',btrim(p_owner_id_type),'owner_id_number',btrim(p_owner_id_number),
    'tenant_name',btrim(p_tenant_name),'tenant_email',lower(btrim(p_tenant_email)),
    'monthly_rent',p_monthly_rent,'deposit_amount',p_deposit_amount,'common_charges',p_common_charges,
    'currency','EUR','start_date',p_start_date,'end_date',p_end_date,'rent_due_day',p_rent_due_day,
    'furniture_and_inventory',coalesce(p_furniture_and_inventory,''),'included_services',coalesce(p_included_services,''),
    'special_terms',coalesce(p_special_terms,''),'guarantor_name',coalesce(p_guarantor_name,''),
    'guarantor_terms',coalesce(p_guarantor_terms,''),'payment_terms',payment_clause
  )::text;
  INSERT INTO public.lease_contract_offers(
    property_id,unit_reference,owner_user_id,owner_name,owner_email,owner_id_type,owner_id_number,
    tenant_name,tenant_email,tenant_phone_e164,monthly_rent,deposit_amount,common_charges,start_date,end_date,
    rent_due_day,furniture_and_inventory,included_services,special_terms,guarantor_name,guarantor_terms,
    payment_terms,terms_sha256,invite_token_sha256,invite_expires_at,owner_signed_name
  ) VALUES(
    p_property_id,btrim(p_unit_reference),actor,btrim(p_owner_name),actor_email,btrim(p_owner_id_type),
    btrim(p_owner_id_number),btrim(p_tenant_name),lower(btrim(p_tenant_email)),
    nullif(btrim(coalesce(p_tenant_phone_e164,'')),''),p_monthly_rent,p_deposit_amount,p_common_charges,
    p_start_date,p_end_date,p_rent_due_day,coalesce(p_furniture_and_inventory,''),coalesce(p_included_services,''),
    coalesce(p_special_terms,''),coalesce(p_guarantor_name,''),coalesce(p_guarantor_terms,''),
    payment_clause,pg_catalog.encode(extensions.digest(terms,'sha256'),'hex'),
    pg_catalog.encode(extensions.digest(raw_token,'sha256'),'hex'),now()+interval '14 days',btrim(p_owner_name)
  ) RETURNING id INTO offer_id;
  INSERT INTO public.lease_contract_offer_events(offer_id,actor_user_id,event_type,signer_name,terms_sha256)
  VALUES(offer_id,actor,'created',btrim(p_owner_name),(SELECT o.terms_sha256 FROM public.lease_contract_offers o WHERE o.id=offer_id));
  RETURN pg_catalog.jsonb_build_object('offer_id',offer_id,'token',raw_token);
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_lease_contract_offer(
  p_token text,p_signer_name text,p_tenant_id_type text,p_tenant_id_number text,p_confirm boolean
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  actor_email text;
  offer public.lease_contract_offers%ROWTYPE;
  contract_id uuid;
BEGIN
  IF actor IS NULL OR p_confirm IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Sign in and explicitly accept the lease terms.' USING ERRCODE='42501';
  END IF;
  IF length(btrim(coalesce(p_signer_name,'')))<3 OR length(btrim(coalesce(p_tenant_id_type,'')))<2
     OR length(btrim(coalesce(p_tenant_id_number,'')))<3 THEN
    RAISE EXCEPTION 'Enter your full name and identification details.' USING ERRCODE='22023';
  END IF;
  SELECT lower(u.email::text) INTO actor_email FROM auth.users u WHERE u.id=actor;
  SELECT * INTO offer FROM public.lease_contract_offers o
    WHERE o.invite_token_sha256=pg_catalog.encode(extensions.digest(p_token,'sha256'),'hex')
      AND lower(o.tenant_email)=actor_email AND o.status='awaiting_tenant' AND o.invite_expires_at>now()
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'This contract invitation cannot be accepted.' USING ERRCODE='42501'; END IF;
  INSERT INTO public.property_rent_contracts(
    property_id,unit_reference,tenant_name,tenant_phone_e164,tenant_user_id,monthly_rent,currency,
    start_date,end_date,due_day,status,created_by
  ) VALUES(
    offer.property_id,offer.unit_reference,btrim(p_signer_name),offer.tenant_phone_e164,actor,
    offer.monthly_rent,offer.currency,offer.start_date,offer.end_date,offer.rent_due_day,'active',offer.owner_user_id
  ) RETURNING id INTO contract_id;
  INSERT INTO public.property_rent_installments(contract_id,period_start,due_date,amount_due)
  SELECT contract_id,(date_trunc('month',offer.start_date::timestamp)+make_interval(months=>s.m))::date,
    GREATEST(
      (date_trunc('month',offer.start_date::timestamp)+make_interval(months=>s.m))::date+(offer.rent_due_day-1),
      CASE WHEN s.m=0 THEN offer.start_date
           ELSE (date_trunc('month',offer.start_date::timestamp)+make_interval(months=>s.m))::date+(offer.rent_due_day-1)
      END),offer.monthly_rent
  FROM generate_series(0,11) AS s(m)
  WHERE offer.end_date IS NULL OR (date_trunc('month',offer.start_date::timestamp)+make_interval(months=>s.m))::date<=offer.end_date;
  UPDATE public.lease_contract_offers SET tenant_user_id=actor,tenant_id_type=btrim(p_tenant_id_type),
    tenant_id_number=btrim(p_tenant_id_number),tenant_signed_at=now(),tenant_signed_name=btrim(p_signer_name),
    status='accepted',rent_contract_id=contract_id,updated_at=now() WHERE id=offer.id;
  INSERT INTO public.lease_contract_offer_events(offer_id,actor_user_id,event_type,signer_name,terms_sha256)
  VALUES(offer.id,actor,'accepted',btrim(p_signer_name),offer.terms_sha256);
  INSERT INTO public.account_role_requests(user_id,requested_roles,status)
  VALUES(actor,ARRAY['tenant']::text[],'pending')
  ON CONFLICT(user_id) DO UPDATE SET requested_roles=ARRAY(
    SELECT DISTINCT role
    FROM unnest(public.account_role_requests.requested_roles||ARRAY['tenant']::text[]) AS role
    ORDER BY role
  );
  UPDATE public.profiles SET
    full_name=CASE WHEN length(btrim(coalesce(full_name,'')))<3 THEN btrim(p_signer_name) ELSE full_name END,
    phone=coalesce(nullif(phone,''),offer.tenant_phone_e164)
  WHERE id=actor;
  RETURN contract_id;
END;
$function$;
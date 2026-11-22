BEGIN;

-- Create a disposable but real owner/tenant dataset for administrator trials.
-- The RPC is intentionally callable only with the server-side service key.
CREATE OR REPLACE FUNCTION public.smartblock_admin_ensure_trial_fixture(
  p_owner_user_id uuid,
  p_tenant_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_org_id uuid;
  v_property_id uuid;
  v_owner_id uuid;
  v_vote_id uuid;
  v_charge_id uuid;
  v_contract_id uuid;
  v_start date := date_trunc('month', now())::date;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.account_role_requests(
    user_id, requested_roles, status, submitted_at, reviewed_at, review_note
  ) VALUES
    (p_owner_user_id, ARRAY['property_owner']::text[], 'approved', now(), now(), 'SmartBlock disposable admin trial'),
    (p_tenant_user_id, ARRAY['tenant']::text[], 'approved', now(), now(), 'SmartBlock disposable admin trial')
  ON CONFLICT (user_id) DO UPDATE SET
    requested_roles = EXCLUDED.requested_roles,
    status = 'approved',
    submitted_at = EXCLUDED.submitted_at,
    reviewed_at = EXCLUDED.reviewed_at,
    review_note = EXCLUDED.review_note;

  SELECT o.id INTO v_org_id
  FROM public.organizations o
  WHERE o.created_by = p_owner_user_id
    AND o.display_name = 'SmartBlock Trial Owner';
  IF v_org_id IS NULL THEN
    INSERT INTO public.organizations(
      organization_type, display_name, country, approval_status, created_by
    ) VALUES ('individual', 'SmartBlock Trial Owner', 'Cyprus', 'approved', p_owner_user_id)
    RETURNING id INTO v_org_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organization_members m
    WHERE m.organization_id = v_org_id AND m.user_id = p_owner_user_id
      AND m.member_role = 'owner'
  ) THEN
    INSERT INTO public.organization_members(
      organization_id, user_id, member_role, membership_status,
      invited_by, approved_by, approved_at
    ) VALUES (
      v_org_id, p_owner_user_id, 'owner', 'active', p_owner_user_id,
      p_owner_user_id, now()
    );
  ELSE
    UPDATE public.organization_members SET membership_status='active', approved_by=p_owner_user_id,
      approved_at=now()
    WHERE organization_id=v_org_id AND user_id=p_owner_user_id AND member_role='owner';
  END IF;

  SELECT p.id INTO v_property_id
  FROM public.properties p
  WHERE p.created_by = p_owner_user_id AND p.name = 'SmartBlock Trial Residence';
  IF v_property_id IS NULL THEN
    INSERT INTO public.properties(
      organization_id, property_type, name, address, city, country,
      management_model, approval_status, created_by, total_apartments,
      manager_user_id, building_model
    ) VALUES (
      v_org_id, 'building', 'SmartBlock Trial Residence',
      '1 SmartBlock Trial Lane', 'Nicosia', 'Cyprus',
      'self_service', 'approved', p_owner_user_id, 2,
      p_owner_user_id, 'physical'
    ) RETURNING id INTO v_property_id;
  ELSE
    UPDATE public.properties SET organization_id=v_org_id, approval_status='approved',
      manager_user_id=p_owner_user_id, total_apartments=2
    WHERE id=v_property_id;
  END IF;

  SELECT po.id INTO v_owner_id FROM public.property_owners po
  WHERE po.property_id=v_property_id AND po.organization_id=v_org_id
    AND po.ownership_status='active';
  IF v_owner_id IS NULL THEN
    INSERT INTO public.property_owners(
      property_id, organization_id, ownership_percentage,
      is_primary_representative, ownership_status, created_by
    ) VALUES (v_property_id, v_org_id, 100, true, 'active', p_owner_user_id)
    RETURNING id INTO v_owner_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.property_residents r
    WHERE r.property_id=v_property_id AND r.user_id=p_tenant_user_id
      AND r.apartment_number='2'
  ) THEN
    INSERT INTO public.property_residents(
      property_id, user_id, resident_email, apartment_number, active, assigned_by
    ) VALUES (
      v_property_id, p_tenant_user_id, 'smartblock.trial.tenant@smartblock.invalid',
      '2', true, p_owner_user_id
    );
  END IF;

  SELECT v.id INTO v_vote_id FROM public.property_votes v
  WHERE v.property_id=v_property_id AND v.title='Trial: repaint the entrance';
  IF v_vote_id IS NULL THEN
    INSERT INTO public.property_votes(
      property_id, title, question, status, opens_at, closes_at, created_by
    ) VALUES (
      v_property_id, 'Trial: repaint the entrance',
      'Should the entrance be repainted this month?', 'open', now(), now()+interval '14 days',
      p_owner_user_id
    ) RETURNING id INTO v_vote_id;
    INSERT INTO public.property_vote_options(vote_id,label,sort_order)
    VALUES (v_vote_id,'Yes',1),(v_vote_id,'No',2);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.property_notes n
    WHERE n.property_id=v_property_id AND n.body='Trial announcement: Welcome to the SmartBlock test building.'
  ) THEN
    INSERT INTO public.property_notes(property_id,body,created_by)
    VALUES (v_property_id,'Trial announcement: Welcome to the SmartBlock test building.',p_owner_user_id);
  END IF;

  SELECT r.id INTO v_charge_id FROM public.property_charge_runs r
  WHERE r.property_id=v_property_id AND r.period_label='SmartBlock Trial Common Charges';
  IF v_charge_id IS NULL THEN
    INSERT INTO public.property_charge_runs(
      property_id, period_label, description, total_amount, currency,
      due_date, status, created_by, billing_cycle, allocation_method
    ) VALUES (
      v_property_id, 'SmartBlock Trial Common Charges',
      'Disposable example charge run. No payment is collected.', 170, 'EUR',
      current_date+14, 'open', p_owner_user_id, 'monthly', 'per_apartment'
    ) RETURNING id INTO v_charge_id;
    INSERT INTO public.property_charge_entries(run_id,property_owner_id,amount_due)
    VALUES (v_charge_id,v_owner_id,170);
  END IF;

  SELECT c.id INTO v_contract_id FROM public.property_rent_contracts c
  WHERE c.property_id=v_property_id AND c.unit_reference='2'
    AND c.tenant_name='SmartBlock Trial Tenant';
  IF v_contract_id IS NULL THEN
    INSERT INTO public.property_rent_contracts(
      property_id,unit_reference,tenant_name,monthly_rent,currency,
      start_date,end_date,due_day,status,created_by
    ) VALUES (
      v_property_id,'2','SmartBlock Trial Tenant',650,'EUR',v_start,
      (v_start+interval '1 year')::date,1,'active',p_owner_user_id
    ) RETURNING id INTO v_contract_id;
    INSERT INTO public.property_rent_installments(
      contract_id,period_start,due_date,amount_due
    ) VALUES (v_contract_id,v_start,v_start,650);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.property_service_requests r
    WHERE r.property_id=v_property_id AND r.title='Trial: leaking kitchen sink'
      AND r.requester_id=p_tenant_user_id
  ) THEN
    INSERT INTO public.property_service_requests(
      property_id,requester_id,title,description,request_type,priority,
      location,apartment_number,issue_scope
    ) VALUES (
      v_property_id,p_tenant_user_id,'Trial: leaking kitchen sink',
      'Disposable example report for testing the tenant service flow.',
      'damage_report','normal','Kitchen','2','unit'
    );
  END IF;

  RETURN jsonb_build_object('property_id',v_property_id,'organization_id',v_org_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.smartblock_admin_ensure_trial_fixture(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.smartblock_admin_ensure_trial_fixture(uuid,uuid) TO service_role;

-- Do not send fake trial registrations or demo property events to real staff.
CREATE OR REPLACE FUNCTION public.notify_property_audience(
  p_property_id uuid, p_audience text[], p_type text,
  p_title_el text, p_title_en text, p_message_el text, p_message_en text,
  p_related_type text, p_related_id uuid, p_exclude_user uuid DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.user_notifications(
    user_id, property_id, notification_type, title_el, title_en,
    message_el, message_en, related_type, related_id
  )
  SELECT DISTINCT target.user_id, p_property_id, p_type, p_title_el, p_title_en,
         p_message_el, p_message_en, p_related_type, p_related_id
  FROM (
    SELECT staff.user_id FROM public.smartblock_staff AS staff
      WHERE staff.is_active AND 'staff' = ANY(p_audience)
        AND NOT EXISTS (
          SELECT 1 FROM public.properties AS property
          JOIN auth.users AS trial_owner ON trial_owner.id=property.created_by
          WHERE property.id=p_property_id
            AND trial_owner.raw_app_meta_data ->> 'smartblock_trial' = 'true'
        )
    UNION
    SELECT member.user_id
    FROM public.property_owners AS owner
    JOIN public.organization_members AS member
      ON member.organization_id = owner.organization_id
     AND member.membership_status = 'active'
     AND member.user_id IS NOT NULL
    WHERE owner.property_id = p_property_id
      AND owner.ownership_status = 'active'
      AND ('owners' = ANY(p_audience) OR 'property' = ANY(p_audience))
    UNION
    SELECT resident.user_id FROM public.property_residents AS resident
      WHERE resident.property_id = p_property_id AND resident.active
        AND ('tenants' = ANY(p_audience) OR 'property' = ANY(p_audience))
  ) AS target
  WHERE target.user_id IS NOT NULL
    AND target.user_id IS DISTINCT FROM p_exclude_user
  ON CONFLICT (user_id, notification_type, related_type, related_id) DO NOTHING;
END;
$function$;
REVOKE ALL ON FUNCTION public.notify_property_audience(uuid,text[],text,text,text,text,text,text,uuid,uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_registration_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM auth.users AS account
    WHERE account.id=NEW.user_id
      AND account.raw_app_meta_data ->> 'smartblock_trial' = 'true'
  ) THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.user_notifications(user_id, notification_type, title_el,title_en,message_el,message_en,related_type,related_id)
  SELECT staff.user_id,'registration','Νέα εγγραφή προς έγκριση','New registration for review',
         'Υποβλήθηκε αίτημα επιλογής ρόλου.','A new role registration is waiting for review.',
         'account_role_requests',NEW.user_id
  FROM public.smartblock_staff AS staff WHERE staff.is_active
  ON CONFLICT (user_id, notification_type, related_type, related_id) DO NOTHING;
  RETURN NEW;
END;
$function$;

COMMIT;
\n
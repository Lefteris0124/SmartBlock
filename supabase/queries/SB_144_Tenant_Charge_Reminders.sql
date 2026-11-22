CREATE OR REPLACE FUNCTION public.refresh_property_due_notifications()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE affected integer := 0; v_count integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501'; END IF;

  INSERT INTO public.user_notifications(user_id,property_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
  SELECT targets.user_id,c.property_id,
         CASE WHEN i.due_date < current_date THEN 'rent_overdue' ELSE 'rent_due' END,
         CASE WHEN i.due_date < current_date THEN 'Καθυστερεί το ενοίκιο' ELSE 'Υπενθύμιση ενοικίου' END,
         CASE WHEN i.due_date < current_date THEN 'Rent is overdue' ELSE 'Rent reminder' END,
         c.unit_reference || ' · €' || (i.amount_due-i.amount_paid)::text || ' · ' || i.due_date::text,
         c.unit_reference || ' · €' || (i.amount_due-i.amount_paid)::text || ' · ' || i.due_date::text,
         'property_rent_installments',i.id
  FROM public.property_rent_installments i
  JOIN public.property_rent_contracts c ON c.id=i.contract_id AND c.status='active'
  JOIN LATERAL (
    SELECT r.user_id FROM public.property_residents r
      WHERE r.property_id=c.property_id AND r.active AND r.apartment_number=c.unit_reference
        AND i.amount_paid<i.amount_due AND i.due_date<=current_date+3
    UNION
    SELECT m.user_id FROM public.property_owners o
      JOIN public.organization_members m ON m.organization_id=o.organization_id
        AND m.membership_status='active' AND m.user_id IS NOT NULL
      WHERE o.property_id=c.property_id AND o.ownership_status='active'
        AND i.amount_paid<i.amount_due AND i.due_date<=current_date+3
    UNION
    SELECT s.user_id FROM public.smartblock_staff s WHERE s.is_active
      AND i.amount_paid<i.amount_due AND i.due_date<=current_date+3
  ) targets ON true
  WHERE i.amount_paid<i.amount_due AND i.due_date<=current_date+3
  ON CONFLICT (user_id,notification_type,related_type,related_id) DO NOTHING;
  GET DIAGNOSTICS affected=ROW_COUNT;

  INSERT INTO public.user_notifications(user_id,property_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
  SELECT targets.user_id,r.property_id,
         CASE WHEN run.due_date<current_date THEN 'charges_overdue' ELSE 'charges_due' END,
         CASE WHEN run.due_date<current_date THEN 'Καθυστερούν τα κοινόχρηστα' ELSE 'Υπενθύμιση κοινοχρήστων' END,
         CASE WHEN run.due_date<current_date THEN 'Common charges are overdue' ELSE 'Common charges reminder' END,
         run.period_label || ' · €' || (e.amount_due-e.amount_paid)::text || ' · ' || run.due_date::text,
         run.period_label || ' · €' || (e.amount_due-e.amount_paid)::text || ' · ' || run.due_date::text,
         'property_charge_entries',e.id
  FROM public.property_charge_entries e
  JOIN public.property_owners o ON o.id=e.property_owner_id
  JOIN public.property_charge_runs run ON run.id=e.run_id
  JOIN public.properties r ON r.id=run.property_id
  JOIN LATERAL (
    SELECT m.user_id FROM public.organization_members m
      WHERE m.organization_id=o.organization_id AND m.membership_status='active' AND m.user_id IS NOT NULL
    UNION
    SELECT s.user_id FROM public.smartblock_staff s WHERE s.is_active
  ) targets ON true
  WHERE e.amount_paid<e.amount_due AND run.due_date<=current_date+3
  ON CONFLICT (user_id,notification_type,related_type,related_id) DO NOTHING;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  affected:=affected+v_count;

  WITH due_runs AS (
    SELECT run.id,run.property_id,run.due_date
    FROM public.property_charge_runs run
    JOIN public.property_charge_entries e ON e.run_id=run.id
    GROUP BY run.id,run.property_id,run.due_date
    HAVING SUM(e.amount_due-e.amount_paid)>0 AND run.due_date<=current_date+3
  )
  INSERT INTO public.user_notifications(user_id,property_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
  SELECT DISTINCT resident.user_id,due_runs.property_id,
         CASE WHEN due_runs.due_date<current_date THEN 'building_charges_overdue' ELSE 'building_charges_due' END,
         CASE WHEN due_runs.due_date<current_date THEN 'Εκκρεμούν κοινόχρηστα κτιρίου' ELSE 'Υπενθύμιση κοινοχρήστων κτιρίου' END,
         CASE WHEN due_runs.due_date<current_date THEN 'Building common charges are overdue' ELSE 'Building common charges reminder' END,
         'Έλεγξε την καρτέλα οικονομικών της πολυκατοικίας για την κατανομή και την ημερομηνία πληρωμής.',
         'Check the building finances for your allocation and payment due date.',
         'property_charge_runs',due_runs.id
  FROM due_runs
  JOIN public.property_residents resident ON resident.property_id=due_runs.property_id AND resident.active
  ON CONFLICT (user_id,notification_type,related_type,related_id) DO NOTHING;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  affected:=affected+v_count;

  SELECT count(*)::integer INTO affected
  FROM public.user_notifications n
  WHERE n.user_id=auth.uid() AND NOT n.is_read;
  RETURN affected;
END;
$function$;
REVOKE ALL ON FUNCTION public.refresh_property_due_notifications() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.refresh_property_due_notifications() TO authenticated;

CREATE OR REPLACE FUNCTION public.review_lease_tenant_request(p_request_id uuid,p_decision text,p_note text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_property_id uuid; v_tenant uuid; v_type text; v_status text;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501'; END IF;
  IF p_decision NOT IN ('accepted','declined','reviewed') THEN RAISE EXCEPTION 'Invalid decision.' USING ERRCODE='22023'; END IF;
  SELECT property_id,tenant_user_id,request_type,status
    INTO v_property_id,v_tenant,v_type,v_status
  FROM public.lease_tenant_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Lease request not found.' USING ERRCODE='P0002'; END IF;
  IF NOT COALESCE(public.can_manage_property(v_property_id),false)
     AND NOT COALESCE(public.is_smartblock_staff(),false) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE='42501';
  END IF;
  IF v_status NOT IN ('requested','reviewed') THEN
    RAISE EXCEPTION 'This request has already been decided.' USING ERRCODE='22023';
  END IF;
  UPDATE public.lease_tenant_requests
  SET status=p_decision,decision_note=left(btrim(COALESCE(p_note,'')),2000),
      reviewed_by=(SELECT auth.uid()),reviewed_at=now(),updated_at=now()
  WHERE id=p_request_id;
  INSERT INTO public.user_notifications(user_id,property_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id)
  VALUES(v_tenant,v_property_id,'lease_request_response',
    CASE WHEN p_decision='accepted' THEN 'Το αίτημα μίσθωσης εγκρίθηκε' WHEN p_decision='declined' THEN 'Απάντηση στο αίτημα μίσθωσης' ELSE 'Ενημέρωση για το αίτημα μίσθωσης' END,
    CASE WHEN p_decision='accepted' THEN 'Lease request accepted' WHEN p_decision='declined' THEN 'Lease request update' ELSE 'Lease request update' END,
    CASE WHEN p_decision='accepted' THEN 'Ο ιδιοκτήτης αποδέχθηκε το αίτημά σου.' WHEN p_decision='declined' THEN 'Ο ιδιοκτήτης απάντησε στο αίτημά σου.' ELSE 'Το αίτημά σου εξετάζεται.' END,
    CASE WHEN p_decision='accepted' THEN 'The owner accepted your request.' WHEN p_decision='declined' THEN 'The owner responded to your request.' ELSE 'Your request is under review.' END,
    'lease_renewal_requests',p_request_id);
  RETURN jsonb_build_object('updated',true,'status',p_decision);
END;
$$;
REVOKE ALL ON FUNCTION public.review_lease_tenant_request(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.review_lease_tenant_request(uuid,text,text) TO authenticated;
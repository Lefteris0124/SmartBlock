CREATE OR REPLACE FUNCTION public.admin_list_user_accounts()
RETURNS TABLE (user_id uuid,email text,full_name text,phone text,requested_roles text[],role_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_smartblock_admin() THEN RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE='42501'; END IF;
  RETURN QUERY SELECT u.id,u.email::text,COALESCE(p.full_name,''),p.phone,COALESCE(r.requested_roles,ARRAY[]::text[]),COALESCE(r.status,'not_requested')
    FROM auth.users u LEFT JOIN public.profiles p ON p.id=u.id LEFT JOIN public.account_role_requests r ON r.user_id=u.id
    ORDER BY u.created_at DESC;
END;
$function$;
CREATE OR REPLACE FUNCTION public.admin_update_user_account(p_user_id uuid,p_full_name text,p_phone text,p_roles text[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE roles text[];
BEGIN
  IF NOT public.is_smartblock_admin() THEN RAISE EXCEPTION 'SmartBlock administrator access is required.' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_user_id) THEN RAISE EXCEPTION 'Account not found.' USING ERRCODE='P0002'; END IF;
  SELECT array_agg(DISTINCT role_name ORDER BY role_name) INTO roles FROM unnest(COALESCE(p_roles,ARRAY[]::text[])) role_name;
  IF COALESCE(cardinality(roles),0) NOT BETWEEN 1 AND 2 OR roles <@ ARRAY['property_owner','tenant']::text[] IS NOT TRUE OR cardinality(roles)<>cardinality(p_roles)
    THEN RAISE EXCEPTION 'Choose owner, tenant, or both.' USING ERRCODE='22023'; END IF;
  INSERT INTO public.profiles(id,full_name,phone) VALUES(p_user_id,btrim(p_full_name),NULLIF(btrim(p_phone),''))
    ON CONFLICT(id) DO UPDATE SET full_name=EXCLUDED.full_name,phone=EXCLUDED.phone;
  INSERT INTO public.account_role_requests(user_id,requested_roles,status,submitted_at,reviewed_at,reviewed_by,review_note)
    VALUES(p_user_id,roles,'approved',now(),now(),auth.uid(),'Account details and roles updated by SmartBlock administrator.')
    ON CONFLICT(user_id) DO UPDATE SET requested_roles=EXCLUDED.requested_roles,status='approved',submitted_at=now(),reviewed_at=now(),reviewed_by=auth.uid(),review_note=EXCLUDED.review_note;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_list_user_accounts() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.admin_update_user_account(uuid,text,text,text[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_list_user_accounts() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user_account(uuid,text,text,text[]) TO authenticated;

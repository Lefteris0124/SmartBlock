CREATE OR REPLACE FUNCTION public.get_lease_contract_offer(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
    WHERE o.invite_token_sha256=extensions.encode(extensions.digest(p_token,'sha256'),'hex')
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

REVOKE ALL ON FUNCTION public.get_lease_contract_offer(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_lease_contract_offer(text) TO authenticated;
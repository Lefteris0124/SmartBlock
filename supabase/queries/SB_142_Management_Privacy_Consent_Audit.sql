BEGIN;

ALTER TABLE public.property_management_audit
  ADD COLUMN IF NOT EXISTS actor_display_name text NOT NULL DEFAULT '';

CREATE OR REPLACE FUNCTION public.capture_property_management_audit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE old_data jsonb; new_data jsonb; pid uuid; row_id text; actor_name text;
BEGIN
  old_data := CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END;
  new_data := CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END;
  pid := COALESCE((new_data ->> 'property_id')::uuid, (old_data ->> 'property_id')::uuid);
  row_id := COALESCE(new_data ->> 'id', old_data ->> 'id');
  SELECT COALESCE(NULLIF(u.raw_user_meta_data->>'full_name',''),
                  NULLIF(u.raw_user_meta_data->>'name',''),
                  NULLIF(u.email,''),'SmartBlock system')
  INTO actor_name FROM auth.users u WHERE u.id=(SELECT auth.uid());
  actor_name := COALESCE(actor_name,'SmartBlock system');
  INSERT INTO public.property_management_audit(
    property_id,actor_id,actor_display_name,action,entity_type,entity_id,details
  ) VALUES (
    pid,(SELECT auth.uid()),actor_name,lower(TG_OP),TG_TABLE_NAME,row_id,
    jsonb_build_object('before',old_data,'after',new_data,'recorded_at',now(),'actor_display_name',actor_name)
  );
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

DROP POLICY IF EXISTS property_management_contracts_select ON public.property_management_contracts;
CREATE POLICY property_management_contracts_select ON public.property_management_contracts
  FOR SELECT TO authenticated USING (public.can_manage_property(property_id));
DROP POLICY IF EXISTS property_management_contract_amendments_select ON public.property_management_contract_amendments;
CREATE POLICY property_management_contract_amendments_select ON public.property_management_contract_amendments
  FOR SELECT TO authenticated USING (public.can_manage_property(property_id));
DROP POLICY IF EXISTS property_insurance_policies_select ON public.property_insurance_policies;
CREATE POLICY property_insurance_policies_select ON public.property_insurance_policies
  FOR SELECT TO authenticated USING (public.can_manage_property(property_id));

CREATE TABLE IF NOT EXISTS public.property_management_policies (
  property_id uuid PRIMARY KEY REFERENCES public.properties(id) ON DELETE CASCADE,
  authorization_limit_eur numeric(12,2) NOT NULL DEFAULT 0 CHECK (authorization_limit_eur >= 0),
  consent_version text NOT NULL,
  accepted_by uuid NOT NULL REFERENCES auth.users(id),
  accepted_by_name text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.property_management_policies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.property_management_policies FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.property_management_policies TO authenticated;
CREATE POLICY property_management_policies_manager ON public.property_management_policies
  FOR ALL TO authenticated USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id));

CREATE OR REPLACE FUNCTION public.save_property_management_policy(
  p_property_id uuid, p_authorization_limit_eur numeric, p_accept boolean
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE actor_name text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_property(p_property_id) THEN
    RAISE EXCEPTION 'Property management access is required.' USING ERRCODE='42501';
  END IF;
  IF p_accept IS NOT TRUE OR p_authorization_limit_eur IS NULL OR p_authorization_limit_eur < 0 THEN
    RAISE EXCEPTION 'Confirm the policy and enter a valid amount.' USING ERRCODE='22023';
  END IF;
  SELECT COALESCE(NULLIF(u.raw_user_meta_data->>'full_name',''),
                  NULLIF(u.raw_user_meta_data->>'name',''),
                  NULLIF(u.email,''),'SmartBlock user')
  INTO actor_name FROM auth.users u WHERE u.id=auth.uid();
  INSERT INTO public.property_management_policies(
    property_id,authorization_limit_eur,consent_version,accepted_by,accepted_by_name,accepted_at,updated_at
  ) VALUES (
    p_property_id,p_authorization_limit_eur,'SB-MGMT-2026-01',auth.uid(),
    COALESCE(actor_name,'SmartBlock user'),now(),now()
  )
  ON CONFLICT(property_id) DO UPDATE SET
    authorization_limit_eur=EXCLUDED.authorization_limit_eur,
    consent_version=EXCLUDED.consent_version,
    accepted_by=EXCLUDED.accepted_by,
    accepted_by_name=EXCLUDED.accepted_by_name,
    accepted_at=EXCLUDED.accepted_at,
    updated_at=now();
END;
$function$;
REVOKE ALL ON FUNCTION public.save_property_management_policy(uuid,numeric,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_property_management_policy(uuid,numeric,boolean) TO authenticated;

DROP TRIGGER IF EXISTS property_management_policy_audit ON public.property_management_policies;
CREATE TRIGGER property_management_policy_audit AFTER INSERT OR UPDATE
ON public.property_management_policies FOR EACH ROW
EXECUTE FUNCTION public.capture_property_management_audit();

COMMIT;

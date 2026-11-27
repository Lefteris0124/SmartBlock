ALTER TABLE public.lease_owner_term_preferences
  ADD COLUMN IF NOT EXISTS furniture_inventory text NOT NULL DEFAULT '';

CREATE OR REPLACE FUNCTION public.get_owner_lease_term_settings()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
  owner_terms text;
  furniture_inventory text;
  locked_terms_el text;
  locked_terms_en text;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Sign in to view rental term settings.' USING ERRCODE='42501';
  END IF;

  SELECT coalesce(pref.terms, ''), coalesce(pref.furniture_inventory, '')
    INTO owner_terms, furniture_inventory
  FROM public.lease_owner_term_preferences AS pref
  WHERE pref.user_id = actor;

  SELECT settings.terms_el, settings.terms_en
    INTO locked_terms_el, locked_terms_en
  FROM public.smartblock_lease_term_settings AS settings
  WHERE settings.setting_key = 'default';

  RETURN pg_catalog.jsonb_build_object(
    'owner_terms', coalesce(owner_terms, ''),
    'owner_furniture_inventory', coalesce(furniture_inventory, ''),
    'smartblock_terms_el', coalesce(locked_terms_el, ''),
    'smartblock_terms_en', coalesce(locked_terms_en, '')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_owner_lease_defaults(
  p_terms text,
  p_furniture_inventory text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor uuid := (SELECT auth.uid());
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Sign in to save your default rental terms.' USING ERRCODE='42501';
  END IF;
  IF char_length(coalesce(p_terms, '')) > 10000
     OR char_length(coalesce(p_furniture_inventory, '')) > 5000 THEN
    RAISE EXCEPTION 'Default terms or furniture inventory exceed the allowed length.' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.properties AS property
    WHERE public.can_manage_property(property.id)
  ) THEN
    RAISE EXCEPTION 'Only an owner or authorized property manager can save lease defaults.' USING ERRCODE='42501';
  END IF;

  INSERT INTO public.lease_owner_term_preferences(user_id, terms, furniture_inventory, updated_at)
  VALUES (actor, coalesce(p_terms, ''), coalesce(p_furniture_inventory, ''), now())
  ON CONFLICT (user_id) DO UPDATE
    SET terms = excluded.terms,
        furniture_inventory = excluded.furniture_inventory,
        updated_at = excluded.updated_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_owner_lease_term_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_owner_lease_term_settings() TO authenticated;
REVOKE ALL ON FUNCTION public.save_owner_lease_defaults(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_owner_lease_defaults(text, text) TO authenticated;

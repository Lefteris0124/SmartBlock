BEGIN;

CREATE TABLE IF NOT EXISTS public.property_virtual_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  unit_label text NOT NULL CHECK (length(btrim(unit_label)) BETWEEN 1 AND 80),
  address text NOT NULL CHECK (length(btrim(address)) BETWEEN 3 AND 300),
  city text NOT NULL CHECK (length(btrim(city)) BETWEEN 1 AND 120),
  country text NOT NULL DEFAULT 'Cyprus',
  verification_status text NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending','verified','rejected')),
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (property_id, unit_label)
);

ALTER TABLE public.property_virtual_units ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.property_virtual_units FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.property_virtual_units TO authenticated;

DROP POLICY IF EXISTS property_virtual_units_manage ON public.property_virtual_units;
CREATE POLICY property_virtual_units_manage
  ON public.property_virtual_units FOR ALL TO authenticated
  USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id));

COMMIT;
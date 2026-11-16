-- SB_107_Property_Notes
-- Property-scoped resident notes / short notices.

BEGIN;

CREATE TABLE public.property_notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 500),
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_property_notes_recent ON public.property_notes(property_id, created_at DESC);

ALTER TABLE public.property_notes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.property_notes FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.property_notes TO authenticated;

CREATE POLICY property_notes_select ON public.property_notes
FOR SELECT TO authenticated USING (public.can_access_property(property_id));

CREATE POLICY property_notes_insert ON public.property_notes
FOR INSERT TO authenticated WITH CHECK (
    created_by = (SELECT auth.uid())
    AND public.can_access_property(property_id)
);

CREATE POLICY property_notes_delete ON public.property_notes
FOR DELETE TO authenticated USING (
    created_by = (SELECT auth.uid())
    OR public.can_manage_property(property_id)
);

COMMIT;

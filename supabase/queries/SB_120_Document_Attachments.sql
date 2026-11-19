-- Add document references for meeting packs and service quotes.
-- Existing storage access remains private and is controlled by SB_112 policies.
BEGIN;

ALTER TABLE public.property_meetings
  ADD COLUMN IF NOT EXISTS document_paths jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.property_meetings
  DROP CONSTRAINT IF EXISTS property_meetings_document_paths_array;
ALTER TABLE public.property_meetings
  ADD CONSTRAINT property_meetings_document_paths_array
  CHECK (jsonb_typeof(document_paths) = 'array');

ALTER TABLE public.property_service_requests
  ADD COLUMN IF NOT EXISTS quote_document_path text;

COMMIT;

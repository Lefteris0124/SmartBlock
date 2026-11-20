-- Add structured service and damage-report details to building requests.
BEGIN;

ALTER TABLE public.property_service_requests
  ADD COLUMN IF NOT EXISTS request_type text NOT NULL DEFAULT 'service',
  ADD COLUMN IF NOT EXISTS priority text NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS location text NOT NULL DEFAULT '';

ALTER TABLE public.property_service_requests
  DROP CONSTRAINT IF EXISTS property_service_requests_request_type_check;
ALTER TABLE public.property_service_requests
  ADD CONSTRAINT property_service_requests_request_type_check
  CHECK (request_type IN ('service','damage_report','maintenance','cleaning','safety','other'));

ALTER TABLE public.property_service_requests
  DROP CONSTRAINT IF EXISTS property_service_requests_priority_check;
ALTER TABLE public.property_service_requests
  ADD CONSTRAINT property_service_requests_priority_check
  CHECK (priority IN ('normal','urgent','emergency'));

CREATE INDEX IF NOT EXISTS property_service_requests_property_priority_idx
  ON public.property_service_requests(property_id, priority, created_at DESC);

COMMIT;

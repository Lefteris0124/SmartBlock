BEGIN;

-- QES provider integration stays server-side. No provider credentials,
-- authorization URLs, or raw webhook bodies are stored in exposed tables.
ALTER TABLE public.lease_renewals
  ADD COLUMN IF NOT EXISTS qes_status text NOT NULL DEFAULT 'not_started'
    CHECK (qes_status IN (
      'not_started', 'document_prepared', 'in_progress',
      'partially_signed', 'completed', 'failed', 'expired', 'cancelled'
    )),
  ADD COLUMN IF NOT EXISTS qes_provider text,
  ADD COLUMN IF NOT EXISTS qes_document_sha256 text,
  ADD COLUMN IF NOT EXISTS qes_completed_at timestamptz;

COMMENT ON COLUMN public.lease_renewals.qes_status IS
  'Qualified signature workflow state; distinct from the existing in-app acceptance status.';
COMMENT ON COLUMN public.lease_renewals.qes_provider IS
  'Qualified trust service provider identifier, set only after provider onboarding.';
COMMENT ON COLUMN public.lease_renewals.qes_document_sha256 IS
  'SHA-256 of the exact final document submitted to the qualified signing provider.';

CREATE TABLE IF NOT EXISTS public.lease_renewal_qes_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  renewal_id uuid NOT NULL REFERENCES public.lease_renewals(id) ON DELETE CASCADE,
  started_by uuid NOT NULL REFERENCES auth.users(id),
  provider text NOT NULL CHECK (provider IN ('jcc_csc')),
  provider_request_id text,
  idempotency_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  status text NOT NULL DEFAULT 'preparing'
    CHECK (status IN (
      'preparing', 'ready', 'in_progress', 'partially_signed',
      'completed', 'failed', 'expired', 'cancelled'
    )),
  document_sha256 text,
  document_storage_path text,
  expires_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (document_sha256 IS NULL OR document_sha256 ~ '^[0-9a-f]{64}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS lease_renewal_qes_provider_request_idx
  ON public.lease_renewal_qes_requests(provider, provider_request_id)
  WHERE provider_request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS lease_renewal_qes_requests_renewal_idx
  ON public.lease_renewal_qes_requests(renewal_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS lease_renewal_qes_one_active_request_idx
  ON public.lease_renewal_qes_requests(renewal_id)
  WHERE status IN ('preparing', 'ready', 'in_progress', 'partially_signed');

ALTER TABLE public.lease_renewal_qes_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lease_renewal_qes_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.lease_renewal_qes_requests TO service_role;

CREATE TABLE IF NOT EXISTS public.lease_renewal_qes_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES public.lease_renewal_qes_requests(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN (
    'document_prepared', 'request_created', 'signer_authorized',
    'signer_completed', 'completed', 'failed', 'expired', 'cancelled'
  )),
  provider_event_id text,
  event_sha256 text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CHECK (event_sha256 IS NULL OR event_sha256 ~ '^[0-9a-f]{64}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS lease_renewal_qes_provider_event_idx
  ON public.lease_renewal_qes_events(provider_event_id)
  WHERE provider_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS lease_renewal_qes_events_request_idx
  ON public.lease_renewal_qes_events(request_id, occurred_at);

ALTER TABLE public.lease_renewal_qes_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lease_renewal_qes_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.lease_renewal_qes_events TO service_role;

COMMIT;


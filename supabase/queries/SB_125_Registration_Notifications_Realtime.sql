-- Stream new registration requests only to authenticated admins allowed by
-- the table's row-level policy.
DO $block$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'account_role_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.account_role_requests;
  END IF;
END;
$block$;

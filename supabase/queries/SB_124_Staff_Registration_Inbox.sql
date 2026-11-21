-- Permit trusted SmartBlock staff to view the registration inbox. Only admins
-- can approve or reject requests (enforced by SB_123).
CREATE OR REPLACE FUNCTION public.admin_list_account_role_requests()
RETURNS TABLE (
  user_id uuid,
  email text,
  requested_roles text[],
  status text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  review_note text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_smartblock_staff() THEN
    RAISE EXCEPTION 'SmartBlock staff access is required.'
      USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT request.user_id, account.email::text, request.requested_roles,
           request.status, request.submitted_at, request.reviewed_at,
           request.review_note
    FROM public.account_role_requests AS request
    JOIN auth.users AS account ON account.id = request.user_id
    ORDER BY (request.status = 'pending') DESC, request.submitted_at DESC;
END;
$function$;

CREATE TABLE IF NOT EXISTS public.property_service_request_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.property_service_requests(id) ON DELETE CASCADE,
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_name text NOT NULL DEFAULT '',
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 2 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS property_service_request_comments_request_created_idx
  ON public.property_service_request_comments(request_id,created_at);
CREATE INDEX IF NOT EXISTS property_service_request_comments_property_idx
  ON public.property_service_request_comments(property_id);
ALTER TABLE public.property_service_request_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS property_service_request_comments_read ON public.property_service_request_comments;
CREATE POLICY property_service_request_comments_read
ON public.property_service_request_comments FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.property_service_requests r
    WHERE r.id=request_id AND (
      r.requester_id=(SELECT auth.uid())
      OR public.can_manage_property(r.property_id)
      OR public.is_smartblock_staff()
      OR (r.issue_scope='building' AND public.can_access_property(r.property_id))
    )
  )
);
REVOKE ALL ON public.property_service_request_comments FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.property_service_request_comments TO authenticated;

CREATE OR REPLACE FUNCTION public.comment_on_property_service_request(p_request_id uuid,p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_user uuid := (SELECT auth.uid());
  v_property uuid;
  v_requester uuid;
  v_scope text;
  v_title text;
  v_author text;
  v_id uuid;
  v_body text := btrim(COALESCE(p_body,''));
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501'; END IF;
  IF length(v_body) NOT BETWEEN 2 AND 2000 THEN
    RAISE EXCEPTION 'Comment must be between 2 and 2000 characters.' USING ERRCODE='22023';
  END IF;
  SELECT property_id,requester_id,issue_scope,title
    INTO v_property,v_requester,v_scope,v_title
  FROM public.property_service_requests WHERE id=p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Problem report not found.' USING ERRCODE='P0002'; END IF;
  IF v_requester<>v_user
     AND NOT COALESCE(public.can_manage_property(v_property),false)
     AND NOT COALESCE(public.is_smartblock_staff(),false)
     AND NOT (v_scope='building' AND COALESCE(public.can_access_property(v_property),false)) THEN
    RAISE EXCEPTION 'You cannot comment on this report.' USING ERRCODE='42501';
  END IF;
  SELECT COALESCE(NULLIF(btrim(p.full_name),''),NULLIF(u.email,''),'SmartBlock user')
    INTO v_author
  FROM auth.users u LEFT JOIN public.profiles p ON p.id=u.id
  WHERE u.id=v_user;
  INSERT INTO public.property_service_request_comments(request_id,property_id,author_id,author_name,body)
  VALUES(p_request_id,v_property,v_user,COALESCE(v_author,'SmartBlock user'),v_body)
  RETURNING id INTO v_id;

  INSERT INTO public.user_notifications(
    user_id,property_id,notification_type,title_el,title_en,message_el,message_en,related_type,related_id,is_read,created_at
  )
  SELECT recipients.user_id,v_property,'service_request_comment',
    'Νέο σχόλιο σε αναφορά βλάβης','New comment on a problem report',
    v_author || ' σχολίασε: ' || left(v_body,240),
    v_author || ' commented: ' || left(v_body,240),
    'property_service_requests',p_request_id,false,now()
  FROM (
    SELECT v_requester AS user_id
    UNION
    SELECT DISTINCT om.user_id
    FROM public.property_owners po
    JOIN public.organization_members om ON om.organization_id=po.organization_id
    WHERE po.property_id=v_property AND po.ownership_status='active' AND om.membership_status='active'
    UNION
    SELECT p.id FROM public.profiles p WHERE p.global_role='central_admin'
  ) recipients
  WHERE recipients.user_id IS NOT NULL AND recipients.user_id<>v_user
  ON CONFLICT (user_id,notification_type,related_type,related_id)
  DO UPDATE SET
    message_el=EXCLUDED.message_el,
    message_en=EXCLUDED.message_en,
    is_read=false,
    created_at=now();
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.comment_on_property_service_request(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.comment_on_property_service_request(uuid,text) TO authenticated;
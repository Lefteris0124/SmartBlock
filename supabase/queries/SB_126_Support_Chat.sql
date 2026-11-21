-- In-app user support conversations. Users can access only their threads;
-- SmartBlock staff can access and answer the support inbox.
BEGIN;

CREATE TABLE IF NOT EXISTS public.support_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject text NOT NULL CHECK (length(btrim(subject)) BETWEEN 3 AND 120),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.support_conversations(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 4000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS support_conversations_user_updated_idx
  ON public.support_conversations(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS support_messages_conversation_created_idx
  ON public.support_messages(conversation_id, created_at);

ALTER TABLE public.support_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.support_conversations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.support_messages FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON TABLE public.support_conversations TO authenticated;
GRANT SELECT ON TABLE public.support_messages TO authenticated;

DROP POLICY IF EXISTS support_conversations_read_accessible
  ON public.support_conversations;
CREATE POLICY support_conversations_read_accessible
  ON public.support_conversations FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_smartblock_staff());

DROP POLICY IF EXISTS support_conversations_staff_update
  ON public.support_conversations;
CREATE POLICY support_conversations_staff_update
  ON public.support_conversations FOR UPDATE TO authenticated
  USING (public.is_smartblock_staff())
  WITH CHECK (public.is_smartblock_staff());

DROP POLICY IF EXISTS support_messages_read_accessible
  ON public.support_messages;
CREATE POLICY support_messages_read_accessible
  ON public.support_messages FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.support_conversations AS conversation
      WHERE conversation.id = support_messages.conversation_id
        AND (conversation.user_id = (SELECT auth.uid())
             OR public.is_smartblock_staff())
    )
  );

CREATE OR REPLACE FUNCTION public.touch_support_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  UPDATE public.support_conversations
  SET updated_at = NEW.created_at
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS support_messages_touch_conversation
  ON public.support_messages;
CREATE TRIGGER support_messages_touch_conversation
  AFTER INSERT ON public.support_messages
  FOR EACH ROW EXECUTE FUNCTION public.touch_support_conversation();

CREATE OR REPLACE FUNCTION public.create_support_conversation(
  p_subject text,
  p_initial_message text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_conversation_id uuid;
  v_subject text := btrim(COALESCE(p_subject, ''));
  v_body text := btrim(COALESCE(p_initial_message, ''));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  IF length(v_subject) NOT BETWEEN 3 AND 120 THEN
    RAISE EXCEPTION 'Enter a subject between 3 and 120 characters.' USING ERRCODE = '22023';
  END IF;
  IF length(v_body) NOT BETWEEN 1 AND 4000 THEN
    RAISE EXCEPTION 'Enter a message between 1 and 4000 characters.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.support_conversations(user_id, subject)
  VALUES (v_user_id, v_subject)
  RETURNING id INTO v_conversation_id;
  INSERT INTO public.support_messages(conversation_id, sender_id, body)
  VALUES (v_conversation_id, v_user_id, v_body);
  RETURN v_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_support_message(
  p_conversation_id uuid,
  p_body text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_owner_id uuid;
  v_status text;
  v_message_id uuid;
  v_body text := btrim(COALESCE(p_body, ''));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  IF length(v_body) NOT BETWEEN 1 AND 4000 THEN
    RAISE EXCEPTION 'Enter a message between 1 and 4000 characters.' USING ERRCODE = '22023';
  END IF;
  SELECT conversation.user_id, conversation.status
    INTO v_owner_id, v_status
  FROM public.support_conversations AS conversation
  WHERE conversation.id = p_conversation_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Support conversation not found.' USING ERRCODE = 'P0002';
  END IF;
  IF public.is_smartblock_staff() IS NOT TRUE
     AND (v_owner_id <> v_user_id OR v_status <> 'open') THEN
    RAISE EXCEPTION 'You cannot reply to this support conversation.'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.support_messages(conversation_id, sender_id, body)
  VALUES (p_conversation_id, v_user_id, v_body)
  RETURNING id INTO v_message_id;
  RETURN v_message_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_support_conversation_status(
  p_conversation_id uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT public.is_smartblock_staff() THEN
    RAISE EXCEPTION 'SmartBlock staff access is required.' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('open', 'closed') THEN
    RAISE EXCEPTION 'Choose open or closed.' USING ERRCODE = '22023';
  END IF;
  UPDATE public.support_conversations
  SET status = p_status, updated_at = now()
  WHERE id = p_conversation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Support conversation not found.' USING ERRCODE = 'P0002';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_support_conversations()
RETURNS TABLE (
  conversation_id uuid,
  user_id uuid,
  user_email text,
  subject text,
  status text,
  updated_at timestamptz,
  last_message text,
  last_sender_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in is required.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT conversation.id,
           conversation.user_id,
           account.email::text,
           conversation.subject,
           conversation.status,
           conversation.updated_at,
           latest.body,
           latest.sender_id
    FROM public.support_conversations AS conversation
    JOIN auth.users AS account ON account.id = conversation.user_id
    LEFT JOIN LATERAL (
      SELECT message.body, message.sender_id
      FROM public.support_messages AS message
      WHERE message.conversation_id = conversation.id
      ORDER BY message.created_at DESC
      LIMIT 1
    ) AS latest ON true
    WHERE conversation.user_id = (SELECT auth.uid())
       OR public.is_smartblock_staff()
    ORDER BY conversation.updated_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.touch_support_conversation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_support_conversation(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_support_message(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_support_conversation_status(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_support_conversations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_support_conversation(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_support_message(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_support_conversation_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_support_conversations() TO authenticated;

DO $block$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'support_conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.support_conversations;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'support_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.support_messages;
  END IF;
END;
$block$;

COMMIT;

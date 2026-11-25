REVOKE ALL ON FUNCTION public.create_apartment_lease_offer(
  uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,date,date,integer,
  text,text,text,text,text,boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_apartment_lease_offer(
  uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,date,date,integer,
  text,text,text,text,text,boolean
) TO authenticated, service_role;

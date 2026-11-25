-- Callers must use the apartment-specific wrappers that enforce document-country and expiry requirements.
revoke all on function public.create_lease_contract_offer(uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,date,date,integer,text,text,text,text,text,boolean) from public, anon, authenticated;
revoke all on function public.accept_lease_contract_offer(text,text,text,text,boolean) from public, anon, authenticated;

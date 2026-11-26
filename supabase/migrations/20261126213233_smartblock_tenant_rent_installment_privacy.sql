drop policy if exists property_rent_installments_select on public.property_rent_installments;
create policy property_rent_installments_select
on public.property_rent_installments
for select
to authenticated
using (
  exists (
    select 1
    from public.property_rent_contracts c
    where c.id = property_rent_installments.contract_id
      and (
        public.is_smartblock_staff()
        or public.can_manage_property(c.property_id)
        or c.tenant_user_id = (select auth.uid())
      )
  )
);

-- SB_101_Verify_Organization_Property_RLS
-- Read-only audit of the grants and RLS policies installed by SB_100.

SELECT 'RLS'::text AS category, c.relname::text AS object_name,
       CASE WHEN c.relrowsecurity THEN 'enabled' ELSE 'disabled' END AS details
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN ('organizations', 'organization_members', 'property_portfolios', 'properties', 'property_owners')
UNION ALL
SELECT 'POLICY', p.tablename, p.policyname || ' — ' || p.cmd || ' → ' || array_to_string(p.roles, ', ')
FROM pg_policies AS p
WHERE p.schemaname = 'public'
  AND p.tablename IN ('organizations', 'organization_members', 'property_portfolios', 'properties', 'property_owners')
UNION ALL
SELECT 'TABLE_GRANT', g.table_name, g.grantee || ': ' || g.privilege_type
FROM information_schema.role_table_grants AS g
WHERE g.table_schema = 'public'
  AND g.table_name IN ('organizations', 'organization_members', 'property_portfolios', 'properties', 'property_owners')
  AND g.grantee IN ('anon', 'authenticated')
UNION ALL
SELECT 'FUNCTION_GRANT', r.routine_name, r.grantee || ': ' || r.privilege_type
FROM information_schema.routine_privileges AS r
WHERE r.specific_schema = 'public'
  AND r.routine_name IN ('can_access_organization', 'can_manage_organization', 'can_access_property')
  AND r.grantee IN ('anon', 'authenticated')
ORDER BY category, object_name, details;

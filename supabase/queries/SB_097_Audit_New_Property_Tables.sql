-- SB_097_Audit_New_Property_Tables
-- Read-only audit. This query does not modify database objects or data.
-- Run in Supabase SQL Editor and save the result for the next implementation step.

-- 1) Confirm RLS is enabled and list policies on the five new tables.
SELECT
    c.relname AS table_name,
    c.relrowsecurity AS rls_enabled,
    p.policyname,
    p.permissive,
    p.roles,
    p.cmd,
    p.qual AS using_expression,
    p.with_check AS check_expression
FROM pg_class AS c
JOIN pg_namespace AS n
    ON n.oid = c.relnamespace
LEFT JOIN pg_policies AS p
    ON p.schemaname = n.nspname
   AND p.tablename = c.relname
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN (
      'organizations',
      'organization_members',
      'property_portfolios',
      'properties',
      'property_owners'
  )
ORDER BY c.relname, p.policyname;

-- 2) List foreign-key column pairs for those tables, including composite keys.
SELECT
    source.relname AS table_name,
    source_column.attname AS column_name,
    target.relname AS referenced_table,
    target_column.attname AS referenced_column,
    CASE constraint_row.confdeltype
        WHEN 'a' THEN 'NO ACTION'
        WHEN 'r' THEN 'RESTRICT'
        WHEN 'c' THEN 'CASCADE'
        WHEN 'n' THEN 'SET NULL'
        WHEN 'd' THEN 'SET DEFAULT'
    END AS delete_rule
FROM pg_constraint AS constraint_row
JOIN pg_class AS source
    ON source.oid = constraint_row.conrelid
JOIN pg_namespace AS source_schema
    ON source_schema.oid = source.relnamespace
JOIN pg_class AS target
    ON target.oid = constraint_row.confrelid
CROSS JOIN LATERAL unnest(constraint_row.conkey) WITH ORDINALITY AS source_key(attnum, position)
JOIN LATERAL unnest(constraint_row.confkey) WITH ORDINALITY AS target_key(attnum, position)
    ON target_key.position = source_key.position
JOIN pg_attribute AS source_column
    ON source_column.attrelid = source.oid
   AND source_column.attnum = source_key.attnum
JOIN pg_attribute AS target_column
    ON target_column.attrelid = target.oid
   AND target_column.attnum = target_key.attnum
WHERE constraint_row.contype = 'f'
  AND source_schema.nspname = 'public'
  AND source.relname IN (
      'organizations',
      'organization_members',
      'property_portfolios',
      'properties',
      'property_owners'
  )
ORDER BY source.relname, constraint_row.conname, source_key.position;
-- 3) Confirm the ownership validation trigger and function are present.
SELECT
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table = 'property_owners'
ORDER BY trigger_name, event_manipulation;
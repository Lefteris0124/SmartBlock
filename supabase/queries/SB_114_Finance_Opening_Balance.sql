ALTER TABLE public.property_finance_settings
  ADD COLUMN IF NOT EXISTS opening_balance numeric(12,2) NOT NULL DEFAULT 0
  CHECK (opening_balance >= 0);

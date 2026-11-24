-- ===========================================================================
-- E-WALLET ACCOUNTS NG RESORT (Nov 24, 2026)
--
-- Ang GCash at Maya na pinapadalhan ng bayad ng guest (makikita sa app).
-- Napapalitan na ng admin sa admin panel → Payment Accounts, kasama ang
-- pangalan ng account (para makita ng guest kung kanino siya nagpapadala).
--
-- Ligtas itong patakbuhin nang ilang beses.
-- ===========================================================================

alter table public.resort_settings add column if not exists gcash_number  text;
alter table public.resort_settings add column if not exists gcash_name    text;
alter table public.resort_settings add column if not exists gcash_enabled boolean not null default true;
alter table public.resort_settings add column if not exists maya_number   text;
alter table public.resort_settings add column if not exists maya_name     text;
alter table public.resort_settings add column if not exists maya_enabled  boolean not null default true;
alter table public.resort_settings add column if not exists payment_accounts_updated_at timestamptz;

-- Ang dating nakalagay sa app (palitan sa admin kung iba na).
update public.resort_settings
   set gcash_number = coalesce(gcash_number, '09628828792'),
       gcash_name   = coalesce(gcash_name, 'Aryana''s Guests House'),
       maya_number  = coalesce(maya_number, '09628828792'),
       maya_name    = coalesce(maya_name, 'Aryana''s Guests House')
 where id = 1;

-- Tamang format: 11 digits na nagsisimula sa 09, at may pangalan.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'resort_settings_pay_accounts_check') then
    alter table public.resort_settings add constraint resort_settings_pay_accounts_check check (
      (gcash_number is null or gcash_number ~ '^09[0-9]{9}$') and
      (maya_number  is null or maya_number  ~ '^09[0-9]{9}$') and
      char_length(coalesce(gcash_name, '')) <= 60 and
      char_length(coalesce(maya_name, ''))  <= 60 and
      (gcash_enabled or maya_enabled)
    );
  end if;
end $$;

-- Dapat lumabas ang kasalukuyang mga account
select gcash_number, gcash_name, gcash_enabled, maya_number, maya_name, maya_enabled
  from public.resort_settings where id = 1;

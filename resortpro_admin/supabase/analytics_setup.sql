-- ===========================================================================
-- ANALYTICS SETUP (Nov 19, 2026)
--   I-paste LAHAT sa Supabase > SQL Editor > New query, tapos Run.
--
--   Part A: mga bagong column (extra pax, extension, iba pang singil, discount,
--           taga-saan ang customer, paano nalaman ang resort, okasyon)
--   Part B: expenses table (gastos ng resort)
--   Part C: dagdag na ₱100 bawat guest (3 taon pataas) na lampas sa kasama sa presyo (server)
--   Part D: BINUBURA ang lahat ng TEST bookings, payments, refunds, surveys,
--           booking logs at notifications (hindi na maibabalik)
--   Part E: simulated data ng 2026 (31 bookings + gastos bawat buwan),
--           naka-mark na is_simulated = true
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Part A: Mga bagong column
-- ---------------------------------------------------------------------------
alter table public.bookings add column if not exists discount           numeric not null default 0;
alter table public.bookings add column if not exists extra_pax          int     not null default 0;
alter table public.bookings add column if not exists extra_pax_fee      numeric not null default 0;
alter table public.bookings add column if not exists extension_hours    int     not null default 0;
alter table public.bookings add column if not exists extension_fee      numeric not null default 0;
alter table public.bookings add column if not exists other_charges      numeric not null default 0;
alter table public.bookings add column if not exists other_charges_note text;
alter table public.bookings add column if not exists customer_location  text;
alter table public.bookings add column if not exists referral_source    text;
alter table public.bookings add column if not exists occasion           text;
alter table public.bookings add column if not exists is_simulated       boolean not null default false;

-- Ilang guest ang kasama sa presyo ng package (null = walang dagdag na singil bawat tao)
alter table public.packages add column if not exists included_pax int;
update public.packages set included_pax = 20
 where included_pax is null and name not ilike 'function hall%';
-- Ayon sa client: hanggang 50 tao sa pool packages (₱100 bawat isa lampas 20)
update public.packages set max_pax = 50
 where name not ilike 'function hall%' and (max_pax is null or max_pax < 50);

alter table public.resort_settings add column if not exists extra_pax_rate numeric not null default 100;

-- ---------------------------------------------------------------------------
-- Part B: Expenses (gastos ng resort) — admin lang ang may access
-- ---------------------------------------------------------------------------
create table if not exists public.expenses (
  id           bigint generated always as identity primary key,
  expense_date date    not null,
  category     text    not null,
  amount       numeric not null check (amount >= 0),
  note         text,
  is_simulated boolean not null default false,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now()
);
create index if not exists expenses_date_idx on public.expenses (expense_date);

alter table public.expenses enable row level security;
drop policy if exists "admins manage expenses" on public.expenses;
create policy "admins manage expenses" on public.expenses
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Part C: Server: dagdag na singil bawat guest na lampas sa kasama sa presyo
--   (Kapareho ng dati, may dagdag lang sa INSERT ng client.)
-- ---------------------------------------------------------------------------
create or replace function public.bookings_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  inc  int;
  rate numeric;
begin
  if tg_op = 'INSERT' and not public.is_admin() then
    new.total_amount := coalesce(public.price_for(new.package_id, new.booking_date), new.total_amount);
    select included_pax into inc from public.packages where id = new.package_id;
    select coalesce(extra_pax_rate, 100) into rate from public.resort_settings where id = 1;
    new.extra_pax       := case when coalesce(inc, 0) > 0 then greatest(0, coalesce(new.total_pax, 0) - coalesce(new.infants, 0) - inc) else 0 end;
    new.extra_pax_fee   := new.extra_pax * coalesce(rate, 100);
    new.total_amount    := coalesce(new.total_amount, 0) + new.extra_pax_fee;
    new.discount        := 0;
    new.extension_hours := 0;
    new.extension_fee   := 0;
    new.other_charges   := 0;
    new.is_simulated    := false;
    new.status := 'reserved';
    new.source := 'online';
  end if;

  if new.status::text in ('cancelled', 'no_show') then
    return new;
  end if;

  -- Patakaran ng resort: kailangan ng verified na 50% downpayment bago ma-confirm (ma-reserve).
  if tg_op = 'UPDATE' and old.status::text = 'reserved' and new.status::text = 'confirmed' then
    if (select coalesce(sum(amount), 0) from public.payments
         where booking_id::text = new.id::text and coalesce(status, 'verified') = 'verified')
       + 0.01 < round(coalesce(new.total_amount, 0) * 0.5) then
      raise exception 'DOWNPAYMENT_REQUIRED: A verified 50%% downpayment is needed before confirming.';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and new.booking_date is not distinct from old.booking_date
     and new.package_id is not distinct from old.package_id
     and old.status::text not in ('cancelled', 'no_show') then
    return new;
  end if;

  -- Isa-isang pagproseso ng booking sa iisang petsa (para walang sabay na makalusot).
  perform pg_advisory_xact_lock(hashtext('booking:' || new.booking_date::text));

  if exists (
    select 1 from public.blocked_dates
    where block_date = new.booking_date
      and (package_id is null or package_id = new.package_id)
  ) then
    raise exception 'DATE_BLOCKED: This date is not available for booking.';
  end if;

  if exists (
    select 1 from public.bookings
    where booking_date = new.booking_date
      and status::text not in ('cancelled', 'no_show')
      and id <> new.id
      and public.package_slots(package_id) && public.package_slots(new.package_id)
  ) then
    raise exception 'DATE_TAKEN: This date is already booked at that time.';
  end if;

  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Part D: Burahin ang lahat ng TEST data (bookings at mga kaugnay nito)
--   Hindi ginagalaw: mga account (profiles), packages, gallery, chat,
--   blocked dates at pricing rules.
-- ---------------------------------------------------------------------------
delete from public.payments;
delete from public.refund_requests;
delete from public.booking_surveys;
delete from public.booking_logs;
delete from public.notifications;
delete from public.bookings;
delete from public.expenses where is_simulated;

-- ---------------------------------------------------------------------------
-- Part E: Simulated data ng 2026 (Jan 1 – Nov 18), mula sa client interview
--   Pansamantalang pinapatay ang mga trigger para hindi mabago ang presyo,
--   status at bayad, at para walang notification na lumabas.
-- ---------------------------------------------------------------------------
alter table public.bookings disable trigger user;
alter table public.payments disable trigger user;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-02-05', 'completed', 'phone', 'Customer 001',
    30, 0, 8, 3, 17, 2,
    9000, 0, 10, 1000, 5, 2500, 0, null,
    'Other Laguna towns', 'Returning customer', 'Family outing', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-02-05 07:30:00+08', '2026-02-05 23:00:00+08', '2026-01-21 10:45:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0205-DP', '2026-01-21 10:45:00+08'::timestamptz from nb
union all
select id, 6250, 'cash', 'balance', 'verified', null, '2026-02-05 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-02-12', 'completed', 'phone', 'Customer 001',
    30, 0, 8, 3, 17, 2,
    6500, 0, 10, 1000, 0, 0, 0, null,
    'Other Laguna towns', 'Returning customer', 'Barkada', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-02-12 07:15:00+08', '2026-02-12 18:00:00+08', '2026-02-05 21:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0212-DP', '2026-02-05 21:00:00+08'::timestamptz from nb
union all
select id, 3750, 'cash', 'balance', 'verified', null, '2026-02-12 07:15:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-03-15', 'completed', 'phone', 'Customer 002',
    15, 0, 4, 2, 8, 1,
    5500, 0, 0, 0, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Referral', 'School / Organization', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-03-15 07:05:00+08', '2026-03-15 18:00:00+08', '2026-02-20 08:15:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0315-DP', '2026-02-20 08:15:00+08'::timestamptz from nb
union all
select id, 2750, 'gcash', 'balance', 'verified', 'SIM-0315-BAL', '2026-03-15 07:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-03-16', 'completed', 'phone', 'Customer 003',
    40, 0, 10, 4, 24, 2,
    8500, 0, 20, 2000, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Facebook', 'Family outing', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-03-16 19:05:00+08', '2026-03-17 06:00:00+08', '2026-03-09 14:45:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0316-DP', '2026-03-09 14:45:00+08'::timestamptz from nb
union all
select id, 5250, 'cash', 'balance', 'verified', null, '2026-03-16 19:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-03-29', 'completed', 'phone', 'Customer 004',
    28, 0, 7, 3, 17, 1,
    6800, 0, 8, 800, 0, 0, 500, 'Gas stove',
    'Metro Manila', 'Facebook', 'Family outing', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-03-29 07:05:00+08', '2026-03-29 18:00:00+08', '2026-03-17 09:45:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0329-DP', '2026-03-17 09:45:00+08'::timestamptz from nb
union all
select id, 4050, 'cash', 'balance', 'verified', null, '2026-03-29 07:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-04-01', 'completed', 'phone', 'Customer 005',
    12, 0, 3, 1, 7, 1,
    8500, 0, 0, 0, 5, 2500, 500, 'Gas stove',
    'Pagsanjan & nearby towns', 'Facebook', 'Reunion', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-04-01 07:30:00+08', '2026-04-01 23:00:00+08', '2026-03-09 09:15:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0401-DP', '2026-03-09 09:15:00+08'::timestamptz from nb
union all
select id, 5750, 'gcash', 'balance', 'verified', 'SIM-0401-BAL', '2026-04-01 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-04-02', 'completed', 'phone', 'Customer 006',
    28, 0, 7, 3, 17, 1,
    6300, 0, 8, 800, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Referral', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-04-02 07:30:00+08', '2026-04-02 18:00:00+08', '2026-03-08 17:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0402-DP', '2026-03-08 17:00:00+08'::timestamptz from nb
union all
select id, 3550, 'cash', 'balance', 'verified', null, '2026-04-02 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-04-04', 'completed', 'phone', 'Customer 007',
    35, 0, 9, 4, 20, 2,
    9500, 0, 15, 1500, 5, 2500, 0, null,
    'Pagsanjan & nearby towns', 'Facebook', 'Barkada', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-04-04 07:05:00+08', '2026-04-04 23:00:00+08', '2026-03-12 14:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0404-DP', '2026-03-12 14:00:00+08'::timestamptz from nb
union all
select id, 6750, 'cash', 'balance', 'verified', null, '2026-04-04 07:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-04-05', 'completed', 'phone', 'Customer 008',
    20, 0, 5, 2, 12, 1,
    5500, 0, 0, 0, 0, 0, 0, null,
    'Other Laguna towns', 'Facebook', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-04-05 07:15:00+08', '2026-04-05 18:00:00+08', '2026-03-30 16:15:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0405-DP', '2026-03-30 16:15:00+08'::timestamptz from nb
union all
select id, 2750, 'cash', 'balance', 'verified', null, '2026-04-05 07:15:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-04-18', 'completed', 'phone', 'Customer 009',
    16, 0, 4, 2, 9, 1,
    6000, 0, 0, 0, 0, 0, 500, 'Gas stove',
    'Pagsanjan & nearby towns', 'Facebook', 'Reunion', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-04-18 07:30:00+08', '2026-04-18 18:00:00+08', '2026-03-31 10:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0418-DP', '2026-03-31 10:00:00+08'::timestamptz from nb
union all
select id, 3250, 'cash', 'balance', 'verified', null, '2026-04-18 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-04-19', 'completed', 'phone', 'Customer 010',
    24, 0, 6, 2, 15, 1,
    6900, 0, 4, 400, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Facebook', 'Barkada', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-04-19 19:05:00+08', '2026-04-20 06:00:00+08', '2026-04-05 16:15:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0419-DP', '2026-04-05 16:15:00+08'::timestamptz from nb
union all
select id, 3650, 'cash', 'balance', 'verified', null, '2026-04-19 19:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-04-24', 'completed', 'phone', 'Customer 011',
    31, 0, 8, 3, 18, 2,
    7600, 0, 11, 1100, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Referral', 'Barkada', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-04-24 19:15:00+08', '2026-04-25 06:00:00+08', '2026-04-01 17:15:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0424-DP', '2026-04-01 17:15:00+08'::timestamptz from nb
union all
select id, 4350, 'cash', 'balance', 'verified', null, '2026-04-24 19:15:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-04-25', 'completed', 'phone', 'Customer 002',
    5, 0, 1, 0, 4, 0,
    8500, 0, 0, 0, 3, 1500, 500, 'Gas stove',
    'Pagsanjan & nearby towns', 'Returning customer', 'Family outing', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-04-25 19:30:00+08', '2026-04-26 09:00:00+08', '2026-04-03 19:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0425-DP', '2026-04-03 19:00:00+08'::timestamptz from nb
union all
select id, 5250, 'cash', 'balance', 'verified', null, '2026-04-25 19:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-05-07', 'completed', 'phone', 'Customer 001',
    30, 0, 8, 3, 17, 2,
    8000, 0, 10, 1000, 0, 0, 500, 'Gas stove',
    'Other Laguna towns', 'Returning customer', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-07 19:30:00+08', '2026-05-08 06:00:00+08', '2026-04-13 11:45:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0507-DP', '2026-04-13 11:45:00+08'::timestamptz from nb
union all
select id, 4750, 'cash', 'balance', 'verified', null, '2026-05-07 19:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-05-08', 'completed', 'phone', 'Customer 012',
    29, 0, 7, 3, 18, 1,
    7400, 0, 9, 900, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Facebook', 'Family outing', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-08 19:15:00+08', '2026-05-09 06:00:00+08', '2026-04-16 14:30:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0508-DP', '2026-04-16 14:30:00+08'::timestamptz from nb
union all
select id, 4150, 'gcash', 'balance', 'verified', 'SIM-0508-BAL', '2026-05-08 19:15:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-05-17', 'completed', 'phone', 'Customer 013',
    37, 0, 9, 4, 22, 2,
    8700, 0, 17, 1700, 3, 1500, 0, null,
    'Pagsanjan & nearby towns', 'Facebook', 'Reunion', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-17 07:15:00+08', '2026-05-17 21:00:00+08', '2026-04-24 15:30:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0517-DP', '2026-04-24 15:30:00+08'::timestamptz from nb
union all
select id, 5950, 'gcash', 'balance', 'verified', 'SIM-0517-BAL', '2026-05-17 07:15:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-05-18', 'completed', 'phone', 'Customer 014',
    12, 0, 3, 1, 7, 1,
    7000, 0, 0, 0, 3, 1500, 0, null,
    'Pagsanjan & nearby towns', 'Facebook', 'Reunion', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-18 07:30:00+08', '2026-05-18 21:00:00+08', '2026-05-06 20:15:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0518-DP', '2026-05-06 20:15:00+08'::timestamptz from nb
union all
select id, 4250, 'cash', 'balance', 'verified', null, '2026-05-18 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-05-23', 'completed', 'phone', 'Customer 013',
    15, 0, 4, 2, 8, 1,
    5500, 0, 0, 0, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Returning customer', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-23 07:30:00+08', '2026-05-23 18:00:00+08', '2026-05-11 09:30:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0523-DP', '2026-05-11 09:30:00+08'::timestamptz from nb
union all
select id, 2750, 'gcash', 'balance', 'verified', 'SIM-0523-BAL', '2026-05-23 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-05-24', 'completed', 'phone', 'Customer 015',
    20, 0, 5, 2, 12, 1,
    6500, 0, 0, 0, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Referral', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-24 19:15:00+08', '2026-05-25 06:00:00+08', '2026-05-04 13:45:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0524-DP', '2026-05-04 13:45:00+08'::timestamptz from nb
union all
select id, 3250, 'gcash', 'balance', 'verified', 'SIM-0524-BAL', '2026-05-24 19:15:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-05-29', 'completed', 'phone', 'Customer 016',
    30, 0, 8, 3, 17, 2,
    7000, 0, 10, 1000, 0, 0, 500, 'Gas stove',
    'Pagsanjan & nearby towns', 'Facebook', 'Reunion', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-29 07:30:00+08', '2026-05-29 18:00:00+08', '2026-05-05 09:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0529-DP', '2026-05-05 09:00:00+08'::timestamptz from nb
union all
select id, 4250, 'cash', 'balance', 'verified', null, '2026-05-29 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-05-30', 'completed', 'phone', 'Customer 017',
    14, 0, 4, 1, 8, 1,
    7000, 0, 0, 0, 0, 0, 500, 'Gas stove',
    'Metro Manila', 'Facebook', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-30 19:05:00+08', '2026-05-31 06:00:00+08', '2026-05-12 10:30:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0530-DP', '2026-05-12 10:30:00+08'::timestamptz from nb
union all
select id, 3750, 'cash', 'balance', 'verified', null, '2026-05-30 19:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-05-31', 'completed', 'phone', 'Customer 018',
    36, 0, 9, 4, 21, 2,
    7600, 0, 16, 1600, 0, 0, 500, 'Gas stove',
    'Pagsanjan & nearby towns', 'Facebook', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-05-31 07:30:00+08', '2026-05-31 18:00:00+08', '2026-05-11 14:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0531-DP', '2026-05-11 14:00:00+08'::timestamptz from nb
union all
select id, 4850, 'gcash', 'balance', 'verified', 'SIM-0531-BAL', '2026-05-31 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-06-15', 'completed', 'phone', 'Customer 019',
    26, 0, 6, 3, 16, 1,
    6100, 0, 6, 600, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Facebook', 'Family outing', 'Simulated data (client interview, Nov 19, 2026); rescheduled due to rain', true, public.gen_checkin_code(),
    '2026-06-15 07:15:00+08', '2026-06-15 18:00:00+08', '2026-06-08 20:30:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0615-DP', '2026-06-08 20:30:00+08'::timestamptz from nb
union all
select id, 3350, 'cash', 'balance', 'verified', null, '2026-06-15 07:15:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-06-21', 'completed', 'phone', 'Customer 012',
    16, 0, 4, 2, 9, 1,
    6500, 0, 0, 0, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Returning customer', 'Barkada', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-06-21 19:05:00+08', '2026-06-22 06:00:00+08', '2026-05-28 15:45:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 3250, 'gcash', 'downpayment', 'verified', 'SIM-0621-DP', '2026-05-28 15:45:00+08'::timestamptz from nb
union all
select id, 3250, 'gcash', 'balance', 'verified', 'SIM-0621-BAL', '2026-06-21 19:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-07-17', 'completed', 'phone', 'Customer 020',
    34, 0, 8, 3, 21, 2,
    6900, 0, 14, 1400, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Referral', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-07-17 07:30:00+08', '2026-07-17 18:00:00+08', '2026-07-10 12:45:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2750, 'gcash', 'downpayment', 'verified', 'SIM-0717-DP', '2026-07-10 12:45:00+08'::timestamptz from nb
union all
select id, 4150, 'cash', 'balance', 'verified', null, '2026-07-17 07:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-09-16', 'completed', 'phone', 'Customer 021',
    29, 0, 7, 3, 18, 1,
    6750, 650, 9, 900, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Walk-by / signage', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-09-16 19:30:00+08', '2026-09-17 06:00:00+08', '2026-08-21 09:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2925, 'gcash', 'downpayment', 'verified', 'SIM-0916-DP', '2026-08-21 09:00:00+08'::timestamptz from nb
union all
select id, 3825, 'cash', 'balance', 'verified', null, '2026-09-16 19:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-09-30', 'completed', 'phone', 'Customer 022',
    8, 0, 2, 1, 5, 0,
    6950, 550, 0, 0, 3, 1500, 500, 'Gas stove',
    'Pagsanjan & nearby towns', 'Facebook', 'Barkada', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-09-30 07:15:00+08', '2026-09-30 21:00:00+08', '2026-09-03 12:45:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2475, 'gcash', 'downpayment', 'verified', 'SIM-0930-DP', '2026-09-03 12:45:00+08'::timestamptz from nb
union all
select id, 4475, 'gcash', 'balance', 'verified', 'SIM-0930-BAL', '2026-09-30 07:15:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-10-16', 'completed', 'phone', 'Customer 023',
    27, 0, 7, 3, 16, 1,
    7050, 650, 7, 700, 0, 0, 500, 'Gas stove',
    'Pagsanjan & nearby towns', 'Facebook', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026); rescheduled due to rain', true, public.gen_checkin_code(),
    '2026-10-16 19:05:00+08', '2026-10-17 06:00:00+08', '2026-09-19 14:30:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2925, 'gcash', 'downpayment', 'verified', 'SIM-1016-DP', '2026-09-19 14:30:00+08'::timestamptz from nb
union all
select id, 4125, 'cash', 'balance', 'verified', null, '2026-10-16 19:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Night Tour' order by id limit 1), '2026-10-28', 'completed', 'phone', 'Customer 024',
    18, 0, 4, 2, 11, 1,
    5850, 650, 0, 0, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Facebook', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-10-28 19:30:00+08', '2026-10-29 06:00:00+08', '2026-10-09 13:15:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2925, 'gcash', 'downpayment', 'verified', 'SIM-1028-DP', '2026-10-09 13:15:00+08'::timestamptz from nb
union all
select id, 2925, 'gcash', 'balance', 'verified', 'SIM-1028-BAL', '2026-10-28 19:30:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-10-30', 'completed', 'phone', 'Customer 025',
    16, 0, 4, 2, 9, 1,
    7450, 550, 0, 0, 4, 2000, 500, 'Gas stove',
    'Pagsanjan & nearby towns', 'Facebook', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-10-30 07:05:00+08', '2026-10-30 22:00:00+08', '2026-10-22 15:00:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2475, 'gcash', 'downpayment', 'verified', 'SIM-1030-DP', '2026-10-22 15:00:00+08'::timestamptz from nb
union all
select id, 4975, 'cash', 'balance', 'verified', null, '2026-10-30 07:05:00+08'::timestamptz from nb;

with nb as (
  insert into public.bookings (package_id, booking_date, status, source, guest_name, total_pax, infants, children, teens, adults, elderly,
    total_amount, discount, extra_pax, extra_pax_fee, extension_hours, extension_fee, other_charges, other_charges_note,
    customer_location, referral_source, occasion, admin_notes, is_simulated, checkin_code, checked_in_at, checked_out_at, created_at)
  values ((select id from public.packages where name = 'Day Tour' order by id limit 1), '2026-11-08', 'completed', 'phone', 'Customer 026',
    18, 0, 4, 2, 11, 1,
    4950, 550, 0, 0, 0, 0, 0, null,
    'Pagsanjan & nearby towns', 'Referral', 'Birthday / Debut / Christening', 'Simulated data (client interview, Nov 19, 2026)', true, public.gen_checkin_code(),
    '2026-11-08 07:30:00+08', '2026-11-08 18:00:00+08', '2026-10-10 12:15:00+08')
  returning id
)
insert into public.payments (booking_id, amount, method, kind, status, reference_no, created_at)
select id, 2475, 'gcash', 'downpayment', 'verified', 'SIM-1108-DP', '2026-10-10 12:15:00+08'::timestamptz from nb
union all
select id, 2475, 'cash', 'balance', 'verified', null, '2026-11-08 07:30:00+08'::timestamptz from nb;

insert into public.expenses (expense_date, category, amount, note, is_simulated) values
  ('2026-01-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-01-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-01-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-01-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-01-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-01-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-02-27', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-02-27', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-02-27', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-02-27', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-02-27', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-02-27', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-03-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-03-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-03-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-03-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-03-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-03-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-04-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-04-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-04-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-04-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-04-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-04-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-05-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-05-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-05-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-05-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-05-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-05-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-06-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-06-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-06-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-06-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-06-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-06-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-07-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-07-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-07-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-07-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-07-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-07-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-08-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-08-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-08-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-08-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-08-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-08-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-09-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-09-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-09-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-09-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-09-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-09-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-10-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-10-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-10-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-10-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-10-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-10-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-11-28', 'Electricity', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-11-28', 'Water', 3000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-11-28', 'Chlorine & pool chemicals', 10000, 'Monthly estimate from client interview (simulated)', true),
  ('2026-11-28', 'Cleaning supplies', 500, 'Monthly estimate from client interview (simulated)', true),
  ('2026-11-28', 'LPG', 1450, 'Monthly estimate from client interview (simulated)', true),
  ('2026-11-28', 'Internet', 1500, 'Monthly estimate from client interview (simulated)', true);

alter table public.bookings enable trigger user;
alter table public.payments enable trigger user;

-- Tsek: dapat 31 bookings, 62 payments, 66 expenses
select
  (select count(*) from public.bookings where is_simulated) as simulated_bookings,
  (select count(*) from public.payments) as payments,
  (select count(*) from public.expenses where is_simulated) as simulated_expenses;

-- Tapos na!

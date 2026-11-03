-- ===========================================================================
-- ResortPro Admin – database setup
-- ---------------------------------------------------------------------------
-- Paano gamitin:
--   1. Buksan ang Supabase dashboard ng project mo → SQL Editor → New query
--   2. I-paste ang buong file na ito, tapos i-click ang "Run".
--   3. Ligtas itong i-run nang paulit-ulit; hindi nito binubura ang data mo.
--
-- Ano ang idinadagdag:
--   • Bagong booking statuses para sa workflow
--     (reserved → confirmed → checked_in → completed, pati no_show)
--   • bookings.admin_notes   – private notes ng admin sa bawat booking
--   • booking_logs           – activity history ng bawat booking
--   • notifications          – real-time notifications (admin at client)
--   • gallery_images + storage bucket "gallery" – photos para sa landing page
--   • Triggers na gumagawa ng notification kapag may bagong booking,
--     bagong payment mula sa client, o bagong verification request
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 0. Helper: admin ba ang naka-login?
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;


-- ---------------------------------------------------------------------------
-- 1. Booking statuses + admin notes
-- ---------------------------------------------------------------------------
do $$
declare
  col_type text;
  col_udt  text;
  c        record;
  v        text;
begin
  select data_type, udt_name into col_type, col_udt
  from information_schema.columns
  where table_schema = 'public' and table_name = 'bookings' and column_name = 'status';

  if col_type = 'USER-DEFINED' then
    -- Enum ang status column: idagdag ang mga bagong value.
    foreach v in array array['reserved','confirmed','fully_paid','checked_in','completed','cancelled','no_show'] loop
      execute format('alter type public.%I add value if not exists %L', col_udt, v);
    end loop;
  else
    -- Text ang status column: palitan ang lumang check constraint (kung meron).
    for c in
      select con.conname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace n on n.oid = rel.relnamespace
      where n.nspname = 'public'
        and rel.relname = 'bookings'
        and con.contype = 'c'
        and pg_get_constraintdef(con.oid) ilike '%status%'
    loop
      execute format('alter table public.bookings drop constraint %I', c.conname);
    end loop;

    alter table public.bookings
      add constraint bookings_status_check
      check (status in ('reserved','confirmed','fully_paid','checked_in','completed','cancelled','no_show'))
      not valid;
  end if;
end $$;

alter table public.bookings add column if not exists admin_notes text;


-- ---------------------------------------------------------------------------
-- 2. Booking activity log
-- ---------------------------------------------------------------------------
create table if not exists public.booking_logs (
  id          bigint generated always as identity primary key,
  booking_id  text not null,
  action      text not null,
  from_status text,
  to_status   text,
  note        text,
  actor_id    uuid default auth.uid(),
  created_at  timestamptz not null default now()
);
create index if not exists booking_logs_booking_idx
  on public.booking_logs (booking_id, created_at desc);

alter table public.booking_logs enable row level security;

drop policy if exists "admins manage booking logs" on public.booking_logs;
create policy "admins manage booking logs" on public.booking_logs
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ---------------------------------------------------------------------------
-- 3. Notifications
--    audience = 'admin'  → para sa lahat ng admin
--    audience = 'client' → para sa isang client (recipient_id)
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id           bigint generated always as identity primary key,
  audience     text not null default 'admin' check (audience in ('admin','client')),
  recipient_id uuid,
  type         text not null,
  data         jsonb not null default '{}'::jsonb,
  ref_id       text,
  is_read      boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists notifications_lookup_idx
  on public.notifications (audience, recipient_id, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists "admins manage notifications" on public.notifications;
create policy "admins manage notifications" on public.notifications
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "clients read own notifications" on public.notifications;
create policy "clients read own notifications" on public.notifications
  for select to authenticated
  using (audience = 'client' and recipient_id = auth.uid());

drop policy if exists "clients update own notifications" on public.notifications;
create policy "clients update own notifications" on public.notifications
  for update to authenticated
  using (audience = 'client' and recipient_id = auth.uid())
  with check (audience = 'client' and recipient_id = auth.uid());

-- Real-time para lumabas agad ang bagong notification
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- 4. Automatic notifications para sa admin (triggers)
-- ---------------------------------------------------------------------------
create or replace function public.client_display_name(p_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(google_display_name), ''),
    nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''),
    'Client'
  )
  from public.profiles where id = p_id;
$$;

-- Bagong booking
create or replace function public.notify_admin_new_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pkg text;
begin
  select name into pkg from public.packages where id = new.package_id;
  insert into public.notifications (audience, type, data, ref_id)
  values (
    'admin',
    'new_booking',
    jsonb_build_object(
      'package', pkg,
      'client', public.client_display_name(new.client_id),
      'date', new.booking_date,
      'pax', new.total_pax
    ),
    new.id::text
  );
  return new;
end $$;

drop trigger if exists trg_notify_new_booking on public.bookings;
create trigger trg_notify_new_booking
  after insert on public.bookings
  for each row execute function public.notify_admin_new_booking();

-- Bagong payment mula sa client (hindi kasama ang ni-record ng admin)
create or replace function public.notify_admin_client_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  b record;
  pkg text;
begin
  if new.received_by is not null then
    return new;
  end if;
  select * into b from public.bookings where id = new.booking_id;
  select name into pkg from public.packages where id = b.package_id;
  insert into public.notifications (audience, type, data, ref_id)
  values (
    'admin',
    'client_payment',
    jsonb_build_object(
      'client', public.client_display_name(b.client_id),
      'package', pkg,
      'amount', new.amount,
      'method', new.method,
      'kind', new.kind
    ),
    new.booking_id::text
  );
  return new;
end $$;

drop trigger if exists trg_notify_client_payment on public.payments;
create trigger trg_notify_client_payment
  after insert on public.payments
  for each row execute function public.notify_admin_client_payment();

-- Bagong verification request (nag-submit ng ID ang client)
create or replace function public.notify_admin_verification_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.verification_status = 'pending'
     and old.verification_status is distinct from 'pending'
     and coalesce(new.role, 'client') = 'client' then
    insert into public.notifications (audience, type, data, ref_id)
    values (
      'admin',
      'verification_request',
      jsonb_build_object('client', public.client_display_name(new.id), 'id_type', new.government_id_type),
      new.id::text
    );
  end if;
  return new;
end $$;

drop trigger if exists trg_notify_verification_request on public.profiles;
create trigger trg_notify_verification_request
  after update of verification_status on public.profiles
  for each row execute function public.notify_admin_verification_request();


-- ---------------------------------------------------------------------------
-- 5. Gallery (photos sa landing page)
-- ---------------------------------------------------------------------------
create table if not exists public.gallery_images (
  id              bigint generated always as identity primary key,
  storage_path    text not null,
  image_url       text not null,
  caption         text,
  sort_order      int not null default 0,
  show_on_landing boolean not null default true,
  created_at      timestamptz not null default now()
);

alter table public.gallery_images enable row level security;

drop policy if exists "anyone can view landing gallery" on public.gallery_images;
create policy "anyone can view landing gallery" on public.gallery_images
  for select to anon, authenticated
  using (show_on_landing or public.is_admin());

drop policy if exists "admins manage gallery" on public.gallery_images;
create policy "admins manage gallery" on public.gallery_images
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Storage bucket (public, para makita ng client app ang photos)
insert into storage.buckets (id, name, public)
values ('gallery', 'gallery', true)
on conflict (id) do update set public = true;

drop policy if exists "gallery public read" on storage.objects;
create policy "gallery public read" on storage.objects
  for select using (bucket_id = 'gallery');

drop policy if exists "gallery admin insert" on storage.objects;
create policy "gallery admin insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'gallery' and public.is_admin());

drop policy if exists "gallery admin update" on storage.objects;
create policy "gallery admin update" on storage.objects
  for update to authenticated
  using (bucket_id = 'gallery' and public.is_admin());

drop policy if exists "gallery admin delete" on storage.objects;
create policy "gallery admin delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'gallery' and public.is_admin());


-- ---------------------------------------------------------------------------
-- 6. Permissions ng admin sa bookings at packages
--    (para gumana ang workflow, admin notes, at pag-edit ng package)
-- ---------------------------------------------------------------------------
drop policy if exists "admins update bookings" on public.bookings;
create policy "admins update bookings" on public.bookings
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins update packages" on public.packages;
create policy "admins update packages" on public.packages
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Tapos na! Bumalik sa admin app at i-refresh.


-- ===========================================================================
-- PART 2 (dinagdag Nov 3, 2026): proof of payment, walk-in bookings,
-- blocked dates, seasonal pricing. Ligtas pa ring i-run nang paulit-ulit.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 7. Proof of payment
--    Ang bayad na galing sa client ay laging 'pending' hanggang i-verify
--    ng admin. Ang lumang payments ay itinuturing na 'verified'.
-- ---------------------------------------------------------------------------
alter table public.payments add column if not exists status        text not null default 'verified';
alter table public.payments add column if not exists reference_no  text;
alter table public.payments add column if not exists proof_path    text;
alter table public.payments add column if not exists reviewed_by   uuid;
alter table public.payments add column if not exists reviewed_at   timestamptz;
alter table public.payments add column if not exists reject_reason text;
alter table public.payments add column if not exists created_at    timestamptz not null default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payments_status_check') then
    alter table public.payments
      add constraint payments_status_check check (status in ('pending','verified','rejected'));
  end if;
end $$;

-- Hindi kayang i-mark ng client na "verified" ang sarili niyang bayad.
create or replace function public.payments_force_pending()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    new.status      := 'pending';
    new.received_by := null;
    new.reviewed_by := null;
    new.reviewed_at := null;
  end if;
  return new;
end $$;

drop trigger if exists trg_payments_force_pending on public.payments;
create trigger trg_payments_force_pending
  before insert on public.payments
  for each row execute function public.payments_force_pending();

drop policy if exists "admins insert payments" on public.payments;
create policy "admins insert payments" on public.payments
  for insert to authenticated with check (public.is_admin());

drop policy if exists "admins update payments" on public.payments;
create policy "admins update payments" on public.payments
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Private bucket para sa screenshots ng bayad
insert into storage.buckets (id, name, public)
values ('payment-proofs', 'payment-proofs', false)
on conflict (id) do nothing;

drop policy if exists "proof owner upload" on storage.objects;
create policy "proof owner upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "proof owner or admin read" on storage.objects;
create policy "proof owner or admin read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'payment-proofs'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );

drop policy if exists "proof admin delete" on storage.objects;
create policy "proof admin delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'payment-proofs' and public.is_admin());

-- Notification sa admin: may in-upload na proof of payment ang client
create or replace function public.notify_admin_client_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  b record;
  pkg text;
begin
  if new.received_by is not null or public.is_admin() then
    return new;
  end if;
  select * into b from public.bookings where id = new.booking_id;
  select name into pkg from public.packages where id = b.package_id;
  insert into public.notifications (audience, type, data, ref_id)
  values (
    'admin',
    'client_payment',
    jsonb_build_object(
      'client', coalesce(public.client_display_name(b.client_id), b.guest_name),
      'package', pkg,
      'amount', new.amount,
      'method', new.method,
      'kind', new.kind,
      'reference_no', new.reference_no
    ),
    new.booking_id::text
  );
  return new;
end $$;


-- ---------------------------------------------------------------------------
-- 8. Walk-in at phone bookings (gawa ng admin, pwedeng walang account)
-- ---------------------------------------------------------------------------
alter table public.bookings add column if not exists source      text not null default 'online';
alter table public.bookings add column if not exists guest_name  text;
alter table public.bookings add column if not exists guest_phone text;
alter table public.bookings alter column client_id drop not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bookings_source_check') then
    alter table public.bookings
      add constraint bookings_source_check check (source in ('online','walk_in','phone'));
  end if;
end $$;

drop policy if exists "admins insert bookings" on public.bookings;
create policy "admins insert bookings" on public.bookings
  for insert to authenticated with check (public.is_admin());

drop policy if exists "admins read bookings" on public.bookings;
create policy "admins read bookings" on public.bookings
  for select to authenticated using (public.is_admin());

-- Walang "new booking" notification kapag admin mismo ang gumawa
create or replace function public.notify_admin_new_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pkg text;
begin
  if public.is_admin() then
    return new;
  end if;
  select name into pkg from public.packages where id = new.package_id;
  insert into public.notifications (audience, type, data, ref_id)
  values (
    'admin',
    'new_booking',
    jsonb_build_object(
      'package', pkg,
      'client', coalesce(public.client_display_name(new.client_id), new.guest_name),
      'date', new.booking_date,
      'pax', new.total_pax
    ),
    new.id::text
  );
  return new;
end $$;


-- ---------------------------------------------------------------------------
-- 9. Blocked dates (maintenance, private event, fully booked)
--    package_id = null → sarado ang buong resort sa araw na iyon
-- ---------------------------------------------------------------------------
create table if not exists public.blocked_dates (
  id          bigint generated always as identity primary key,
  block_date  date not null,
  package_id  bigint,
  reason      text,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now()
);
create index if not exists blocked_dates_date_idx on public.blocked_dates (block_date);

alter table public.blocked_dates enable row level security;

drop policy if exists "anyone can view blocked dates" on public.blocked_dates;
create policy "anyone can view blocked dates" on public.blocked_dates
  for select to anon, authenticated using (true);

drop policy if exists "admins manage blocked dates" on public.blocked_dates;
create policy "admins manage blocked dates" on public.blocked_dates
  for all to authenticated using (public.is_admin()) with check (public.is_admin());


-- ---------------------------------------------------------------------------
-- 10. Seasonal pricing (weekend, holiday, peak season)
--     adjust_type: 'percent'      → +/- porsyento sa base price
--                  'fixed_amount' → +/- halaga sa base price
--                  'set_price'    → eksaktong presyo
--     days_of_week: 1 = Lunes ... 7 = Linggo (null = kahit anong araw)
--     Kapag maraming tugma, ang may pinakamataas na priority ang gagamitin.
-- ---------------------------------------------------------------------------
create table if not exists public.pricing_rules (
  id            bigint generated always as identity primary key,
  name          text not null,
  package_id    bigint,
  start_date    date,
  end_date      date,
  days_of_week  int[],
  adjust_type   text not null default 'percent' check (adjust_type in ('percent','fixed_amount','set_price')),
  value         numeric not null default 0,
  priority      int not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

alter table public.pricing_rules enable row level security;

drop policy if exists "anyone can view pricing rules" on public.pricing_rules;
create policy "anyone can view pricing rules" on public.pricing_rules
  for select to anon, authenticated using (true);

drop policy if exists "admins manage pricing rules" on public.pricing_rules;
create policy "admins manage pricing rules" on public.pricing_rules
  for all to authenticated using (public.is_admin()) with check (public.is_admin());


-- ---------------------------------------------------------------------------
-- 11. Presyo at availability (ginagamit ng user app at ng admin)
-- ---------------------------------------------------------------------------
create or replace function public.price_for(p_package_id bigint, p_date date)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  base numeric;
  r    record;
  dow  int := extract(isodow from p_date)::int;
begin
  select price into base from public.packages where id = p_package_id;
  if base is null then
    return null;
  end if;

  select * into r
  from public.pricing_rules
  where is_active
    and (package_id is null or package_id = p_package_id)
    and (start_date is null or p_date >= start_date)
    and (end_date is null or p_date <= end_date)
    and (days_of_week is null or cardinality(days_of_week) = 0 or dow = any(days_of_week))
  order by priority desc, (package_id is not null) desc, id desc
  limit 1;

  if not found then
    return base;
  end if;

  if r.adjust_type = 'percent' then
    return round(base * (1 + r.value / 100.0));
  elsif r.adjust_type = 'fixed_amount' then
    return greatest(0, base + r.value);
  else
    return r.value;
  end if;
end $$;

create or replace function public.check_availability(
  p_package_id bigint,
  p_date date,
  p_exclude_booking text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  block_reason text;
begin
  select coalesce(reason, '') into block_reason
  from public.blocked_dates
  where block_date = p_date and (package_id is null or package_id = p_package_id)
  limit 1;
  if found then
    return jsonb_build_object('available', false, 'reason', 'blocked', 'note', block_reason);
  end if;

  if exists (
    select 1 from public.bookings
    where package_id = p_package_id
      and booking_date = p_date
      and status not in ('cancelled', 'no_show')
      and (p_exclude_booking is null or id::text <> p_exclude_booking)
  ) then
    return jsonb_build_object('available', false, 'reason', 'booked');
  end if;

  return jsonb_build_object('available', true, 'price', public.price_for(p_package_id, p_date));
end $$;

grant execute on function public.price_for(bigint, date) to anon, authenticated;
grant execute on function public.check_availability(bigint, date, text) to anon, authenticated;

-- Bantay laban sa double booking at blocked dates (kahit sino ang mag-book).
-- Para sa client, ang server din ang nagtatakda ng tamang presyo.
create or replace function public.bookings_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' and not public.is_admin() then
    new.total_amount := coalesce(public.price_for(new.package_id, new.booking_date), new.total_amount);
    new.status := 'reserved';
    new.source := 'online';
  end if;

  if new.status in ('cancelled', 'no_show') then
    return new;
  end if;

  -- Walang binago sa petsa/package at aktibo na dati: hayaan.
  if tg_op = 'UPDATE'
     and new.booking_date is not distinct from old.booking_date
     and new.package_id is not distinct from old.package_id
     and old.status not in ('cancelled', 'no_show') then
    return new;
  end if;

  if exists (
    select 1 from public.blocked_dates
    where block_date = new.booking_date
      and (package_id is null or package_id = new.package_id)
  ) then
    raise exception 'DATE_BLOCKED: This date is not available for booking.';
  end if;

  if exists (
    select 1 from public.bookings
    where package_id = new.package_id
      and booking_date = new.booking_date
      and status not in ('cancelled', 'no_show')
      and id <> new.id
  ) then
    raise exception 'DATE_TAKEN: This date is already booked for this package.';
  end if;

  return new;
end $$;

drop trigger if exists trg_bookings_guard on public.bookings;
create trigger trg_bookings_guard
  before insert or update of booking_date, package_id, status on public.bookings
  for each row execute function public.bookings_guard();

-- Tapos na ang Part 2!

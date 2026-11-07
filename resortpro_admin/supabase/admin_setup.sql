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

-- Pwedeng mag-record ng bayad ang client para sa SARILI niyang booking lang.
-- (Laging "pending" ito dahil sa trigger na payments_force_pending; admin ang magve-verify.)
drop policy if exists "clients insert own payments" on public.payments;
create policy "clients insert own payments" on public.payments
  for insert to authenticated
  with check (
    exists (
      select 1 from public.bookings b
      where b.id = payments.booking_id
        and b.client_id = auth.uid()
    )
  );

-- Nakikita ng client ang mga bayad sa sarili niyang bookings (para sa My Bookings at receipts).
drop policy if exists "clients read own payments" on public.payments;
create policy "clients read own payments" on public.payments
  for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.bookings b
      where b.id = payments.booking_id
        and b.client_id = auth.uid()
    )
  );

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


-- ===========================================================================
-- PART 3 (dinagdag Nov 4, 2026): Account page ng client
--   • username (pwedeng palitan) at profile picture
-- ===========================================================================

alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists avatar_url text;

-- Walang dalawang account na pareho ang username (hindi case-sensitive).
create unique index if not exists profiles_username_unique
  on public.profiles (lower(username))
  where username is not null;

-- Public na bucket para sa profile pictures (bawat user, sariling folder lang).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "avatars public read" on storage.objects;
create policy "avatars public read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars own upload" on storage.objects;
create policy "avatars own upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars own update" on storage.objects;
create policy "avatars own update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars own delete" on storage.objects;
create policy "avatars own delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Delete account (ginagamit ng "Delete account" sa Account page ng app)
--   • Hindi pwede kapag may paparating pang aktibong booking.
--   • Hindi binubura ang lumang bookings/bayad (kailangan ng resort sa records);
--     tinatanggal lang ang koneksyon nila sa account at iniiwan ang pangalan.
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid    uuid := auth.uid();
  v_name text;
begin
  if uid is null then
    raise exception 'NOT_SIGNED_IN';
  end if;
  if public.is_admin() then
    raise exception 'ADMIN_ACCOUNT: Admin accounts cannot be deleted from the app.';
  end if;
  if exists (
    select 1 from public.bookings
    where client_id = uid
      and status::text in ('reserved', 'confirmed', 'fully_paid', 'checked_in')
      and booking_date >= current_date
  ) then
    raise exception 'HAS_ACTIVE_BOOKING: Cancel or finish your upcoming booking first.';
  end if;

  select coalesce(
           nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''),
           username)
    into v_name
    from public.profiles where id = uid;

  update public.bookings
     set guest_name = coalesce(guest_name, v_name, 'Deleted account'),
         client_id  = null
   where client_id = uid;

  delete from public.notifications where audience = 'client' and recipient_id = uid;
  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;
end $$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Tapos na ang Part 3!


-- ===========================================================================
-- PART 4 (dinagdag Nov 5, 2026): Delete account – pati litrato ng ID
--   Pinapayagan ang client na burahin ang sarili niyang ID photo sa storage
--   (ginagamit ng "Delete account" bago burahin ang account).
-- ===========================================================================
drop policy if exists "government ids own delete" on storage.objects;
create policy "government ids own delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'government-ids' and (storage.foldername(name))[1] = auth.uid()::text);

-- Tapos na ang Part 4!


-- ===========================================================================
-- PART 5 (dinagdag Nov 6, 2026): I-link ang walk-in booking sa account
--   • Bawat booking na walang account (walk-in/phone) ay may "claim code"
--     na nakalagay sa resibo.
--   • Kapag gumawa ng account ang guest, ita-type niya ang code sa app
--     at mapupunta sa Bookings at My Receipt niya ang booking.
-- ===========================================================================
alter table public.bookings add column if not exists claim_code text;
create unique index if not exists bookings_claim_code_unique
  on public.bookings (claim_code) where claim_code is not null;

-- 8 letra/numero, walang nakakalitong O/0 at I/1 (hal. K7QM4XPA)
create or replace function public.gen_claim_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code  text;
begin
  loop
    code := '';
    for i in 1..8 loop
      code := code || substr(chars, 1 + floor(random() * length(chars))::int, 1);
    end loop;
    exit when not exists (select 1 from public.bookings where claim_code = code);
  end loop;
  return code;
end $$;

-- May code ang booking na walang account; nawawala ang code kapag na-link na.
create or replace function public.bookings_claim_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.client_id is not null then
    new.claim_code := null;
  elsif new.claim_code is null then
    new.claim_code := public.gen_claim_code();
  end if;
  return new;
end $$;

drop trigger if exists trg_bookings_claim_code on public.bookings;
create trigger trg_bookings_claim_code
  before insert or update of client_id on public.bookings
  for each row execute function public.bookings_claim_code();

-- Bigyan ng code ang mga dating walk-in na wala pang account.
update public.bookings
   set claim_code = public.gen_claim_code()
 where client_id is null and claim_code is null;

-- Ginagamit ng app: i-link ang booking sa naka-login na account gamit ang code.
create or replace function public.claim_booking(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid  uuid := auth.uid();
  code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  b    record;
begin
  if uid is null then
    raise exception 'NOT_SIGNED_IN';
  end if;
  if length(code) <> 8 then
    raise exception 'INVALID_CODE';
  end if;

  select * into b
    from public.bookings
   where claim_code = code and client_id is null
   for update;
  if not found then
    raise exception 'INVALID_CODE';
  end if;

  update public.bookings set client_id = uid where id = b.id;

  begin
    insert into public.booking_logs (booking_id, action, note)
    values (b.id::text, 'claimed', 'Linked to the guest''s app account using the receipt code');
  exception when others then null;
  end;

  return jsonb_build_object('booking_id', b.id, 'booking_date', b.booking_date);
end $$;

revoke all on function public.claim_booking(text) from public, anon;
grant execute on function public.claim_booking(text) to authenticated;

-- Tapos na ang Part 5!


-- ===========================================================================
-- PART 6 (dinagdag Nov 6, 2026): Iisang lugar ang buong resort
--   Private resort ito, kaya magkasalungat ang dalawang booking kapag
--   pareho ang petsa at nagsasabay ang oras:
--     • Day Tour + Overnight sa iisang petsa → PWEDE (magkaibang oras)
--     • Day Tour + Function Hall (Day Tour hours) → BAWAL (sabay)
--     • Function Hall 22 Hours → kinukuha ang buong araw at gabi
-- ===========================================================================

-- Anong bahagi ng araw ang ginagamit ng package: 'day' at/o 'night'
create or replace function public.package_slots(p_package_id bigint)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  p     record;
  s     text[] := '{}';
  st    time;
  en    time;
begin
  select * into p from public.packages where id = p_package_id;
  if not found then
    return array['day', 'night'];
  end if;

  begin
    st := p.start_time::text::time;
    en := p.end_time::text::time;
  exception when others then
    st := null;
    en := null;
  end;

  if st is null or en is null then
    -- Walang oras na nakalagay: hulaan mula sa pangalan.
    if p.name ilike '%22%' then return array['day', 'night']; end if;
    if p.name ilike '%overnight%' then return array['night']; end if;
    return array['day'];
  end if;

  if st < time '17:00' then s := s || 'day'::text; end if;
  if en <= st or st >= time '17:00' then s := s || 'night'::text; end if;
  if cardinality(s) = 0 then s := array['day']; end if;
  return s;
end $$;

grant execute on function public.package_slots(bigint) to anon, authenticated;

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
  clash        text;
begin
  select coalesce(reason, '') into block_reason
  from public.blocked_dates
  where block_date = p_date and (package_id is null or package_id = p_package_id)
  limit 1;
  if found then
    return jsonb_build_object('available', false, 'reason', 'blocked', 'note', block_reason);
  end if;

  select pk.name into clash
  from public.bookings b
  left join public.packages pk on pk.id = b.package_id
  where b.booking_date = p_date
    and b.status::text not in ('cancelled', 'no_show')
    and (p_exclude_booking is null or b.id::text <> p_exclude_booking)
    and public.package_slots(b.package_id) && public.package_slots(p_package_id)
  limit 1;
  if found then
    return jsonb_build_object('available', false, 'reason', 'booked', 'note', coalesce(clash, ''));
  end if;

  return jsonb_build_object('available', true, 'price', public.price_for(p_package_id, p_date));
end $$;

grant execute on function public.check_availability(bigint, date, text) to anon, authenticated;

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

  if new.status::text in ('cancelled', 'no_show') then
    return new;
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

-- Tapos na ang Part 6!


-- ===========================================================================
-- PART 7 (dinagdag Nov 6, 2026): Litrato mula sa Google para sa admin
--   Sine-save ng app ang Google profile picture ng client, para makita ito
--   ng admin (hal. sa New Walk-In / Phone Booking) kahit walang sariling litrato.
-- ===========================================================================
alter table public.profiles add column if not exists google_avatar_url text;

-- Tapos na ang Part 7!


-- ===========================================================================
-- PART 8 (dinagdag Nov 6, 2026): QR check-in / check-out
--   • Bawat booking ay may QR code (checkin_code) na ini-scan ng staff.
--   • Unang scan = IN (kailangang bayad na ang balanse), pangalawa = OUT.
--   • Kapag late ang OUT, may multa ayon sa resort_settings (₱ kada oras,
--     may palugit na 10 minuto), na idinadagdag sa total ng booking.
--   • Tapos lang ang stay (completed) kapag nasagutan ang survey.
-- ===========================================================================

-- Mga patakaran na nababago ng admin (iisang row lang)
create table if not exists public.resort_settings (
  id                   int primary key default 1 check (id = 1),
  late_fee_per_hour    numeric not null default 500,
  late_grace_minutes   int     not null default 10,
  updated_at           timestamptz not null default now()
);
insert into public.resort_settings (id) values (1) on conflict (id) do nothing;
-- Kinumpirma ng resort (Nov 6, 2026): ₱500 kada oras ng extension, 10 minutong palugit.
alter table public.resort_settings alter column late_grace_minutes set default 10;

alter table public.resort_settings enable row level security;
drop policy if exists "anyone can read resort settings" on public.resort_settings;
create policy "anyone can read resort settings" on public.resort_settings
  for select to anon, authenticated using (true);
drop policy if exists "admins update resort settings" on public.resort_settings;
create policy "admins update resort settings" on public.resort_settings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Mga bagong column sa bookings
alter table public.bookings add column if not exists checkin_code   text;
alter table public.bookings add column if not exists checked_in_at  timestamptz;
alter table public.bookings add column if not exists checked_out_at timestamptz;
alter table public.bookings add column if not exists late_minutes   int not null default 0;
alter table public.bookings add column if not exists late_fee       numeric not null default 0;
create unique index if not exists bookings_checkin_code_unique
  on public.bookings (checkin_code) where checkin_code is not null;

create or replace function public.gen_checkin_code()
returns text language plpgsql volatile set search_path = public as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code  text;
begin
  loop
    code := '';
    for i in 1..10 loop
      code := code || substr(chars, 1 + floor(random() * length(chars))::int, 1);
    end loop;
    exit when not exists (select 1 from public.bookings where checkin_code = code);
  end loop;
  return code;
end $$;

create or replace function public.bookings_checkin_code()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.checkin_code is null then
    new.checkin_code := public.gen_checkin_code();
  end if;
  return new;
end $$;

drop trigger if exists trg_bookings_checkin_code on public.bookings;
create trigger trg_bookings_checkin_code
  before insert on public.bookings
  for each row execute function public.bookings_checkin_code();

update public.bookings set checkin_code = public.gen_checkin_code() where checkin_code is null;

-- Survey pagkatapos ng stay
create table if not exists public.booking_surveys (
  id           bigint generated always as identity primary key,
  booking_id   text not null,
  overall      int  not null check (overall between 1 and 5),
  cleanliness  int  check (cleanliness between 1 and 5),
  staff        int  check (staff between 1 and 5),
  facilities   int  check (facilities between 1 and 5),
  comments     text,
  answered_by  text not null default 'guest' check (answered_by in ('guest', 'staff')),
  submitted_by uuid default auth.uid(),
  created_at   timestamptz not null default now()
);
create unique index if not exists booking_surveys_one_per_booking on public.booking_surveys (booking_id);

alter table public.booking_surveys enable row level security;
drop policy if exists "admins read surveys" on public.booking_surveys;
create policy "admins read surveys" on public.booking_surveys
  for select to authenticated using (public.is_admin());
drop policy if exists "clients read own surveys" on public.booking_surveys;
create policy "clients read own surveys" on public.booking_surveys
  for select to authenticated
  using (exists (select 1 from public.bookings b where b.id::text = booking_surveys.booking_id and b.client_id = auth.uid()));

-- Kailan dapat lumabas ang guest (oras ng Asia/Manila)
create or replace function public.booking_end_at(p_booking_date date, p_package_id bigint)
returns timestamptz language plpgsql stable security definer set search_path = public as $$
declare
  st time;
  en time;
begin
  begin
    select start_time::text::time, end_time::text::time into st, en
      from public.packages where id = p_package_id;
  exception when others then
    st := null; en := null;
  end;
  if en is null then
    return ((p_booking_date + 1)::timestamp + time '06:00') at time zone 'Asia/Manila';
  end if;
  if st is not null and en <= st then
    return ((p_booking_date + 1)::timestamp + en) at time zone 'Asia/Manila';
  end if;
  return (p_booking_date::timestamp + en) at time zone 'Asia/Manila';
end $$;

-- Ang pag-scan: IN o OUT. Admin lang.
create or replace function public.booking_scan(p_code text, p_booking_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  code     text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  b        record;
  paid     numeric;
  balance  numeric;
  ends     timestamptz;
  late     int := 0;
  fee      numeric := 0;
  s        record;
  today    date := (now() at time zone 'Asia/Manila')::date;
begin
  if not public.is_admin() then
    raise exception 'NOT_ADMIN';
  end if;

  if p_booking_id is not null then
    select * into b from public.bookings where id::text = p_booking_id for update;
  else
    if code like 'AGH%' and length(code) > 10 then code := substr(code, 4); end if;
    select * into b from public.bookings where checkin_code = code for update;
  end if;
  if not found then
    raise exception 'CODE_NOT_FOUND';
  end if;

  select coalesce(sum(amount), 0) into paid
    from public.payments
   where booking_id::text = b.id::text and coalesce(status, 'verified') = 'verified';
  balance := greatest(0, coalesce(b.total_amount, 0) - paid);

  -- Hindi pa naka-in: IN
  if b.checked_in_at is null then
    if b.status::text in ('cancelled', 'no_show', 'completed') then
      raise exception 'BOOKING_INACTIVE';
    end if;
    if b.status::text = 'reserved' then
      raise exception 'NOT_CONFIRMED';
    end if;
    if b.booking_date > today then
      raise exception 'TOO_EARLY:%', b.booking_date;
    end if;
    if public.booking_end_at(b.booking_date, b.package_id) < now() then
      raise exception 'BOOKING_ENDED';
    end if;
    if balance > 0.01 then
      raise exception 'BALANCE_DUE:%', balance;
    end if;

    update public.bookings
       set checked_in_at = now(), status = 'checked_in'
     where id = b.id;
    insert into public.booking_logs (booking_id, action, from_status, to_status, note)
    values (b.id::text, 'checked_in', b.status::text, 'checked_in', 'QR scan');
    return jsonb_build_object('action', 'checked_in', 'booking_id', b.id, 'balance', 0);
  end if;

  -- Naka-in pa: OUT (may multa kapag late)
  if b.checked_out_at is null then
    select * into s from public.resort_settings where id = 1;
    ends := public.booking_end_at(b.booking_date, b.package_id);
    late := greatest(0, floor(extract(epoch from (now() - ends)) / 60)::int);
    if late > coalesce(s.late_grace_minutes, 10) then
      fee := ceil(late / 60.0) * coalesce(s.late_fee_per_hour, 500);
    else
      late := 0;
    end if;

    update public.bookings
       set checked_out_at = now(),
           late_minutes   = late,
           late_fee       = fee,
           total_amount   = coalesce(total_amount, 0) + fee
     where id = b.id;
    insert into public.booking_logs (booking_id, action, note)
    values (b.id::text, 'checked_out',
            case when fee > 0 then 'QR scan · late ' || late || ' min · fee ' || fee else 'QR scan · on time' end);
    return jsonb_build_object('action', 'checked_out', 'booking_id', b.id,
                              'late_minutes', late, 'late_fee', fee, 'balance', balance + fee);
  end if;

  -- Naka-out na
  return jsonb_build_object(
    'action', case when b.status::text = 'completed' then 'completed' else 'awaiting_survey' end,
    'booking_id', b.id, 'late_minutes', b.late_minutes, 'late_fee', b.late_fee, 'balance', balance);
end $$;

revoke all on function public.booking_scan(text, text) from public, anon;
grant execute on function public.booking_scan(text, text) to authenticated;

-- Sagutin ang survey: guest (sariling booking) o staff. Saka magiging "completed".
create or replace function public.submit_booking_survey(
  p_booking_id  text,
  p_overall     int,
  p_cleanliness int default null,
  p_staff       int default null,
  p_facilities  int default null,
  p_comments    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b       record;
  paid    numeric;
  balance numeric;
  admin   boolean := public.is_admin();
begin
  select * into b from public.bookings where id::text = p_booking_id for update;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if not admin and (auth.uid() is null or b.client_id is distinct from auth.uid()) then
    raise exception 'NOT_ALLOWED';
  end if;
  if b.checked_out_at is null then raise exception 'NOT_CHECKED_OUT'; end if;
  if exists (select 1 from public.booking_surveys where booking_id = p_booking_id) then
    raise exception 'ALREADY_ANSWERED';
  end if;

  select coalesce(sum(amount), 0) into paid
    from public.payments
   where booking_id::text = b.id::text and coalesce(status, 'verified') = 'verified';
  balance := greatest(0, coalesce(b.total_amount, 0) - paid);
  if balance > 0.01 then
    raise exception 'BALANCE_DUE:%', balance;
  end if;

  insert into public.booking_surveys (booking_id, overall, cleanliness, staff, facilities, comments, answered_by)
  values (p_booking_id, p_overall, p_cleanliness, p_staff, p_facilities,
          nullif(trim(coalesce(p_comments, '')), ''), case when admin then 'staff' else 'guest' end);

  update public.bookings set status = 'completed' where id = b.id;
  insert into public.booking_logs (booking_id, action, from_status, to_status, note)
  values (b.id::text, 'survey', b.status::text, 'completed', 'Check-out survey answered (' || p_overall || '/5)');
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.submit_booking_survey(text, int, int, int, int, text) from public, anon;
grant execute on function public.submit_booking_survey(text, int, int, int, int, text) to authenticated;

-- Tapos na ang Part 8!


-- ===========================================================================
-- PART 9 (dinagdag Nov 6, 2026): 50% downpayment bago ma-confirm
--   Hindi ma-co-confirm ang booking hangga't walang VERIFIED na bayad na
--   hindi bababa sa 50% ng total (policy #1 ng resort).
-- ===========================================================================
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

-- Tapos na ang Part 9!


-- ===========================================================================
-- PART 10 (dinagdag Nov 7, 2026): Mga package ayon sa Pool Agreement,
-- at cancellation + refund
--   Policy #6–#8 ng resort (kinumpirma Nov 7, 2026):
--     • Cancel BAGO ang mismong araw ng booking (kahit sa loob ng 5 araw bago)
--       → refund ng KALAHATI ng 50% reservation fee (hal. ₱6,500 → fee ₱3,250 → refund ₱1,625)
--     • Hindi nakapag-cancel bago ang araw ng booking → walang refund
--     • Ang ibinayad na lampas sa reservation fee (hal. bayad na lahat) ay ibinabalik
-- ===========================================================================

-- ---- Mga pangalan ng package (ayon sa papel ng resort) ----
-- Ang dating "Overnight" (7:00 PM – 6:00 AM) ay "Night Tour" na.
update public.packages set name = 'Night Tour'
 where name = 'Overnight'
   and not exists (select 1 from public.packages where name = 'Night Tour');

-- ---- Refund requests ----
create table if not exists public.refund_requests (
  id               bigint generated always as identity primary key,
  booking_id       text not null,
  client_id        uuid,
  days_before      int not null,
  paid             numeric not null default 0,
  reservation_fee  numeric not null default 0,
  amount           numeric not null default 0,
  payout_method    text check (payout_method in ('gcash', 'maya', 'cash')),
  payout_number    text,
  payout_name      text,
  reason           text,
  status           text not null default 'pending' check (status in ('pending', 'refunded', 'rejected')),
  refund_reference text,
  admin_note       text,
  processed_by     uuid,
  processed_at     timestamptz,
  created_at       timestamptz not null default now()
);
create unique index if not exists refund_requests_one_per_booking on public.refund_requests (booking_id);

alter table public.refund_requests enable row level security;
drop policy if exists "admins manage refunds" on public.refund_requests;
create policy "admins manage refunds" on public.refund_requests
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "clients read own refunds" on public.refund_requests;
create policy "clients read own refunds" on public.refund_requests
  for select to authenticated using (client_id = auth.uid());

-- Pwedeng i-record ang refund bilang negatibong bayad (kind = 'refund').
do $$
declare c record;
begin
  for c in
    select con.conname, pg_get_constraintdef(con.oid) as def
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace n on n.oid = rel.relnamespace
    where n.nspname = 'public' and rel.relname = 'payments' and con.contype = 'c'
      and (pg_get_constraintdef(con.oid) ilike '%kind%' or pg_get_constraintdef(con.oid) ilike '%amount%')
      and con.conname <> 'payments_status_check'
  loop
    execute format('alter table public.payments drop constraint %I', c.conname);
  end loop;
end $$;

-- Kuwenta ng refund (pareho ang ginagamit ng app at ng server).
create or replace function public.refund_quote(p_booking_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b      record;
  paid   numeric;
  fee    numeric;
  days   int;
  refund numeric;
  today  date := (now() at time zone 'Asia/Manila')::date;
begin
  select * into b from public.bookings where id::text = p_booking_id;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if not coalesce(public.is_admin(), false) and (auth.uid() is null or b.client_id is distinct from auth.uid()) then
    raise exception 'NOT_ALLOWED';
  end if;

  select coalesce(sum(amount), 0) into paid
    from public.payments
   where booking_id::text = b.id::text and coalesce(status, 'verified') = 'verified';
  fee  := least(paid, round(coalesce(b.total_amount, 0) * 0.5));
  days := b.booking_date - today;
  refund := greatest(0, paid - fee) + case when days >= 1 then round(fee * 0.5) else 0 end;

  return jsonb_build_object(
    'days_before', days, 'paid', paid, 'reservation_fee', fee,
    'refund', refund, 'eligible_half', days >= 1,
    'can_cancel', b.status::text in ('reserved', 'confirmed', 'fully_paid') and b.checked_in_at is null and days >= 0);
end $$;

grant execute on function public.refund_quote(text) to authenticated;

-- Guest: i-cancel ang sariling booking at humingi ng refund (kung mayroon).
create or replace function public.request_cancellation(
  p_booking_id text,
  p_method     text default null,
  p_number     text default null,
  p_name       text default null,
  p_reason     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b   record;
  q   jsonb;
  amt numeric;
begin
  select * into b from public.bookings where id::text = p_booking_id for update;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if auth.uid() is null or b.client_id is distinct from auth.uid() then
    raise exception 'NOT_ALLOWED';
  end if;

  q := public.refund_quote(p_booking_id);
  if not (q->>'can_cancel')::boolean then raise exception 'CANNOT_CANCEL'; end if;
  amt := (q->>'refund')::numeric;

  if amt > 0 and (coalesce(p_method, '') not in ('gcash', 'maya') or length(coalesce(trim(p_number), '')) < 10
                  or length(coalesce(trim(p_name), '')) < 2) then
    raise exception 'PAYOUT_REQUIRED';
  end if;

  update public.bookings set status = 'cancelled' where id = b.id;
  insert into public.booking_logs (booking_id, action, from_status, to_status, note)
  values (b.id::text, 'status_change', b.status::text, 'cancelled',
          'Cancelled by guest' || case when coalesce(trim(p_reason), '') <> '' then ' · ' || trim(p_reason) else '' end
          || ' · ' || (q->>'days_before') || ' day(s) before · refund ' || amt);

  if amt > 0 then
    insert into public.refund_requests
      (booking_id, client_id, days_before, paid, reservation_fee, amount,
       payout_method, payout_number, payout_name, reason)
    values (b.id::text, b.client_id, (q->>'days_before')::int, (q->>'paid')::numeric,
            (q->>'reservation_fee')::numeric, amt, p_method, trim(p_number), trim(p_name),
            nullif(trim(coalesce(p_reason, '')), ''));
  end if;

  insert into public.notifications (audience, type, data, ref_id)
  values ('admin', 'refund_request',
          jsonb_build_object('client', public.client_display_name(b.client_id),
                             'package', (select name from public.packages where id = b.package_id),
                             'date', b.booking_date, 'amount', amt),
          b.id::text);

  return q;
end $$;

revoke all on function public.request_cancellation(text, text, text, text, text) from public, anon;
grant execute on function public.request_cancellation(text, text, text, text, text) to authenticated;

-- Admin: naipadala na ang refund (o tinanggihan).
create or replace function public.complete_refund(
  p_request_id bigint,
  p_reference  text default null,
  p_reject     boolean default false,
  p_note       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  b record;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'NOT_ADMIN'; end if;
  select * into r from public.refund_requests where id = p_request_id for update;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if r.status <> 'pending' then raise exception 'ALREADY_DONE'; end if;
  select * into b from public.bookings where id::text = r.booking_id;

  if p_reject then
    update public.refund_requests
       set status = 'rejected', admin_note = nullif(trim(coalesce(p_note, '')), ''),
           processed_by = auth.uid(), processed_at = now()
     where id = r.id;
  else
    update public.refund_requests
       set status = 'refunded', refund_reference = nullif(trim(coalesce(p_reference, '')), ''),
           admin_note = nullif(trim(coalesce(p_note, '')), ''),
           processed_by = auth.uid(), processed_at = now()
     where id = r.id;
    -- Ibawas sa nakolektang bayad (para tama ang reports).
    insert into public.payments (booking_id, amount, method, kind, received_by, status, reference_no)
    values (b.id, -r.amount, coalesce(r.payout_method, 'cash'), 'refund', auth.uid(), 'verified',
            nullif(trim(coalesce(p_reference, '')), ''));
  end if;

  insert into public.booking_logs (booking_id, action, note)
  values (r.booking_id, case when p_reject then 'refund_rejected' else 'refunded' end,
          case when p_reject then coalesce(p_note, '') else 'Refund ' || r.amount || coalesce(' · Ref ' || p_reference, '') end);

  if r.client_id is not null then
    insert into public.notifications (audience, recipient_id, type, data, ref_id)
    values ('client', r.client_id, case when p_reject then 'payment_refund_rejected' else 'payment_refunded' end,
            jsonb_build_object('package', (select name from public.packages where id = b.package_id),
                               'date', b.booking_date, 'amount', r.amount,
                               'reference_no', p_reference, 'reason', p_note),
            r.booking_id);
  end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.complete_refund(bigint, text, boolean, text) from public, anon;
grant execute on function public.complete_refund(bigint, text, boolean, text) to authenticated;

-- Tapos na ang Part 10!

-- ===========================================================================
-- PART 11 (dinagdag Nov 7, 2026): Mga presyo ng package, Overnight (22 hours),
-- at refund kapag may VALID na dahilan lang
--   Pool:          Day Tour ₱5,500 · Night Tour ₱6,500 · Overnight (22 Hours) ₱11,500
--   Function Hall: Day Tour ₱15,000 · Night Tour ₱15,000 · Overnight (22 Hours) ₱22,000
--   Lahat ay non-refundable maliban kung may valid na dahilan (aaprubahan ng admin);
--   kapag valid, susundin ang policy sa reservation fee.
-- ===========================================================================

-- ---- Pool packages ----
update public.packages set price = 5500 where name = 'Day Tour';
update public.packages set price = 6500 where name = 'Night Tour';

-- Bagong "Overnight (22 Hours)": kopya ng Night Tour (inclusions, max pax, atbp.),
-- 8:00 AM hanggang 6:00 AM kinabukasan, ₱11,500.
do $$
declare
  cols      text;
  id_needed boolean;
  id_type   text;
  id_expr   text;
begin
  if exists (select 1 from public.packages where name = 'Overnight (22 Hours)') then
    update public.packages
       set price = 11500, start_time = '08:00', end_time = '06:00'
     where name = 'Overnight (22 Hours)';
    return;
  end if;
  if not exists (select 1 from public.packages where name = 'Night Tour') then
    return;
  end if;

  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'packages'
     and column_name not in ('id', 'name', 'price', 'start_time', 'end_time', 'created_at')
     and is_generated = 'NEVER' and identity_generation is null;

  -- Kung walang default ang id, gagawa tayo ng bago (uuid o susunod na numero).
  select c.column_default is null and c.identity_generation is null, c.data_type
    into id_needed, id_type
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'packages' and c.column_name = 'id';
  if id_needed then
    id_expr := case when id_type = 'uuid' then 'gen_random_uuid()'
                    when id_type in ('text', 'character varying') then 'gen_random_uuid()::text'
                    else '(select coalesce(max(id), 0) + 1 from public.packages)' end;
  end if;

  execute format(
    'insert into public.packages (%sname, price, start_time, end_time%s)
     select %s%L, 11500, %L, %L%s from public.packages where name = %L limit 1',
    case when id_expr is null then '' else 'id, ' end,
    case when cols is null then '' else ', ' || cols end,
    case when id_expr is null then '' else id_expr || ', ' end,
    'Overnight (22 Hours)', '08:00', '06:00',
    case when cols is null then '' else ', ' || cols end,
    'Night Tour');
end $$;

-- ---- Function Hall: pangalan at presyo ayon sa oras (hindi binabago ang oras) ----
update public.packages
   set name = 'Function Hall (Day Tour)', price = 15000
 where name ilike 'function hall%'
   and start_time::text::time < time '17:00' and end_time::text::time > start_time::text::time;

update public.packages
   set name = 'Function Hall (Night Tour)', price = 15000
 where name ilike 'function hall%'
   and start_time::text::time >= time '17:00';

update public.packages
   set name = 'Function Hall (Overnight 22 Hours)', price = 22000
 where name ilike 'function hall%'
   and start_time::text::time < time '17:00' and end_time::text::time <= start_time::text::time;

-- ---- Pag-cancel: refund kapag hiniling LANG at may dahilan; admin ang mag-aapruba ----
drop function if exists public.request_cancellation(text, text, text, text, text);

create or replace function public.request_cancellation(
  p_booking_id     text,
  p_method         text default null,
  p_number         text default null,
  p_name           text default null,
  p_reason         text default null,
  p_request_refund boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b    record;
  q    jsonb;
  amt  numeric;
  want boolean;
begin
  select * into b from public.bookings where id::text = p_booking_id for update;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if auth.uid() is null or b.client_id is distinct from auth.uid() then
    raise exception 'NOT_ALLOWED';
  end if;

  q := public.refund_quote(p_booking_id);
  if not (q->>'can_cancel')::boolean then raise exception 'CANNOT_CANCEL'; end if;
  amt  := (q->>'refund')::numeric;
  want := coalesce(p_request_refund, true) and amt > 0;

  if want then
    if length(coalesce(trim(p_reason), '')) < 5 then
      raise exception 'REASON_REQUIRED';
    end if;
    if coalesce(p_method, '') not in ('gcash', 'maya') or length(coalesce(trim(p_number), '')) < 10
       or length(coalesce(trim(p_name), '')) < 2 then
      raise exception 'PAYOUT_REQUIRED';
    end if;
  end if;

  update public.bookings set status = 'cancelled' where id = b.id;
  insert into public.booking_logs (booking_id, action, from_status, to_status, note)
  values (b.id::text, 'status_change', b.status::text, 'cancelled',
          'Cancelled by guest' || case when coalesce(trim(p_reason), '') <> '' then ' · ' || trim(p_reason) else '' end
          || ' · ' || (q->>'days_before') || ' day(s) before'
          || case when want then ' · refund requested ' || amt else ' · no refund requested' end);

  if want then
    insert into public.refund_requests
      (booking_id, client_id, days_before, paid, reservation_fee, amount,
       payout_method, payout_number, payout_name, reason)
    values (b.id::text, b.client_id, (q->>'days_before')::int, (q->>'paid')::numeric,
            (q->>'reservation_fee')::numeric, amt, p_method, trim(p_number), trim(p_name), trim(p_reason));
  end if;

  insert into public.notifications (audience, type, data, ref_id)
  values ('admin', 'refund_request',
          jsonb_build_object('client', public.client_display_name(b.client_id),
                             'package', (select name from public.packages where id = b.package_id),
                             'date', b.booking_date, 'amount', case when want then amt else 0 end,
                             'reason', p_reason),
          b.id::text);

  return q || jsonb_build_object('refund_requested', want);
end $$;

revoke all on function public.request_cancellation(text, text, text, text, text, boolean) from public, anon;
grant execute on function public.request_cancellation(text, text, text, text, text, boolean) to authenticated;

-- Tapos na ang Part 11!

-- ===========================================================================
-- PART 12 (dinagdag Nov 7, 2026): Pangalan sa notification — FIRST LAST, all caps
--   Hal. "KRIZIA BUENA" (hindi na "Buena Krizia" mula sa Google name)
-- ===========================================================================
create or replace function public.client_display_name(p_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select upper(coalesce(
    nullif(trim(
      case when upper(trim(coalesce(first_name, ''))) = 'N/A' then '' else trim(coalesce(first_name, '')) end
      || ' ' ||
      case when upper(trim(coalesce(last_name, ''))) = 'N/A' then '' else trim(coalesce(last_name, '')) end
    ), ''),
    nullif(trim(google_display_name), ''),
    'Client'
  ))
  from public.profiles where id = p_id;
$$;

-- Tapos na ang Part 12!

-- ===========================================================================
-- PART 13 (dinagdag Nov 8, 2026): Kusang "No-show"
--   Kapag hindi nag-check in ang guest at natapos na ang oras ng package
--   (hal. Day Tour hanggang 5:00 PM → no-show pagsapit ng 5:01 PM;
--   Night Tour / Overnight hanggang 6:00 AM → no-show pagsapit ng 6:01 AM kinabukasan),
--   gagawing "no_show" ang booking, ila-log, at aabisuhan ang guest.
--   Non-refundable ang mga bayad (kasama pa rin sa "Collected").
-- ===========================================================================
create or replace function public.mark_no_shows()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  b record;
  n int := 0;
begin
  for b in
    select bk.* from public.bookings bk
     where bk.status::text in ('reserved', 'confirmed', 'fully_paid')
       and bk.checked_in_at is null
       and bk.booking_date <= (now() at time zone 'Asia/Manila')::date
       and public.booking_end_at(bk.booking_date, bk.package_id) < now()
     for update skip locked
  loop
    update public.bookings set status = 'no_show' where id = b.id;

    insert into public.booking_logs (booking_id, action, from_status, to_status, note)
    values (b.id::text, 'status_change', b.status::text, 'no_show',
            'Automatically marked: no check-in on the booking date');

    if b.client_id is not null then
      insert into public.notifications (audience, recipient_id, type, data, ref_id)
      values ('client', b.client_id, 'booking_no_show',
              jsonb_build_object('package', (select name from public.packages where id = b.package_id),
                                 'date', b.booking_date,
                                 'note', 'There was no check-in on your booking date. Payments are non-refundable.'),
              b.id::text);
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

revoke all on function public.mark_no_shows() from public, anon;
grant execute on function public.mark_no_shows() to authenticated;

-- Patakbuhin bawat minuto (pg_cron). Kung hindi available, ang admin app ang tatawag nito.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'mark-no-shows';
  perform cron.schedule('mark-no-shows', '* * * * *', 'select public.mark_no_shows()');
exception when others then
  raise notice 'pg_cron is not available (%). The admin app will mark no-shows instead.', sqlerrm;
end $$;

-- Ngayon din: ayusin ang mga lumang booking na lumipas na.
select public.mark_no_shows() as marked_no_show;

-- Tapos na ang Part 13!

-- ===========================================================================
-- PART 14 (dinagdag Nov 8, 2026): Posisyon ng admin/staff
--   Hal. "Owner", "Assistant / Caretaker" — makikita sa sidebar at Dashboard.
--   Ang admin mismo ang naglalagay nito (pindutin ang pangalan sa sidebar).
-- ===========================================================================
alter table public.profiles add column if not exists staff_title text;

-- Tapos na ang Part 14!

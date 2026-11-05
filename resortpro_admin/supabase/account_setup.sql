-- Account page: username at profile picture (avatars bucket).
-- I-paste lahat sa Supabase > SQL Editor > New query, tapos Run.

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

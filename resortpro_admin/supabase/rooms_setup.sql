-- ===========================================================================
-- FUNCTION HALL: DAGDAG NA KUWARTO SA SECOND FLOOR (Nov 24, 2026)
--
-- Ayon sa caretaker: hindi kasama sa Function Hall package ang mga kuwarto
-- sa second floor. ₱3,500 bawat kuwarto, hanggang 3, at Function Hall
-- booking lang ang pwedeng mag-avail.
--   • bookings.extra_rooms / extra_rooms_fee — ilang kuwarto at magkano
--   • resort_settings.extra_room_rate / extra_rooms_max — presyo at limit
--   • bookings_guard — sa online booking, ang server ang nagkukuwenta ng
--     singil; hinaharang kapag hindi Function Hall o lampas sa limit.
--
-- Ligtas itong patakbuhin nang ilang beses.
-- ===========================================================================

alter table public.bookings add column if not exists extra_rooms     int     not null default 0;
alter table public.bookings add column if not exists extra_rooms_fee numeric not null default 0;

alter table public.resort_settings add column if not exists extra_room_rate numeric not null default 3500;
alter table public.resort_settings add column if not exists extra_rooms_max int     not null default 3;

create or replace function public.bookings_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  inc   int;
  rate  numeric;
  rrate numeric;
  rmax  int;
  is_fh boolean;
begin
  -- Dagdag na kuwarto (second floor): Function Hall lang, hanggang extra_rooms_max.
  select name ilike 'function hall%' into is_fh from public.packages where id = new.package_id;
  select coalesce(extra_room_rate, 3500), coalesce(extra_rooms_max, 3) into rrate, rmax
    from public.resort_settings where id = 1;
  new.extra_rooms := coalesce(new.extra_rooms, 0);
  if new.extra_rooms < 0 or new.extra_rooms > coalesce(rmax, 3) then
    raise exception 'ROOMS_LIMIT: Up to % additional rooms only.', coalesce(rmax, 3);
  end if;
  if new.extra_rooms > 0 and not coalesce(is_fh, false) then
    raise exception 'ROOMS_FUNCTION_HALL_ONLY: Additional rooms are for Function Hall bookings only.';
  end if;

  if tg_op = 'INSERT' and not public.is_admin() then
    new.total_amount := coalesce(public.price_for(new.package_id, new.booking_date), new.total_amount);
    select included_pax into inc from public.packages where id = new.package_id;
    select coalesce(extra_pax_rate, 100) into rate from public.resort_settings where id = 1;
    new.extra_pax       := case when coalesce(inc, 0) > 0 then greatest(0, coalesce(new.total_pax, 0) - coalesce(new.infants, 0) - inc) else 0 end;
    new.extra_pax_fee   := new.extra_pax * coalesce(rate, 100);
    new.extra_rooms_fee := new.extra_rooms * coalesce(rrate, 3500);
    new.total_amount    := coalesce(new.total_amount, 0) + new.extra_pax_fee + new.extra_rooms_fee;
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

drop trigger if exists trg_bookings_guard on public.bookings;
create trigger trg_bookings_guard
  before insert or update of booking_date, package_id, status, extra_rooms on public.bookings
  for each row execute function public.bookings_guard();

-- Dapat lumabas: 3500 | 3
select extra_room_rate, extra_rooms_max from public.resort_settings where id = 1;

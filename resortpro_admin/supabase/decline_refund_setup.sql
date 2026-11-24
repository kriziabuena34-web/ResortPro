-- ===========================================================================
-- DECLINE / CANCEL NG RESORT → FULL REFUND (Nov 24, 2026)
--
-- Kapag ang RESORT (admin) ang nag-decline o nag-cancel ng booking:
--   • May payment proof pang hindi nare-review (pending) → HINDI pwede.
--     I-verify muna (kung dumating ang pera) o i-reject (kung hindi).
--   • May verified na bayad → buong halaga ang ibabalik (hindi kalahati,
--     dahil hindi guest ang nag-cancel). Gagawa ng refund sa
--     Payments → Refunds; doon ilalagay ang reference kapag naipadala na.
--   • Walang bayad → cancelled lang.
--
-- Ligtas itong patakbuhin nang ilang beses.
-- ===========================================================================

create or replace function public.admin_cancel_booking(
  p_booking_id text,
  p_note       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b      record;
  paid   numeric;
  pend   int;
  meth   text;
  phone  text;
  note   text := nullif(left(trim(coalesce(p_note, '')), 300), '');
begin
  if not coalesce(public.is_admin(), false) then raise exception 'NOT_ADMIN'; end if;

  select * into b from public.bookings where id::text = p_booking_id for update;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if b.status::text not in ('reserved', 'confirmed', 'fully_paid') then
    raise exception 'CANNOT_CANCEL';
  end if;

  select count(*) into pend
    from public.payments
   where booking_id::text = p_booking_id and status = 'pending';
  if pend > 0 then raise exception 'PENDING_PAYMENTS'; end if;

  -- Netong verified na bayad (kasama ang dating refund na negatibo).
  select coalesce(sum(amount), 0) into paid
    from public.payments
   where booking_id::text = p_booking_id and coalesce(status, 'verified') = 'verified';
  paid := greatest(paid, 0);

  update public.bookings set status = 'cancelled' where id = b.id;

  insert into public.booking_logs (booking_id, action, from_status, to_status, note)
  values (b.id::text, 'status_change', b.status::text, 'cancelled',
          'Cancelled by resort' || coalesce(' · ' || note, '')
          || case when paid > 0 then ' · full refund ' || paid else '' end);

  if paid > 0 then
    -- Ibabalik sa paraang ginamit ng guest sa pinakahuling bayad.
    select method into meth
      from public.payments
     where booking_id::text = p_booking_id and coalesce(status, 'verified') = 'verified' and amount > 0
     order by created_at desc nulls last
     limit 1;
    if meth not in ('gcash', 'maya', 'cash') then meth := null; end if;

    select nullif(trim(to_jsonb(p)->>'phone'), '') into phone
      from public.profiles p where p.id = b.client_id;

    insert into public.refund_requests
      (booking_id, client_id, days_before, paid, reservation_fee, amount,
       payout_method, payout_number, payout_name, reason)
    values (b.id::text, b.client_id, greatest(b.booking_date - current_date, 0), paid, 0, paid,
            meth, coalesce(phone, b.guest_phone),
            coalesce(public.client_display_name(b.client_id), b.guest_name),
            left('Declined by resort' || coalesce(': ' || note, ''), 500))
    on conflict (booking_id) do update
       set client_id = excluded.client_id, days_before = excluded.days_before,
           paid = excluded.paid, reservation_fee = 0, amount = excluded.amount,
           payout_method = excluded.payout_method, payout_number = excluded.payout_number,
           payout_name = excluded.payout_name, reason = excluded.reason,
           status = 'pending', refund_reference = null, admin_note = null,
           processed_by = null, processed_at = null, created_at = now();
  end if;

  return jsonb_build_object('refund', paid);
end $$;

revoke all on function public.admin_cancel_booking(text, text) from public, anon;
grant execute on function public.admin_cancel_booking(text, text) to authenticated;

-- Dapat lumabas: admin_cancel_booking
select proname from pg_proc where proname = 'admin_cancel_booking';

-- ===========================================================================
-- DECLINE / CANCEL NG RESORT → FULL REFUND (Nov 24, 2026)
--
-- Kapag ang RESORT (admin) ang nag-decline o nag-cancel ng booking:
--   • May payment proof pang hindi nare-review (pending) → HINDI pwede.
--     I-verify muna (kung dumating ang pera) o i-reject (kung hindi).
--   • May verified na bayad → buong halaga ang ibabalik (hindi kalahati,
--     dahil hindi guest ang nag-cancel). Gagawa ng refund sa
--     Payments → Refunds na WALA pang account: ang guest ang maglalagay
--     ng sariling GCash/Maya sa app ("Claim your refund"). Para sa walk-in
--     o phone booking na walang account, ang admin ang maglalagay.
--   • Hindi pwedeng i-"Mark as sent" ang refund hangga't walang account.
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
    insert into public.refund_requests
      (booking_id, client_id, days_before, paid, reservation_fee, amount,
       payout_method, payout_number, payout_name, reason)
    values (b.id::text, b.client_id, greatest(b.booking_date - current_date, 0), paid, 0, paid,
            null, null, null,
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

-- ---------------------------------------------------------------------------
-- Guest: saan ipapadala ang refund (GCash o Maya na sarili niyang account)
-- ---------------------------------------------------------------------------
create or replace function public.submit_refund_details(
  p_booking_id text,
  p_method     text,
  p_number     text,
  p_name       text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r   record;
  num text := regexp_replace(coalesce(p_number, ''), '\D', '', 'g');
  nm  text := left(trim(coalesce(p_name, '')), 60);
begin
  select * into r from public.refund_requests where booking_id = p_booking_id for update;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if auth.uid() is null or r.client_id is distinct from auth.uid() then raise exception 'NOT_ALLOWED'; end if;
  if r.status <> 'pending' then raise exception 'ALREADY_DONE'; end if;
  if coalesce(p_method, '') not in ('gcash', 'maya') or num !~ '^09[0-9]{9}$' or length(nm) < 2 then
    raise exception 'PAYOUT_REQUIRED';
  end if;

  update public.refund_requests
     set payout_method = p_method, payout_number = num, payout_name = nm
   where id = r.id;

  insert into public.booking_logs (booking_id, action, note)
  values (r.booking_id, 'refund_details', 'Guest sent refund account · ' || p_method);

  insert into public.notifications (audience, type, data, ref_id)
  values ('admin', 'refund_details',
          jsonb_build_object('client', public.client_display_name(r.client_id),
                             'package', (select p.name from public.bookings b join public.packages p on p.id = b.package_id
                                          where b.id::text = r.booking_id),
                             'amount', r.amount, 'method', p_method),
          r.booking_id);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.submit_refund_details(text, text, text, text) from public, anon;
grant execute on function public.submit_refund_details(text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: naipadala na ang refund (o tinanggihan). Hindi na pwedeng i-"sent"
-- kapag wala pang account na mapapadalhan (maliban sa cash).
-- ---------------------------------------------------------------------------
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
  if not coalesce(p_reject, false)
     and (r.payout_method is null
          or (r.payout_method <> 'cash' and coalesce(trim(r.payout_number), '') = '')) then
    raise exception 'PAYOUT_MISSING';
  end if;
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

-- Dapat lumabas ang 3: admin_cancel_booking, complete_refund, submit_refund_details
select proname from pg_proc
 where proname in ('admin_cancel_booking', 'complete_refund', 'submit_refund_details')
 order by proname;

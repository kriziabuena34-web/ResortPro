-- ===========================================================================
-- TERMS & LIMITS SETUP (Nov 24, 2026)
--   I-paste LAHAT sa Supabase > SQL Editor > New query, tapos Run.
--   Ligtas i-run kahit ilang beses. Walang binubura na data.
--
--   Part A: Pool Agreement ng resort na nababago sa admin (resort_settings.pool_terms)
--   Part B: Limit sa haba ng mga reason at note. Ang dating text na sobrang
--           haba (hal. test na paulit-ulit na letra) ay pinaiikli sa limit.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Part A: Pool Agreement (listahan ng patakaran; JSON array ng text)
--   Nababasa ng lahat (kahit hindi naka-login, para sa app);
--   admin lang ang nakakapagbago (dating policy ng resort_settings).
-- ---------------------------------------------------------------------------
alter table public.resort_settings add column if not exists pool_terms jsonb;
alter table public.resort_settings add column if not exists pool_terms_updated_at timestamptz;

update public.resort_settings
   set pool_terms = '["Payment of 50% must be made at the time of booking, and the balance must be paid upon arrival.", "There must be adult supervision at all private rentals. Strictly NO Diving.", "There will be no food, drinks, or pets on the pool premises.", "Guests will be responsible for any damage that may occur during the time they rent the facility.", "The management is not liable for any accidents that will occur during the guest''s stay.", "Guests are responsible for confirming or canceling their reservations at least 5 days before the booking date.", "If the guests fail to cancel the reservation within 5 days, they will no longer get the 50% reservation fee.", "Guests can only refund half of the 50% reservation fee if they cancel within 5 days before the event.", "All bookings are non-refundable unless the guest has a valid reason accepted by the management.", "For extensions, guests will be charged ₱500 per hour.", "Guests are obliged to make an effort to keep the surroundings clean. Guests should refrain from throwing rubbish anywhere other than the strategically located trash bins. Don''t leave any trash.", "If the guest exceeds 20 pax, there will be an additional payment of ₱100 per head.", "Aryana''s Guest House will not be responsible for any lost belongings or personal items of the customer.", "The videoke and speaker are strictly until 10 PM. Exceeding the time limit will result in a ₱1,500 penalty."]'::jsonb
 where id = 1 and pool_terms is null;

-- ---------------------------------------------------------------------------
-- Part B: Limit sa haba ng text
--   Una, paiikliin ang dating sobrang habang text para pumasa sa limit.
-- ---------------------------------------------------------------------------
update public.payments set reject_reason = left(reject_reason, 300) where char_length(reject_reason) > 300;
update public.refund_requests set reason = left(reason, 500) where char_length(reason) > 500;
update public.refund_requests set admin_note = left(admin_note, 300) where char_length(admin_note) > 300;
update public.refund_requests set refund_reference = left(refund_reference, 60) where char_length(refund_reference) > 60;
update public.bookings set admin_notes = left(admin_notes, 1000) where char_length(admin_notes) > 1000;
update public.bookings set other_charges_note = left(other_charges_note, 300) where char_length(other_charges_note) > 300;
update public.bookings set guest_name = left(guest_name, 100) where char_length(guest_name) > 100;
update public.bookings set event_type = left(event_type, 100) where char_length(event_type) > 100;
update public.expenses set note = left(note, 300) where char_length(note) > 300;
update public.notifications set data = jsonb_set(data, '{reason}', to_jsonb(left(data->>'reason', 500)))
 where char_length(data->>'reason') > 500;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payments_reject_reason_len') then
    alter table public.payments add constraint payments_reject_reason_len
      check (char_length(coalesce(reject_reason, '')) <= 300);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'refund_requests_reason_len') then
    alter table public.refund_requests add constraint refund_requests_reason_len
      check (char_length(coalesce(reason, '')) <= 500);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'refund_requests_note_len') then
    alter table public.refund_requests add constraint refund_requests_note_len
      check (char_length(coalesce(admin_note, '')) <= 300
         and char_length(coalesce(refund_reference, '')) <= 60);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bookings_text_len') then
    alter table public.bookings add constraint bookings_text_len
      check (char_length(coalesce(admin_notes, '')) <= 1000
         and char_length(coalesce(other_charges_note, '')) <= 300
         and char_length(coalesce(guest_name, '')) <= 100
         and char_length(coalesce(event_type, '')) <= 100);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'expenses_note_len') then
    alter table public.expenses add constraint expenses_note_len
      check (char_length(coalesce(note, '')) <= 300);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'notifications_reason_len') then
    alter table public.notifications add constraint notifications_reason_len
      check (char_length(coalesce(data->>'reason', '')) <= 500);
  end if;
end $$;

-- Tsek: dapat 14 ang bilang ng patakaran
select jsonb_array_length(pool_terms) as pool_terms_count from public.resort_settings where id = 1;

-- Tapos na!

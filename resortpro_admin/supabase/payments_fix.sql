-- Ayos: payment proof ng client ("new row violates row-level security policy for table payments")
-- I-paste lahat sa Supabase > SQL Editor > New query, tapos Run. Ligtas i-run kahit ilang beses.

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

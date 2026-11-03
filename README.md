# ResortPro — Aryana's Guests House

Capstone project (BS IT – Business Analytics).
A resort booking and management system built with **Flutter** and **Supabase**.

| Folder | What it is | Runs on |
|---|---|---|
| `resortpro/` | Guest app: browse packages, book dates, upload GCash/Maya proof of payment, notifications | Android |
| `resortpro_admin/` | Admin panel: dashboard, bookings workflow, calendar, clients, verifications, payments, packages, gallery, availability and seasonal pricing, PDF/Excel reports, analytics with forecast | Web (Edge/Chrome) |

## Database setup
Run `resortpro_admin/supabase/admin_setup.sql` once in the Supabase SQL Editor. It is safe to run again.

## Running
```bash
cd resortpro        # or resortpro_admin
flutter pub get
flutter run
```

# SmartBlock

## Current app features

- Email sign-in, account registration, and password reset through Supabase Auth.
- Greek and English interface.
- Organization registration and approval status tracking.
- Property registration and co-owner share tracking.
- Property details and guarded submission for review after organization approval.
- Database-enforced ownership share limits and row-level access policies.
- Property-first drafts, apartment buildings, and required descriptions for “Other”.
- Phone-based owner organization matching and property owner linking.
- SmartBlock staff review screens, property votes, common charge runs, and rental contracts.
- Property management records for contracts, services, expenses, reserve settings, arrears actions, insurance, meetings, and handovers.
- A server-side cash-reserve check for expense payments, plus a property-scoped list of overdue common charges with linked follow-up history.
- One-active-contract enforcement with an amendment log and authorized approval of revised fees and VAT.
- Resident service requests follow quote, approval, work, and expense review steps; approved quotes count against the reserve before completion.
- Insurance claims are linked to a policy and tracked from report through review, decision, payout, and closure.
- Monthly, quarterly, semiannual, annual, or custom common-charge cycles, with a property finance overview.
- Common charges can be allocated by ownership share, declared floor area, or apartment count; each run records the method used.
- Private PDF and image attachments are supported for management records; meeting files are shared with property members, while arrears, expenses, claims, and handover files stay manager-only.
- In-app reminders cover contract notice/expiry, insurance expiry, upcoming meetings, and charges due within seven days; owner-specific debt follow-ups are manager-only.

## Run the Flutter app

1. Open this folder in VS Code and select **SmartBlock (Supabase)** in Run and Debug.
2. The project URL and publishable key are read from the local, git-ignored `supabase.environment.json` file.
3. Start debugging. Keep the local environment file out of version control.

For a fresh checkout, copy `launch.example.json` to `.vscode/launch.json` and `supabase.environment.example.json` to `supabase.environment.json`, then add the project's publishable key to the local environment file.

In Supabase **Authentication → URL Configuration**, allow these redirect URLs for confirmation and password recovery:

- `io.supabase.smartblock://login-callback`
- `http://localhost:*/*` for local Flutter web runs

To create a production web build, run `flutter build web --release --dart-define-from-file=supabase.environment.json`. The static site is generated in `build/web`.

For a signed Android release, keep `android/key.properties` and `android/app/smartblock-release.jks` local and out of version control. They are generated for this checkout. Back up the keystore and its passwords securely; Android updates must keep using the same signing key. Build an APK with `flutter build apk --release --dart-define-from-file=supabase.environment.json`, or a Play Store bundle with `flutter build appbundle --release --dart-define-from-file=supabase.environment.json`. If you clone the repo, copy `android/key.properties.example` to `android/key.properties` and provide your signing credentials and keystore.

## Publish the web app with GitHub Pages

The workflow in `.github/workflows/deploy-web.yml` builds and deploys the Web app on pushes to `main`. In the GitHub repository, set the `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` repository variables under **Settings → Secrets and variables → Actions → Variables**, then select **GitHub Actions** as the Pages build source. The publishable key is intended for client-side use; never add a `service_role` key to repository variables or the web build.

Use the publishable key for the client app. Do not use a secret or `service_role` key in Flutter.

SB_105 enables property-first creation, phone lookup for owners, staff roles, and review actions. SB_106 adds voting, common-charge allocation/payment tracking, and rental contracts. SB_112 adds property management records and private management-document storage; SB_113 adds flexible common-charge cycles; SB_114 adds finance opening balances; SB_115 adds an atomic reserve-aware expense-payment RPC; SB_116 adds allocation by ownership share, floor area, or apartment count; SB_117 adds single-active-contract enforcement and reviewed amendments; SB_118 adds resident service requests, quote approval, and completion-to-expense tracking; SB_119 adds an insurance-claim register. These migrations are applied to the linked production Supabase project. To make the signed-in operator an admin, run a private one-time insert into `public.smartblock_staff` for their `auth.users.id`; do not commit user IDs or service-role credentials. The app exposes the admin review menu only when `is_smartblock_staff()` returns true.

The organization, property, co-owner, and review workflow database scripts are archived in `supabase/queries`. SB_092–SB_104 have been applied to the linked Supabase project. They are retained as reference SQL; do not rerun the table-creation scripts SB_092–SB_096.

## Stripe online payments (test mode)

SB_111 and the `create-checkout-session` / `stripe-webhook` Edge Functions add hosted Stripe Checkout for common-charge entries and rent installments. Stripe records the payment only after its signed webhook confirms settlement. The current implementation deliberately rejects `sk_live_` keys so accidental live charges cannot be made during setup and trial.

The SB_111 database migration is applied and both Edge Functions are deployed to the linked SmartBlock Supabase project. Add these two secrets in Supabase Edge Function Secrets to activate payments:

- `STRIPE_SECRET_KEY`: a Stripe test-mode secret key (`sk_test_...`).
- `STRIPE_WEBHOOK_SECRET`: the signing secret (`whsec_...`) for the already registered Stripe sandbox webhook at `https://ymlmjalcrgqiijqpvlop.supabase.co/functions/v1/stripe-webhook`, subscribed to `checkout.session.completed` and `checkout.session.async_payment_succeeded`.

In Stripe sandbox, enable card payments and Apple Pay / Google Pay under payment-method settings. Stripe Checkout shows wallet buttons only when Stripe and the customer's browser/device support them. Test with Stripe's published test card details; no live funds should move.

Never put the Stripe secret or webhook signing secret in Flutter code, a GitHub repository variable, or a committed file. Store them only as Supabase Edge Function secrets. A live key is intentionally blocked until the live-payment mode is explicitly enabled in a later change.


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

SB_105 enables property-first creation, phone lookup for owners, staff roles, and review actions. SB_106 adds voting, common-charge allocation/payment tracking, and rental contracts. Apply each once in the Supabase SQL Editor after reviewing it. To make the signed-in operator an admin, run a private one-time insert into `public.smartblock_staff` for their `auth.users.id`; do not commit user IDs or service-role credentials. The app exposes the admin review menu only when `is_smartblock_staff()` returns true.

The organization, property, co-owner, and review workflow database scripts are archived in `supabase/queries`. SB_092–SB_104 have been applied to the linked Supabase project. They are retained as reference SQL; do not rerun the table-creation scripts SB_092–SB_096.

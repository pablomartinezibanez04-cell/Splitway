# Profile Completeness — Design Document

**Status:** Approved
**Date:** 2026-05-28
**Author:** PabloMartinezIbanez
**Related specs:** `2026-05-28-admin-panel-design.md`

## 1. Context

Splitway supports two sign-in methods at the Supabase Auth layer:

- **Email + password** (Flutter signup form collects nickname, date of birth, password)
- **Google OAuth** (one-tap via `signInWithGoogle()` in Flutter)

Today, Google-OAuth users end up with an inconsistent account state:

- A `profiles` row is auto-created by `ProfileService.ensureProfile(fallbackNickname: ...)` with a nickname derived from Google (`movile_app/lib/src/services/profile/profile_service.dart:50`), `date_of_birth = null`, and no password set on `auth.users`.
- They cannot subsequently sign in with email + password.
- The auto-generated nickname is throw-away — the user never chose it.

This blocks the admin panel: the seeded superadmin (`pabmariba@gmail.com`) is a Google-OAuth user, so the F2 email/password form rejects them. It also means the Flutter user base has two semantically different account flavors with no way to bridge them.

## 2. Goal

Establish a single source of truth for **"this user's account is complete"** and enforce it consistently in both clients (admin panel and Flutter app) so that:

- Every user — regardless of how they signed up — eventually has nickname, date of birth, and password set.
- Once complete, users can sign in via **either** method interchangeably.
- The criterion is documented in one place and the enforcement is symmetric.

## 3. Scope

### In scope

- A shared "is profile complete" contract: three conditions, no new DB columns.
- Admin panel implementation (Phase F2.1): Google OAuth button, OAuth callback, middleware redirect to onboarding, dedicated `/onboarding/complete-profile` page + action.
- Flutter implementation (Phase F2.2): post-sign-in completeness check, dedicated `CompleteProfileScreen`, removal of the silent `ensureProfile(fallbackNickname)` auto-creation, gate on `HomeShell`.

### Out of scope (YAGNI)

- A DB-side trigger or RPC for the completeness check. Both clients implement the same three boolean conditions; collapsing them into an RPC adds a round-trip without simplifying the logic.
- Backfilling existing incomplete profiles via a migration. Enforcement is lazy: the next time the user signs in they hit the onboarding flow. For the seeded superadmin this happens on the first F2.1 sign-in attempt.
- Adding `avatar_url` or `bio` to the completeness criterion. Both stay optional.
- A shared onboarding web page rendered inside Flutter via webview. Each client implements its own UI on its own stack.
- Email-confirmation changes. The existing Flutter signup flow keeps its confirmation behavior; the admin panel adds no signup at all.

## 4. The Completeness Contract

A user's account is **complete** if and only if **all three** of the following are true:

1. `profiles.nickname` is non-null and not empty.
2. `profiles.date_of_birth` is non-null.
3. The user's `auth.users.identities` array contains an entry with `provider = 'email'` (equivalent to "the user has a password set in Supabase Auth").

Condition 3 is checked client-side by inspecting the result of `supabase.auth.getUser()`. The `identities` array is reliably populated on every getUser call in both SSR and Flutter SDKs.

**Failure mode:** if any condition is false, the account is incomplete and the client must redirect/navigate to its respective onboarding flow before allowing any other action.

## 5. Phase F2.1 — Admin Panel

**Why first:** unblocks the seeded superadmin from logging into the F2 admin panel.

### New surface

| Path | Purpose |
|---|---|
| `/login` (extended) | Adds a "Continuar con Google" button alongside the email+password form. |
| `/auth/callback` | Route handler that exchanges the OAuth `?code` for a session and redirects. |
| `/onboarding/complete-profile` | Dedicated page (own layout, no sidebar) with a single form for nickname, DOB, password. |

### Auth flow

```
                       no session
unauth -> /login ─────────────────────────────> /login
                       Google or email login
            │                                  │
            ▼                                  ▼
       /auth/callback (only OAuth) ──────► session created
                                               │
                                               ▼
                          middleware re-evaluates the request
                                               │
                              ┌────────────────┼─────────────────────┐
                              │                │                     │
                              ▼                ▼                     ▼
                       not admin           admin role +          admin role +
                                          incomplete profile    complete profile
                              │                │                     │
                              ▼                ▼                     ▼
                       signOut +          /onboarding/         original target
                       /login?            complete-profile     (/, /settings, …)
                       error=forbidden
```

### Middleware extensions

The existing `updateSession` (admin/lib/supabase/middleware.ts) already enforces "must be admin to enter". F2.1 extends it with:

- When `role` is admin/superadmin AND `pathname` is **not** `/onboarding/...`, query `profiles.nickname` + `profiles.date_of_birth` (the role query is already there — extend its `select` rather than adding a second round-trip). Inspect `user.identities` for `provider === 'email'`. If any condition fails, redirect to `/onboarding/complete-profile`.
- When `pathname` is `/onboarding/complete-profile` AND profile is already complete, redirect to `/`.
- `/auth/callback` must be in the middleware matcher so OAuth redirects are processed, but the route handler itself bypasses the role/onboarding check (the user has no session yet on entry).

### The onboarding form

A single client component with three inputs:

- **Apodo** (`Input`, autofocus, min 2 / max 24 chars, matches the `update_nickname` RPC limits)
- **Fecha de nacimiento** (date input, must be at least 13 years ago, must be ≤ today)
- **Contraseña** (password input, min 8 chars, with confirm-password field)

Submit calls a Server Action that:

1. Re-validates with Zod.
2. Calls `requireAdmin()` for defense-in-depth (the middleware already gated).
3. Upserts `profiles` with the new values (the row already exists for admins — they were promoted/seeded — so an `update`; for safety use `upsert`).
4. Calls `supabase.auth.updateUser({ password })` via the cookie-bound server client. This is the canonical way to add a password to an OAuth-only user.
5. Writes an audit log entry: `action = "complete_profile"`, `targetType = "user"`, `targetId = adminId`, `details = { fieldsSet: ["nickname", "date_of_birth", "password"] }`.
6. Returns `{ ok: true }`; the client redirects to `/`.

### What does NOT change

- F1's email+password sign-in form continues to work unchanged for admins who already have a password.
- `requireAdmin` / `requireSuperadmin` keep their current signatures. Onboarding doesn't run inside them; it runs in middleware.
- The `(dashboard)` layout still calls `requireAdmin`, but for users en route to onboarding the middleware redirects before the layout renders.

## 6. Phase F2.2 — Flutter App

**Why second:** isolating it lets us test/ship the admin unblock independently. Flutter changes don't gate admin verification.

### Behavioral changes

- After any successful sign-in (Google or email), `AuthService` triggers a load of the profile. A new `ProfileService.isProfileComplete()` getter checks the three conditions (condition 3 by querying `_client.auth.currentUser?.identities`).
- `HomeShell` (and any other top-level screen that requires a full account) wraps its child tree in a check: if `!isProfileComplete`, push `CompleteProfileScreen` and prevent backwards navigation until it resolves.
- `CompleteProfileScreen` is a new screen that reuses the styling and the validation logic of the signup section of `login_screen.dart`. It always shows the three inputs (nickname, DOB, password) for consistency with the admin panel onboarding; the nickname field is pre-populated with the current value when one exists, so the user can keep or refine it.

### Auto-creation cleanup

The current `ProfileService.ensureProfile(fallbackNickname: ...)` (called from `app.dart:_createProfileService`) silently creates a profile row whenever the user lacks one. With the new flow:

- `ensureProfile`'s auto-creation path is **removed**. If `getProfile()` returns null, the service stays in an "incomplete, no row yet" state; `CompleteProfileScreen` is what eventually inserts the row.
- This also means the throw-away nicknames stop happening for new Google users.

### Out of scope for F2.2

- Backfill of existing users whose profile was already auto-created with a garbage nickname. They get prompted to fix it on next sign-in (the nickname field will be pre-populated and editable).
- Localization for new strings beyond `app_es.arb` / `app_en.arb` updates (only the two locales currently shipped).
- Any change to `signUpWithEmail` — the email-signup form already collects all three pieces correctly.

## 7. Data Model

**No migrations.** The fields already exist:

- `profiles.nickname` (NOT NULL since `20260520000000_add_profiles.sql`)
- `profiles.date_of_birth` (added by `20260520000004_add_date_of_birth.sql`, nullable — stays nullable in the schema; completeness enforces it at the application layer)
- `auth.users.identities` (managed by Supabase Auth, queried via SDK)

**Audit log:** F2.1 adds one new value to the `AuditAction` union (`admin/lib/audit.ts`): `"complete_profile"`. No DB-side change since `admin_audit_log.action` is `text`.

## 8. Supabase Configuration

Google OAuth must be enabled at the project level (it already is, since the Flutter app uses it). The admin panel just needs the redirect URL added:

- Dashboard → Authentication → URL Configuration → **Redirect URLs**:
  - `http://localhost:3000/auth/callback` (dev)
  - `<production-admin-url>/auth/callback` (added when prod is decided)

This is a one-time user action documented in the F2.1 plan.

## 9. Risks and Trade-offs

- **Client-side completeness check duplication.** Both clients implement the same three conditions. A future change to the criterion would require synchronized edits. Accepted because the criterion is small (three booleans) and changes rarely; an RPC adds a round-trip without removing the duplication on the "what to ask in the form" side.
- **Existing Google users in Flutter discover the onboarding screen on next launch.** This is a one-time UX friction. Users who never come back stay incomplete, which is fine — they only need to complete if they want to sign in by password.
- **`updateUser({ password })` requires a current session.** This is fine for the onboarding flow because the user just signed in. It would fail if attempted from `service_role` (which is why we use the cookie-bound client in step 4 of §5).
- **Middleware does one extra column on its existing query.** Negligible cost; the role lookup is already happening.

## 10. Acceptance Criteria

For F2.1 (admin panel):
1. The login page shows a "Continuar con Google" button next to the existing form.
2. Clicking it redirects through Google, back to `/auth/callback`, and into the panel.
3. The seeded superadmin (`pabmariba@gmail.com`, Google-OAuth, no DOB, no password) is redirected to `/onboarding/complete-profile` instead of `/`.
4. Submitting valid nickname + DOB + password on that page updates `profiles`, sets the auth password, writes a `complete_profile` audit row, and redirects to `/`.
5. After completion, sign-out + sign-in with email + password works for the same user.
6. A user who is **already** complete (e.g., the test admin promoted in F2 with a manually-set password) never sees the onboarding screen.
7. A non-admin user who signs in with Google is signed out and redirected to `/login?error=forbidden` (the F2 forbidden flow still works).

For F2.2 (Flutter): defined in its own plan, but in spirit:
1. After Google sign-in, a user with an incomplete profile is sent to `CompleteProfileScreen` and cannot reach `HomeShell` until they finish.
2. The auto-created throw-away nickname behavior is gone (verified by deleting the profile of a test Google user and observing the onboarding screen appear on next launch).
3. A complete user signs in normally with no extra screens.

# Activate OCCCI membership workflows

Target project: `hlxcltqnlypptbykirzi`. Production app: https://occci-member-connect.vercel.app/

## Production state verified on 2026-10-11

Migrations 002–013 are applied to project `hlxcltqnlypptbykirzi`. Migrations 010, 011 and 012 were activated on 2026-10-10 UTC; migration 013 was activated on 2026-10-11 UTC. Audit identity capture and historical identity backfill were verified after 010. All eight live SQL checks after 013 returned true: its migration marker, one DM per district, one BM per branch, the exact manager and final-review procedures, unchanged Admin password guards, authenticated RPC/private helper permissions, unchanged district/branch access, and the existing BM-screened test financial request remaining pending. The currently assigned DM can finalize that request after a BM→DM role change, retaining the recorded BM screening and both role-specific audit entries. Membership and profile edits retain their distinct-reviewer rules. The upgrades do not approve financial requests or create invitations, employees or role assignments automatically.

Nine frontend and database regression suites pass, including manager uniqueness, current-DM financial approval after recorded BM screening, a full fresh-installer PostgreSQL run, scoped Team position tabs, all staff password confirmations, private staff invitation and Branch Cashier workflows. Production Site URL and the allowed OAuth redirect remain `https://occci-member-connect.vercel.app/`. Email sign-in identifies invited employees before the minimal employee application form; Google uses the existing provider when configured. Live app Google consent and physical iOS/Android testing remain outside this verification.

## Apply the database changes

For an existing project, apply any missing migrations from **supabase/migrations/002_workflow.sql** through **supabase/migrations/013_single_managers_financial_review.sql** in numerical order in the Supabase SQL Editor. This production project already has them. For a fresh project, run **supabase/install.sql** instead. The migrations run their changes in transactions. Do not rerun the legacy setup.sql alone after upgrading: it contains the former role policies.

The workflow migration preserves old branch Admin assignments as BM and old Admin Head assignments as cooperative Admin. A migration marker prevents this conversion from running again. Existing profiles remain pending unless already approved; complete legacy missing names/contact/address through the authorized edit workflow. Existing Active profiles without official account numbers must be reconciled in the SQL Editor before financial use.

In Authentication → URL Configuration, set Site URL to `https://occci-member-connect.vercel.app` and allow that URL for email confirmation redirects. Email confirmation remains required. Google sign-in is supported after the setup below. Facebook remains deferred.

## Temporary developer Admin bootstrap (initial setup)

The existing project already has the workflow schema. Run **supabase/migrations/003_staff_signup.sql** to add staff applications and the developer bootstrap. Configure its target privately in SQL Editor before running the migration:

```sql
select set_config('occci.bootstrap_email','REPLACE_WITH_VERIFIED_DEVELOPER_EMAIL',false);
```

Paste that statement and the migration into the same SQL Editor execution. The public repository intentionally contains no personal developer email. If the migration was run without a target, rerun it with this configuration; an unused empty bootstrap can be configured, while a consumed bootstrap is never restored.

- The privately configured, verified developer email receives temporary Admin access. If that account already exists and its email is confirmed, the migration activates Admin immediately. Otherwise register using **Cooperative Member**, confirm the email and sign in; the trusted Auth confirmation trigger activates Admin. No password or new Auth user is created by the migration.
- This is a one-time, revocable grant, with no arbitrary expiry date. When setup is finished, assign a permanent cooperative Admin in Team. That Admin removes the developer assignment. Re-running the migration, signing in again or changing Auth metadata never restores the consumed bootstrap.
- After migration 007, public registration offers **Cooperative Member only**. OCCCI employee registration requires an Admin-generated private link and separate single-use code. The employee provides a complete name, employee ID, contact and photo/visual avatar after a separate account-registration step. No applicant chooses a position or district/branch.
- Admin generates/revokes invitations in **CMS → Settings** and reviews applications in **Staff Applications**. Admin approves/rejects with notes and assigns Admin (global), DM (district), or BM/Branch Staff (BS)/BC (branch). Applicant email confirmation and a unique employee ID are required. Applicants see their status and review note; after approval, Refresh status or sign-in opens the authorized CMS.
- Staff-role approval and member account-number approval remain separate. Staff applicants are excluded from the member verification directory and membership metrics. Admin can adjust or remove approved assignments from Team.

## Assign a permanent cooperative Admin

The temporary developer Admin can assign a permanent Admin in CMS → Team. Alternatively, register and confirm the intended administrator's email through the app. In the project's trusted SQL Editor, replace the example email and run:

```sql
insert into public.occci_staff_assignments(user_id,role,branch_id,district)
select id,'Admin',null,null from auth.users where email='REPLACE_WITH_ADMIN_EMAIL'
on conflict(user_id) do update set role='Admin',branch_id=null,district=null;
```

Sign out and sign back in. Admin can manage Admin (global), DM (district) and BM/Branch Staff (BS)/BC (branch) from CMS → Team. Pending employee applications must be approved in Staff Applications first. BM/DM assignments require Admin password confirmation. User-editable Auth metadata cannot create staff access. The assigned DM performs final financial approval after BM screening; GM is not a separate role.

## Acceptance walkthrough

1. Register a member with last/first/middle names, full address, contact number, district and branch, email/password, and one of six visual avatars or a supported photo. Confirm email and sign in. If a photo could not be uploaded or is lost while confirming email, the avatar persists and Profile offers photo upload afterward.
2. Find the pending member in the assigned branch. BS/BC/BM/DM can assign their unique official ID/account number within their scope. BM screens the membership and the assigned district DM gives final approval. Assigning an ID alone does not activate membership. Admin views this workflow without approving it.
3. Staff requests permission to edit a member with Reason / Comments / Notes. A different assigned BM or DM reviews it. The requesting Staff then makes one logged edit after approval. Changes to the underlying profile invalidate stale permissions.
4. Staff uploads original private documents and proposes savings, loan balance/status, annual interest, record date, source reference and calendar payment schedules. BM screens the submission; the currently assigned DM for that district gives final approval through **Approve and synchronize**. Only then does the current member financial snapshot change. Stale simultaneous submissions are rejected.
5. Confirm the member sees their own approved snapshot, schedule and activity. Admin sees all activity, DM only their district, and BM/BS/BC only their branch; members see their own activity. Audit entries retain affected identities, before/after values and reviewers, including after a staff transfer.
6. Manage announcements/events/services with branch/district/cooperative scope. Published applicable content appears in the member app; drafts stay in CMS scope. Admin manages team assignments. The separate Branches menu is removed; database branches still drive registration, assignments and scoped reporting. Cooperative Reports shows Branch summary and Branch transactions under district tabs, limited to the current report filters and authorized locations.

## Data and deletion

There are no sample members, balances, loans or CMS announcements. The supplied branch directory contains **52 branches across six districts** (the supplied list has 52, despite the earlier reference to 51). It is an initial database import and can subsequently be maintained by authorized database administration. Navigation labels, roles, validation rules and brand assets remain application code.

Members and content are archived when deleted; branches are deactivated; role assignments can be removed. Financial snapshots are replaced only through reviewed document submissions. Audit history and source documents remain immutable for traceability. Password/email changes and permanent regulatory record deletion require trusted Supabase administration; they are not unrestricted CMS operations.

Private storage buckets: `occci-documents` (10 MB PDF/JPG/PNG) and `occci-avatars` (5 MB JPG/PNG). Browser-convertible photos are resized to JPEG; unsupported iOS photos fall back to the selected avatar. Signed document/photo links expire after five minutes. Staff documents are immutable after upload; failed submissions can leave orphaned uploads for trusted administrator cleanup.

The browser uses a public Supabase publishable key. Sensitive reads are protected by RLS; table writes are denied to browser roles and validated security-definer RPCs perform authorized changes. Service workers cache static assets only; authenticated API responses are not cached. Session tokens remain device-local and are cleared on sign-out. Never add a service-role key to frontend code.

## Verification

`node tests/frontend-workflow.mjs` checks rendering logic, registration fields/avatars, name/account search and role review controls. `tests/database-workflow.mjs` runs actual PostgreSQL via PGlite with minimal local Supabase Auth/Storage schema stubs. It checks migrations, permissions, branch isolation, approval sequences, account uniqueness, one-time edits and stale financial proposals. These are local checks; finish the acceptance walkthrough against the real project after applying SQL. The publishable key cannot apply schema migrations, and the live authenticated workflows cannot be verified before that step.

## Current upgrade: notes, saving, logs and Google sign-in

For the existing production database, run **supabase/migrations/004_activity_google.sql** after 003. This enables the activity RPC, actor name/role snapshots, manager access to all districts’ audit logs, safe self-assignment changes and Google profile completion. The publishable browser key cannot apply SQL or change Auth provider settings.

All CMS notes inputs use **Reason / Comments / Notes** and save to the existing audited note fields. Team saves canonicalize Admin to global scope, DM to district, and BM/Staff to an active branch. Editing locks the selected identity. New assignments require confirmed email and a completed profile. An Admin can save their own assignment, but cannot demote/remove the last remaining Admin. Assign another Admin before testing your own DM/BM/Staff access; a self-demotion changes your workspace immediately.

The database branch directory remains the source of truth for registration, staff assignments and district/branch reports. It has no separate workspace menu page. Branch transactions and savings/credit branch summaries use district tabs with the same access limits as the rest of Reports.

### Enable Google in the project dashboard

1. In Google Auth Platform, create a **Web application** OAuth client. Add `https://occci-member-connect.vercel.app` as an authorized JavaScript origin. Add `https://hlxcltqnlypptbykirzi.supabase.co/auth/v1/callback` as the authorized redirect URI. Configure the consent screen and, if in testing, add allowed test users.
2. In Supabase project `hlxcltqnlypptbykirzi`, go to **Authentication → Sign In / Providers → Google**, enable Google, and enter the Google client ID and client secret privately. Save. Never put the client secret in the frontend or public Git repository.
3. Under **Authentication → URL Configuration**, set Site URL and allowed redirect URL to `https://occci-member-connect.vercel.app/`. Add each intended preview/local URL separately when testing.
4. Open the app, select **Continue with Google**, and complete Google consent. The app uses PKCE, exchanges the returned code, and removes it from the URL. Finish in the same browser tab where sign-in started.
5. New Google accounts must complete name, contact, address, district/branch and avatar/photo details. Public registration is Member-only. Employees use an Admin-generated invitation and code; Admin assigns their position. Google confirmation does not grant staff roles, approve membership, or generate an official account number. Existing linked users retain their current assignments.

Before provider activation the Google button reports that setup is pending and email sign-in stays available. If 004 is missing, Google signup is blocked before redirect; existing email users can still read activity with the earlier RLS policies until the migration is applied.

Verify saving with both a valid assignment and a last-Admin demotion attempt. Verify an out-of-district action appears only to Admin and managers assigned to its district/branch. Verify both the activity table and activity RPC enforce these boundaries. Older audit rows resolve actor names where available; role snapshots are captured for new actions only. Activity loading pages through all accessible entries instead of cutting off at 250.

## Member approvals, edit permissions and original documents

Run **supabase/migrations/005_member_documents.sql** after 004 on the existing database. It preserves existing one-file references, adds attachment manifests to requests and approved snapshots, accepts other original document formats in the private bucket, and expands existing branch-scoped manager rules to DM.

Staff select Request information edit, enter a reason and wait. The assigned BM or DM approves in Approvals. The requesting Staff then opens the approved request and edits once. Requests are invalidated when member revision/scope changes. Older exact-change requests remain usable through their previous apply action. Direct Staff profile updates remain denied.

BS/BC/BM/DM can assign or correct an official account number in their scope without activating membership. BM screens a pending membership; final assigned-DM approval assigns its number and activates it; duplicate IDs are rejected without partial writes. Admin archive retains the profile and audit while removing it from active lists and revoking any staff assignment.

## Reports and Staff work activation

Run `supabase/migrations/006_reports.sql` in the SQL Editor after migration 005. Refresh the app. This creates the private report register and Staff draft/submission workflow. Staff sends work reports to BM; only BM approval publishes an approved report. Admin/DM monitor the authorized locations. Record official compliance acknowledgements manually after filing through the official system.

## Staff invitation upgrade

For the current OCCCI project with migrations 002–006 already installed, run **supabase/migrations/007_staff_invitations.sql** in SQL Editor. Do not rerun older migrations over the current role/policy definitions. The combined installer is for a fresh database. Migration 007 adds private invitation metadata, one-use hashed codes, employee IDs and BC assignments; it preserves existing records and pending applications. Existing pending applicants without an employee ID can have it recorded by Admin during review.

No extra provider or server secret is required. Email confirmation remains mandatory. Google sign-in uses the existing provider configuration when enabled. Do not change the Supabase Auth email/password requirements: credential creation is a separate identity step from the employee profile form.

Admin uses **Settings → Generate staff invitation** to copy the link and independent code. The link contains only the invitation UUID. Codes are shown once, excluded from REST metadata, and never included in app-generated audit snapshots. Invitations expire in 1–30 days, can be revoked before use, and are consumed atomically when a verified user submits the minimal employee application. Only Admin review assigns a position. BC has branch operational access and BM-reviewed work reports, without manager approval or role-assignment powers.


## Current upgrade: BM screening and assigned DM approval

For production with 008 already installed, apply **supabase/migrations/009_branch_approval_workflow.sql** before publishing the `branch-workflow-13` frontend. Do not rerun older migrations over these policies. `supabase/install.sql` includes all migrations and is for fresh projects. The previous upgrade notes describe their original setup; 009 supersedes their membership, financial and audit approval rules.

Admin approves employee applications and assigns positions, and can view all locations. New members and financial submissions undergo branch BM screening followed by final approval by the branch's assigned district DM. BM approval alone never publishes financial balances or activates a membership. BS/BC stay within their assigned branch; work reports remain personal and go to BM. Calendar rows and repeated installments replace the plain-text payment schedule.

Unfinished requests from the old DM/Admin workflow return to BM screening once, with the prior reviewer, note and review time retained in audit. No old request is automatically approved. Completed records stay intact. The migration narrows profiles, report records, audit records/RPCs and linked private documents to the current district/branch assignment. Email display is mirrored from trusted Auth records.

Validate the current behavior with `tests/branch-approval-workflow.mjs` (local PostgreSQL fixtures) and `tests/branch-approval-frontend.mjs` (native DOM forms). Confirm the 009 marker and procedure bodies in SQL Editor after applying.

## Current upgrade: affected users in activity logs

For production with 009 installed, apply **supabase/migrations/010_audit_subject_identity.sql**, then **supabase/migrations/011_admin_position_confirmation.sql** before publishing the `audit-identity-14` frontend. The fresh installer includes both. Existing role-assignment entries gain the affected person's name, position and employee ID from their recorded identity or linked profile. New audit entries capture those details separately from the Admin or staff member performing the action. Once captured, the identity is not refreshed by later renaming, transfer or archiving. Existing event scope and read policies remain intact.

The activity list shows **Name · Position** before opening an entry. Expanded details show **Affected user**, the employee ID when recorded, the acting user, notes and the before/after changes. Global actions without an affected account do not show a fictitious person. The staff directory also places the position beside the name.

The assigned DM receives an explicit **Final DM approval** section and **Approve and synchronize** action after recorded BM screening. Under migration 013, the currently assigned district DM may finalize a financial request that the same account submitted or screened before being reassigned from BM. No second DM is needed. The earlier BM screening remains recorded, and current scope/member/revision checks still apply. Profile edits and membership approvals keep their separate-reviewer rules. Admin remains unable to approve financial or membership requests.

Migration 011 protects both Team assignment and staff-application approval for BM/DM positions. Admin re-enters their own password; Supabase verifies it in a separate temporary session. A private, expiring confirmation binds that new password session to the exact target, position, branch/district and employee ID, and can be consumed only once. The original Admin session is retained. Passwords and tokens are excluded from CMS payloads, audit records and app storage; the temporary session is signed out after the action. Pending reviews and other positions use their existing workflows.

Test the native UI with `tests/audit-identity-frontend.mjs` and `tests/position-confirmation-frontend.mjs`, and the current database workflow with `tests/branch-approval-workflow.mjs`.

## Team workspace upgrade: all staff changes require Admin password

Apply **supabase/migrations/012_all_staff_password_confirmation.sql** after 011. The fresh installer includes it. Publish the `team-workspace-15` frontend after the database update.

**Team → OCCCI Staff** contains the staff directory. Admin's **Team → Staff Applications** holds the application queue. **Team → Cooperative Hierarchy** separates Admin, DM, BM, Branch Staff (BS) and BC into position tabs with district and dependent branch filters, compact location groups and 20 assignments per page. DM/branch readers retain their existing scope. Members remain in their separate directory. The four approval shortcuts below the banner are hidden in Reports and all Team sections; they remain available in the operational workspaces.

Admin re-enters their password for every staff assignment or approval, regardless of position, every assignment removal and every account archive. The database enforces this even for direct API calls. Removal confirmations also bind to current assignment and profile revision. A transfer or profile update after confirmation invalidates it. Every change needs its own new password session. Temporary confirmation sessions preserve the original Admin session and are signed out locally after the action. Private confirmation data never appears in CMS audit payloads. Pending review drafts and rejections do not grant access and retain their existing review path. The last-Admin safeguard and BM→DM membership/financial stages remain enforced.

## Current upgrade: one DM per district and one BM per branch

Apply **supabase/migrations/013_single_managers_financial_review.sql** after 012, then publish the `single-managers-16` frontend. The installer includes the same update. The migration stops if the existing database has duplicate DM or BM assignments; it never removes or selects employees automatically. Resolve any conflicts through the password-confirmed Team workflow before applying. Database unique indexes prevent a second DM for the same district or a second BM for the same branch, including changes made after a password challenge was issued. Empty positions are permitted during setup. Admin/BS/BC roles retain their current rules.

Occupied manager positions show a clear message and disable final assignment/approval. **Save as Pending** and **Reject** remain available because they grant no access. Editing the existing sole manager in the same location is allowed. An Admin must reassign the existing occupant before appointing a replacement. Every actual assignment/removal still requires a fresh Admin password and leaves an activity record.

For financial sync, the sole currently assigned district DM may give final approval after recorded BM screening even if it is the account that submitted or screened the request before becoming DM. **Approve and synchronize** is active for that eligible account. Pending requests without BM screening remain blocked; other districts, Admin, BM and branch staff cannot provide final approval. No balance or status is published until the DM submits the final decision. Both stage reviewers and their original activity entries remain recorded. Requests with changed member scope/status or a stale financial revision remain blocked. Profile edits and membership approvals continue to require separate reviewers.

Validate with `tests/manager-workflow.mjs`, `tests/manager-frontend.mjs`, `tests/position-confirmation-frontend.mjs` and `tests/branch-approval-frontend.mjs`. The manager SQL suite executes the fresh installer and tests upgrade rollback on existing duplicates, direct-write uniqueness, occupied-position races, verified transfers and role-change financial approval with stage logs/documents intact. Production verification should confirm the 013 marker, both valid unique indexes, exact manager/review procedures, unchanged password consumption and scope procedures, and private helper permissions.

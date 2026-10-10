# Activate OCCCI membership workflows

Target project: `hlxcltqnlypptbykirzi`. Production app: https://occci-member-connect.vercel.app/

## Apply the database changes

If the earlier Supabase connection already works, run **supabase/migrations/002_workflow.sql**, then **supabase/migrations/003_staff_signup.sql** in the Supabase SQL Editor. For a fresh project, run **supabase/install.sql** instead. Both files run their changes in transactions. Do not rerun the legacy setup.sql alone after upgrading: it contains the former role policies.

The workflow migration preserves old branch Admin assignments as BM and old Admin Head assignments as cooperative Admin. A migration marker prevents this conversion from running again. Existing profiles remain pending unless already approved; complete legacy missing names/contact/address through the authorized edit workflow. Existing Active profiles without official account numbers must be reconciled in the SQL Editor before financial use.

In Authentication → URL Configuration, set Site URL to `https://occci-member-connect.vercel.app` and allow that URL for email confirmation redirects. Email confirmation remains required. Google/Facebook are deliberately deferred.

## Temporary developer Admin and staff signup

The existing project already has the workflow schema. Run **supabase/migrations/003_staff_signup.sql** to add staff applications and the developer bootstrap. Configure its target privately in SQL Editor before running the migration:

```sql
select set_config('occci.bootstrap_email','REPLACE_WITH_VERIFIED_DEVELOPER_EMAIL',false);
```

Paste that statement and the migration into the same SQL Editor execution. The public repository intentionally contains no personal developer email. If the migration was run without a target, rerun it with this configuration; an unused empty bootstrap can be configured, while a consumed bootstrap is never restored.

- The privately configured, verified developer email receives temporary Admin access. If that account already exists and its email is confirmed, the migration activates Admin immediately. Otherwise register using **Cooperative Member**, confirm the email and sign in; the trusted Auth confirmation trigger activates Admin. No password or new Auth user is created by the migration.
- This is a one-time, revocable grant, with no arbitrary expiry date. When setup is finished, assign a permanent cooperative Admin in Team. That Admin removes the developer assignment. Re-running the migration, signing in again or changing Auth metadata never restores the consumed bootstrap.
- Registration offers **Cooperative Member** and **OCCCI Staff**. Staff selects a requested DM/BM/Staff position, district and branch. Everyone supplies full profile details and can use the six visual avatars/photo upload. Staff signup is an application and does not self-grant CMS access.
- Admin reviews pending staff applications in **CMS → Team → Staff applications**, approves/rejects with a note, and sees the decision in activity logs. Applicant email confirmation is mandatory for approval. DM gets district access; BM and Staff get the approved branch. Applicants can see their status and review note; after approval, Refresh status or sign-in opens their authorized CMS.
- Staff-role approval and member account-number approval remain separate. Staff applicants are excluded from the member verification directory and membership metrics. Admin can adjust or remove approved assignments from Team.

## Assign a permanent cooperative Admin

The temporary developer Admin can assign a permanent Admin in CMS → Team. Alternatively, register and confirm the intended administrator's email through the app. In the project's trusted SQL Editor, replace the example email and run:

```sql
insert into public.occci_staff_assignments(user_id,role,branch_id,district)
select id,'Admin',null,null from auth.users where email='REPLACE_WITH_ADMIN_EMAIL'
on conflict(user_id) do update set role='Admin',branch_id=null,district=null;
```

Sign out and sign back in. Admin can assign DM (district), BM (branch), and Staff (branch) from CMS → Team. Requested staff positions in signup metadata remain unprivileged until reviewed by Admin. Admin is also the GM approval role requested in this version; GM is not a separate sixth role.

## Acceptance walkthrough

1. Register a member with last/first/middle names, full address, contact number, district and branch, email/password, and one of six visual avatars or a supported photo. Confirm email and sign in. If a photo could not be uploaded or is lost while confirming email, the avatar persists and Profile offers photo upload afterward.
2. Sign in as a BM or Staff assigned to that branch. Find the pending member in Members, verify actual membership documents, and assign their unique official ID/account number. Admin can also approve. Other branches and Members cannot approve.
3. Staff proposes a member correction with a reason. A different BM (or Admin) reviews it. The requesting Staff applies the approved exact proposal once. Changes to the underlying profile invalidate stale proposals.
4. Staff uploads an actual private PDF/JPG/PNG and proposes savings, loan balance/status, annual interest, record date, source reference and payment schedule. A different DM in the district reviews it; a different Admin gives final approval. Only then does the current member financial snapshot change. Stale simultaneous submissions are rejected.
5. Confirm the member sees their own approved snapshot, schedule and activity. Verify a member in another branch cannot see those records. CMS shows activity for authorized branches. Audit entries retain before/after values and reviewers.
6. Manage announcements/events/services with branch/district/cooperative scope. Published applicable content appears in the member app; drafts stay in CMS scope. Admin can manage the database branch directory and team assignments. Branches is the last navigation item.

## Data and deletion

There are no sample members, balances, loans or CMS announcements. The supplied branch directory contains **52 branches across six districts** (the supplied list has 52, despite the earlier reference to 51). It is an initial database import and is subsequently editable in CMS. Navigation labels, roles, validation rules and brand assets remain application code.

Members and content are archived when deleted; branches are deactivated; role assignments can be removed. Financial snapshots are replaced only through reviewed document submissions. Audit history and source documents remain immutable for traceability. Password/email changes and permanent regulatory record deletion require trusted Supabase administration; they are not unrestricted CMS operations.

Private storage buckets: `occci-documents` (10 MB PDF/JPG/PNG) and `occci-avatars` (5 MB JPG/PNG). Browser-convertible photos are resized to JPEG; unsupported iOS photos fall back to the selected avatar. Signed document/photo links expire after five minutes. Staff documents are immutable after upload; failed submissions can leave orphaned uploads for trusted administrator cleanup.

The browser uses a public Supabase publishable key. Sensitive reads are protected by RLS; table writes are denied to browser roles and validated security-definer RPCs perform authorized changes. Service workers cache static assets only; authenticated API responses are not cached. Session tokens remain device-local and are cleared on sign-out. Never add a service-role key to frontend code.

## Verification

`node tests/frontend-workflow.mjs` checks rendering logic, registration fields/avatars, name/account search and role review controls. `tests/database-workflow.mjs` runs actual PostgreSQL via PGlite with minimal local Supabase Auth/Storage schema stubs. It checks migrations, permissions, branch isolation, approval sequences, account uniqueness, one-time edits and stale financial proposals. These are local checks; finish the acceptance walkthrough against the real project after applying SQL. The publishable key cannot apply schema migrations, and the live authenticated workflows cannot be verified before that step.

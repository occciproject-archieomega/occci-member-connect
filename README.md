# OCCCI Member Connect

Responsive installable PWA for Metro Ormoc Community Multi-Purpose Cooperative, with a member app and a role-scoped cooperative CMS. Uses bundled Poppins fonts, OCCCI branding and six visual temporary avatars. Static HTML/CSS/JavaScript; no build step.

- Admin → District Manager → Branch Manager → Branch Staff (BS) / Branch Cashier (BC) → Member, with database-enforced district/branch assignments.
- Member-only public registration; private, code-verified employee invitations; Admin-assigned Admin/DM/BM/Staff/BC positions; and a one-time verified-email developer Admin bootstrap.
- Full member registration, email confirmation and membership verification with unique official account numbers.
- Staff request permission → BM or DM approval → one logged profile edit.
- Multiple private original documents (PDF, Word, Excel, scans or other files) → BM screening → assigned DM approval → savings/loan snapshot synchronization.
- Branch-filtered typo-tolerant name search and exact account-number lookup.
- Editable CMS announcements/events/services, branch directory, team assignments and scoped activity logs.
- Activity entries identify the affected member or employee as well as the acting user. Captured names, positions and employee IDs remain readable after role changes, transfers, profile renaming and archiving.
- Staff directory names include their positions. BM/DM assignments and staff approvals require a fresh, single-use Admin password confirmation; saving a pending review grants no access.
- No sample operational data or role simulation.

Serve `dist/` over HTTP locally (`python -m http.server 3000 --directory dist`). Vercel configuration publishes `dist/` from the linked GitHub repository. Follow [SUPABASE-SETUP.md](SUPABASE-SETUP.md) to activate the database workflow; the browser publishable key cannot perform migrations.

Validation:

```sh
node --check dist/app.js
node --check dist/ui.js
node --check dist/sw.js
node tests/frontend-workflow.mjs
npm install --prefix /tmp/occci-sql-test @electric-sql/pglite
PGLITE_MODULE=/tmp/occci-sql-test/node_modules/@electric-sql/pglite/dist/index.js node tests/database-workflow.mjs
```

The PostgreSQL checks use local minimal Supabase schema stubs. Real email delivery, device photo handling, signed storage links and live authenticated acceptance require verification in the configured Supabase project.

The latest upgrade adds district-first Branch Directory, unified reason/comments/notes fields, scoped audit visibility for Admin/DM/BM (enforced by migration 009), safe assignment saving, and Google PKCE sign-in with required profile completion. Apply `supabase/migrations/004_activity_google.sql` after migration 003 and enable the Google provider as described in [SUPABASE-SETUP.md](SUPABASE-SETUP.md). Google OAuth credentials belong in Supabase provider settings, never in frontend code.

## Member/document upgrade

Migration `005_member_documents.sql` introduced membership and document operations. Migration 009 now requires BM screening followed by assigned DM activation, with branch-scoped ID assignment for BS/BC/BM/DM, permission-first Staff profile editing and multiple original attachments. ID assignment alone does not activate membership. Archive is an Admin soft archive with activity retained. Native form tests reproduce and prevent the `form.action` handler-name collision that blocked CMS submissions.

Original supporting files remain private: up to 10 files per request, 10 MB per file and 50 MB total. Reviewers see every original filename; approved snapshots retain all attachments. The optional record reference is a ledger/form/statement label and defaults to filenames. Documents download through short-lived signed links.

Run native form regression tests with:
```sh
npm install --prefix /tmp/occci-dom-test jsdom
JSDOM_MODULE=/tmp/occci-dom-test/node_modules/jsdom/lib/api.js node tests/cms-form-submission.mjs
```

## Reporting workspace

The CMS header has four approval portals: Staff Applications (Admin only), New Members, Review Staff Edits and Review Actual Balances. New Members opens the pending-member queue; regular workspace navigation remains in the sidebar and mobile menu. Branch summary displays one district at a time through district tabs, respecting report filters and the manager's assigned scope. Network totals and CSV exports keep the selected report scope.

Member search supports name matching, exact account/user IDs, district and branch filters, and name/account/district/branch sorting. Record update logs use 20 rows per page; returning to an open edit form preserves values and selected documents.

Reports is available to Admin, DM, BM, Staff and BC. Staff and BC receive a personal My Reports page. Staff saves a daily, seven-day weekly or calendar-month report with actual transaction totals and private source documents, then submits it to the assigned BM. BM approval publishes an immutable approved record to the managerial report register. Returned reports can be corrected and resubmitted. Every action is recorded in scoped report logs.

Admin sees all locations. DM sees assigned district branches. BM sees the assigned branch. Managers have savings/credit snapshots, daily/weekly/monthly CMS activity and approved staff transaction summaries, report status, CSV exports, and registers for assembly, district and cluster reports. The Annual compliance tab has been removed. Daily/weekly/monthly totals are calculated separately. Approved member snapshots are not historical accounting ledgers or audited financial statements. The app does not submit filings to CDA.

Apply `supabase/migrations/006_reports.sql` after migration 005. It is repeatable and adds report types, managerial registers, staff staging, immutable events and private `occci-reports` storage. Members have no report access. Staff has access only to their own work reports. Files are limited to 10, 10 MB each, 50 MB total.

Verification: `node tests/frontend-workflow.mjs`, `node tests/cms-form-submission.mjs`, `node tests/reports-frontend.mjs`, `node tests/database-workflow.mjs`, `node tests/reports-workflow.mjs`. DOM tests require jsdom; database tests require @electric-sql/pglite, with `JSDOM_MODULE` / `PGLITE_MODULE` pointing to their modules when installed outside the repo.

## Admin-invited employee registration

Apply `supabase/migrations/007_staff_invitations.sql` after 006 on an existing project. Use `supabase/install.sql` for a fresh database; use only the new migration for an upgrade. Migration 007 is transactional and repeatable, preserves existing users/assignments/applications, and disables the old requested-position approval endpoint. Existing pending applications require an employee ID and an Admin-selected position when reviewed.

1. Admin opens **Settings → Generate staff invitation**, enters an internal label, validity (1–30 days) and reason/comments/notes. The dialog shows a private registration link and an independent code once. Copy both and give them separately to the employee. Admin can revoke an unused invitation in Settings.
2. The employee opens the HTTPS link in any browser and verifies the code. The private form offers account registration through Google or email/password, with no sign-in tab. Email confirmation resumes registration in the same browser through PKCE; the employee application asks only for last/first/optional middle name, employee number/ID, contact number and a photo or one of the six visual avatars.
3. Submission consumes the invitation once and creates a pending application without any requested role or scope. It grants no CMS access. Admin reviews it in **Staff Applications** and assigns Admin (global), DM (district), or BM/Branch Staff/BC (branch), or rejects it with notes.
4. Approved BC users have branch-scoped operational access like Staff: permission-first profile corrections, original-document submissions and personal work reports sent to BM. BC cannot assign roles or approve staff/report applications. Member accounts and employee IDs remain separate identifiers.

Only a salted SHA-256 code digest is stored. Admin can read invitation metadata, never its code/hash. The application revalidates the code, expiry and revocation inside the transaction that consumes it. Codes never appear in URLs, auth metadata or audit snapshots. Verified invitation context is kept in tab session storage for up to 30 minutes to survive Google PKCE and is cleared after submission/cancellation.

Additional verification: `node tests/staff-invitations-frontend.mjs` (jsdom) and `node tests/staff-invitations-workflow.mjs` (@electric-sql/pglite). These cover invalid/expired/revoked/used invitations, employee ID uniqueness, no public staff self-registration, approval and role escalation boundaries, all five assigned positions, BC branch/report workflows, and the private registration form.


## Pending staff reviews and separate directories

Apply `supabase/migrations/008_staff_review_drafts.sql` after 007 before deploying this update. **Save and Approve** grants the selected role through the existing approval endpoint. **Save as Pending** stores the position, workplace, employee ID and notes in a review draft; the applicant remains Pending, the submitted profile stays intact, and no staff assignment is created. Reopening the application restores the draft. Both actions are recorded in the activity log. Rejection can also be prepared without finalizing it.

The visible position name is **Branch Staff (BS)**; the stored role identifier remains `Staff` so existing permissions and assignments continue to work. **Members** lists cooperative members; **OCCCI Staff** lists approved personnel with their employee IDs and assigned workplaces. Pending employee applications remain in Staff Applications.

Financial sync includes members without a snapshot, including pending member registrations. These rows say **No financial records yet. Update and verification required.** Membership approval and an official account number remain prerequisites for balance submissions. Verified zero balances are displayed as zero; missing records never imply a zero savings balance or an absence of loans. Member records use 20 rows per page and retain branch scope.

Review actions are visible for the assigned BM at Pending and for the assigned district DM at BM approved. Admin has read-only access to membership and financial approvals. BS/BC submissions require BM screening; a BM-originated balance submission records its screening and goes to an independent DM for final approval. Stage explanations are visible to other readers. Final synchronization and verified snapshot dialogs are read-only; updated balances require a fresh document submission. File references and downloads remain private.

Additional checks: `node tests/staff-financial-workflow.mjs` (jsdom) and the extended staff-invitations SQL suite. Supabase email registration uses the [documented PKCE signup fields](https://github.com/supabase/auth/blob/master/openapi.yaml) only when email confirmation is enabled.


## Current branch approval workflow (009)

Apply `supabase/migrations/009_branch_approval_workflow.sql` **after 008 and before publishing the matching frontend**. This transactional, repeatable migration supersedes the earlier membership and financial approval rules. It narrows profile, activity, report and original-document access on the server; browser filters alone are not the permission boundary.

- Admin reads all districts, approves employee applications and assigns positions. Admin cannot approve new members, submit financial balances or finalize financial synchronization.
- DM reads only their assigned district and finalizes BM-screened membership/financial requests from its branches.
- BM reads only their assigned branch and screens its new members and financial submissions.
- BS/BC read only their branch's member/financial records and maintain their own branch work reports. Profile corrections remain permission-first.
- New membership stays Pending and the proposed official account number stays in the screening request until the assigned DM approves. Editing a pending member's status cannot bypass activation.
- DM financial approval writes the verified savings, loan status, interest, payment schedule and original references atomically. The member profile displays that verified snapshot. Stale revisions and same-person final reviews are rejected.

Unfinished legacy financial requests (`Pending` / `DM approved` under workflow version 1) return to BM screening. Earlier DM reviews are retained in a scoped migration event; no balance is published automatically. Completed snapshots stay intact. Reapplying 009 does not reset requests under the current workflow.

CMS activity provides All, Admin, DM, BM, BS and BC tabs with date sorting and 20 entries per page, within the reader's permitted scope. Active notification counts are orange; zero counts remain gray. Staff directories and application reviews display the Auth-derived email; user metadata cannot spoof it. The duplicate cooperative name at the bottom of the sidebar is removed.

The payment editor uses date pickers and editable rows. Generate weekly, fortnightly, monthly or quarterly installments; successive generations append, and rows can be edited or removed. Monthly installments preserve the first due-day, clamping only shorter months, including leap years. Up to 360 payments are accepted and validated before document upload. No financial snapshot means “Not recorded,” not a fabricated zero.

Current workflow verification:
```sh
PGLITE_MODULE=/tmp/occci-sql-test/node_modules/@electric-sql/pglite/dist/index.js node tests/branch-approval-workflow.mjs
JSDOM_MODULE=/tmp/occci-dom-test/node_modules/jsdom/lib/api.js node tests/branch-approval-frontend.mjs
```
The database suite uses non-production fixtures and covers scope isolation through tables, RPCs and private original documents, Auth email mirroring, legacy migration, BM/DM stages, pending activation, no Admin approval, atomic publication and stale submissions. The native DOM suite covers review controls, activity tabs, counters, staff email, calendar controls and exact submission payloads. Earlier SQL suites retain their historical migration checks.

# OCCCI Member Connect

Responsive installable PWA for Metro Ormoc Community Multi-Purpose Cooperative, with a member app and a role-scoped cooperative CMS. Uses bundled Poppins fonts, OCCCI branding and six visual temporary avatars. Static HTML/CSS/JavaScript; no build step.

- Admin → District Manager → Branch Manager → Branch Staff (BS) / Branch Cashier (BC) → Member, with database-enforced district/branch assignments.
- Member-only public registration; private, code-verified employee invitations; Admin-assigned Admin/DM/BM/Staff/BC positions; and a one-time verified-email developer Admin bootstrap.
- Full member registration, email confirmation and membership verification with unique official account numbers.
- Staff request permission → BM or DM approval → one logged profile edit.
- Multiple private original documents (PDF, Word, Excel, scans or other files) → BM screening → assigned DM approval → savings/loan snapshot synchronization.
- One-screen member financial overview: savings, paid-up share capital, outstanding loan principal and the next unpaid installment.
- Branch Cashier member search, actual receipt entry, automatic balance/schedule updates and an immutable scoped payment history.
- Branch-filtered typo-tolerant name search and exact account-number lookup.
- Editable CMS announcements/events/services, team assignments and scoped activity logs, with database-backed branches for registration and reports.
- Activity entries identify the affected member or employee as well as the acting user. Captured names, positions and employee IDs remain readable after role changes, transfers, profile renaming and archiving.
- Member activity starts behind a compact expandable button. Dates and entries stay hidden until opened; individual entries show their details on demand, with 20 entries per page and pagination keeping the panel open.
- Team contains the OCCCI Staff directory, Staff Applications and Cooperative Hierarchy. Hierarchy positions have district/branch filters, compact grouped rows and 20 assignments per page. Reports and Team omit the four banner approval shortcuts.
- Staff directory names include their positions. Every Admin staff assignment, staff-application approval, assignment removal and account archive requires a fresh, single-use Admin password confirmation; saving a pending review grants no access.
- No sample operational data or role simulation.

Serve `dist/` over HTTP locally (`python -m http.server 3000 --directory dist`). Vercel configuration publishes `dist/` from the linked GitHub repository. Follow [SUPABASE-SETUP.md](SUPABASE-SETUP.md) to activate the database workflow; the browser publishable key cannot perform migrations.

Validation:

```sh
node --check dist/app.js
node --check dist/ui.js
node --check dist/finance.js
node --check dist/sw.js
node tests/frontend-workflow.mjs
npm install --prefix /tmp/occci-sql-test @electric-sql/pglite
PGLITE_MODULE=/tmp/occci-sql-test/node_modules/@electric-sql/pglite/dist/index.js node tests/database-workflow.mjs
```

The PostgreSQL checks use local minimal Supabase schema stubs. Real email delivery, device photo handling, signed storage links and live authenticated acceptance require verification in the configured Supabase project.

The activity upgrade adds unified reason/comments/notes fields, scoped audit visibility for Admin/DM/BM (enforced by migration 009), safe assignment saving, and Google PKCE sign-in with required profile completion. Apply `supabase/migrations/004_activity_google.sql` after migration 003 and enable the Google provider as described in [SUPABASE-SETUP.md](SUPABASE-SETUP.md). Google OAuth credentials belong in Supabase provider settings, never in frontend code.

## Member/document upgrade

Migration `005_member_documents.sql` introduced membership and document operations. Migration 009 now requires BM screening followed by assigned DM activation, with branch-scoped ID assignment for BS/BC/BM/DM, permission-first Staff profile editing and multiple original attachments. ID assignment alone does not activate membership. Archive is an Admin soft archive with activity retained. Requests whose member is archived or no longer accessible are excluded from synchronization/approval lists, overview totals and notification counters, and cannot be opened for review. Their stored requests, documents, financial snapshots and audit entries remain intact. Native form tests reproduce and prevent the `form.action` handler-name collision that blocked CMS submissions.

Original supporting files remain private: up to 10 files per request, 10 MB per file and 50 MB total. Reviewers see every original filename; approved snapshots retain all attachments. The optional record reference is a ledger/form/statement label and defaults to filenames. Documents download through short-lived signed links.

Run native form regression tests with:
```sh
npm install --prefix /tmp/occci-dom-test jsdom
JSDOM_MODULE=/tmp/occci-dom-test/node_modules/jsdom/lib/api.js node tests/cms-form-submission.mjs
JSDOM_MODULE=/tmp/occci-dom-test/node_modules/jsdom/lib/api.js node tests/member-record-frontend.mjs
```

The member-record regression exercises native expansion and paging, archived/missing profile exclusion, branch/district scopes, notification counts, preserved history and password-confirmed archive followed by the actual data reload. The member activity/archive frontend update requires no additional SQL migration beyond the existing schema.

## Reporting workspace

The CMS header has four approval portals: Staff Applications (Admin only), New Members, Review Staff Edits and Review Actual Balances. New Members opens the pending-member queue; regular workspace navigation remains in the sidebar and mobile menu, without a separate Branches page. Both Branch summary and Branch transactions display one district at a time through district tabs, respecting report filters and the manager's assigned scope. Network totals and CSV exports keep the selected report scope.

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

Review actions are visible for the assigned BM at Pending and for the assigned district DM at BM approved. Admin has read-only access to membership and financial approvals. BS/BC submissions require BM screening; a BM-originated balance submission records its screening and goes to the assigned district DM for final approval. Stage explanations are visible to other readers. Final synchronization and verified snapshot dialogs are read-only; updated balances require a fresh document submission. File references and downloads remain private.

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

## Team workspace and password confirmation upgrade

Apply `supabase/migrations/012_all_staff_password_confirmation.sql` after 011 before publishing the `team-workspace-15` frontend. OCCCI Staff is now inside Team; member records remain in Members. Team sections separate the staff directory, application queue and hierarchy. Admin, DM, BM, Branch Staff (BS) and BC have individual hierarchy tabs within the reader's permitted district/branch scope. Choosing a district restricts branch choices. Position and location changes retain independent paging and logged review rules.

All staff positions now require Admin password re-entry in Team and on application approval. Removing an assignment and archiving an account also require confirmation. Removal confirmations bind to the current assignment and profile revision, so a changed account requires a fresh confirmation. Password sessions are single-use across assignments, removals and archives. Scope policies, the last-Admin rule, pending drafts and BM→DM financial approvals remain intact.

`tests/team-workspace-frontend.mjs` verifies the relocated navigation, hidden banner shortcuts, position/location filters, scoped personnel, search and pagination through native clicks. `tests/position-confirmation-frontend.mjs` verifies native password dispatch for all positions and removals. `tests/branch-approval-workflow.mjs` tests the full migrations through 012 against actual local PostgreSQL, including direct-API blocking, all position approvals, action binding, stale removal/archive prevention, the last-Admin rule and audit preservation.

## One manager per location and financial approval after reassignment

Apply `supabase/migrations/013_single_managers_financial_review.sql` after 012 before publishing the `single-managers-16` frontend. A district has at most one DM and a branch has at most one BM. Database unique indexes enforce this across Team changes, staff approvals and direct writes. Occupied positions show clear feedback before Admin password confirmation. Existing managers may retain their own position, and an Admin can move or remove an assignment with the existing password and audit requirements. Vacant positions remain allowed during setup. Pending application drafts do not reserve a manager position.

A Financial sync request with recorded BM screening can receive final approval from the currently assigned district DM even if that same account submitted or screened it before being reassigned. The recorded BM stage is retained; no second DM is required. Current district authority, original documents, member status, financial revision and required review notes still apply. No pending request is automatically approved. Profile edits and membership approvals retain their separate-reviewer rules.

`tests/manager-workflow.mjs` exercises the 013 upgrade, then compares the latest upgraded procedures with the fresh installer against local PostgreSQL fixtures. It verifies manager limits, atomic failures when occupancy changes after confirmation, password-protected transfers, BM-to-DM final finance approval, unchanged balance publication timing, audits/documents, scope restrictions, stale/repeated/missing-screening rejection and migration safety/idempotency. `tests/manager-frontend.mjs` checks native manager selection, conflict messages, pending/reject controls, the enabled final approval action and its real RPC payload.

## Member dashboard and Branch Cashier receipts (014)

Production activation completed on **2026-10-11 UTC** after user approval. All 12 live database checks passed and the anonymous receipt endpoint denied access. See [activation details and verification evidence](SUPABASE-SETUP.md#member-dashboard--cashier-activation-status). No operational payment was posted for testing.

The `compact-workspace-21` presentation update uses **Workspace** throughout CMS. Role badges and the labeled branch selector share a compact toolbar, with aligned page gutters and tighter section spacing. Narrow screens stack the toolbar controls and retain 44-pixel touch targets. Approval shortcuts are hidden on Reports, Team, Content, Activity and Settings. Content has no workspace branch selector and shows records available within the user's database-authorized scope; a branch filter selected on another page does not silently restrict its list. Activity retains its workspace branch selector; Settings has no branch selector. The existing authorization, approvals and financial workflows are unchanged.

Apply `supabase/migrations/014_member_dashboard_cashier.sql` after 013 to activate cashier records. The fresh installer includes the same update. The frontend remains usable before activation: existing verified savings/loan records are available, share capital is labeled **Not yet verified**, and cashier posting stays disabled with an activation message.

Members see savings, paid-up share capital, outstanding loan principal and their next unpaid installment in one compact, mobile-responsive overview. Overdue installments take priority; paid/cancelled installments are excluded, partial payments show the amount remaining, and a loan without a schedule is labeled explicitly. No snapshot means **Awaiting verified records**, never an invented zero. Payment schedules and receipt history expand on demand, with 20 receipts per page.

The assigned BC opens **Cashier**, searches their branch's members by name or exact account/ID, and selects a member. The form records the official receipt, payment date, principal, interest, fees, savings deposit, share capital contribution and notes. It previews the resulting balances before submission. Principal alone reduces the loan principal; savings and share capital contributions increase their respective balances. Principal plus interest can be allocated to one unpaid installment; fees and deposits never pay an installment. Partial payments are retained as paid-to-date amounts. Extra principal can be recorded without allocating an installment. This does not recalculate future installments: the branch must review the documented schedule. Unpaid installments remain visible even when principal reaches zero, with **Schedule review required** rather than an unsupported claim that nothing is due. The schedule editor also accepts documented paid-to-date amounts for opening records.

Only an Active member with an official ID and a DM-verified financial snapshot can receive a posted receipt. Share capital starts unknown on legacy snapshots; an actual opening amount must pass BM screening and DM approval before BC contributions are enabled. Leaving the optional opening-capital field blank preserves the existing value. Initial records and later document corrections retain BM→DM review; an authorized BC posts new actual receipts directly against those verified records.

The database locks the member and financial revision and commits the receipt, balances, installment update and activity log together. Overpayment, stale balances, future dates, invalid amounts, duplicate official receipts and cross-branch submissions fail. A repeated identical client reference returns the existing receipt without another update; a changed payload cannot reuse it. Case-insensitive official receipt numbers are unique within a branch. Posted receipts have no edit/delete endpoint. Original documents and references stay attached to the financial snapshot. Corrections use the existing document-review workflow; a pending older snapshot cannot overwrite a newer cashier payment.

Receipt reads respect both the captured branch and the member's current scope: members read their own receipts, BC/BS/BM read their permitted branch, DM reads their district, and Admin reads all. Other staff and managers have a read-only **Cashier receipts** button on verified member records. Database policies and RPC checks enforce these limits independently of the UI.

### Share capital policy

No current official OCCCI percentage of deposits or loan payments was verified. [CDA's Republic Act 9520, Article 75](https://cda.gov.ph/issuances/republic-act-9520/) places the capital build-up program in each cooperative's bylaws. The Act's ownership limit is not a payment deduction rate. This implementation uses documented opening balances and the actual capital amount on each receipt; it applies no assumed percentage, automatic interest calculation or deduction. An OCCCI bylaw/product policy is required before adding percentage-based allocation.

### Verification

```sh
npm install --prefix /tmp/occci-finance-tests @electric-sql/pglite jsdom
PGLITE_MODULE=/tmp/occci-finance-tests/node_modules/@electric-sql/pglite/dist/index.js node tests/cashier-workflow.mjs
JSDOM_MODULE=/tmp/occci-finance-tests/node_modules/jsdom/lib/api.js node tests/cashier-frontend.mjs
```

These use disposable local PostgreSQL and DOM fixtures. They cover fresh install and repeatable upgrade, nullable capital, BM/DM publication, actual receipt arithmetic, installment allocation, full and partial payoff, retries, receipt uniqueness, stale review rejection, private ledger permissions, archived/member-role/branch isolation, preserved audits/documents, native selection/search/submission, previews, history pagination without losing drafts and pre-activation UI. No real member payment is posted by these tests.

The registration-photo-22 update provides drag, zoom and position controls beside a cropped avatar preview. Photos up to 20 MB are decoded locally and saved as 512-pixel square JPEGs (under the 5 MB storage limit). Cropped drafts are bound to the account and retained in the same browser for up to 24 hours during email confirmation or upload retries. Middle name and photo remain optional; employee IDs normalize spaces around punctuation and show specific validation errors. No database migration is required.

The account-access-23 update checks the signed-in user’s non-archived profile before loading workspace records. Missing/archived profiles receive **Account not Registered** and clear the saved login: no sign-out button, avatar, assignment label, workspace toolbar or member/CMS navigation. Incomplete registration remains available, with workspace navigation hidden until completion. Transient network errors retain a distinct Retry screen rather than declaring an account deleted.

Manager-invites-24 adds staff invitation Settings for Admin, DM and BM. The server derives the scope from the acting manager’s assignment, rather than trusting browser-supplied district/branch fields. Metadata listing and revocation follow district/branch boundaries. Admin retains employee approval and position assignment; manager invitations grant no staff access. Apply migration 015 before using this feature.

Re-registration-25 adds **Register again** for archived members. Supabase keeps the original email identity when a cooperative profile is archived; a second signup cannot replace that identity. The explicit flow verifies the existing email/password, then calls the owner-only re-registration RPC. The profile returns as a pending Member without an account number, staff privileges or old photo. BM/DM approval is required again. Financial and audit history is retained; outstanding requests and prior staff applications are closed with activity logs. Apply migration 016 to activate this flow.

Deleted staff can also register again using a fresh invitation link and code, then **Previously deleted staff account? Register again**. Existing credentials verify ownership; the invitation is checked server-side before the profile becomes an incomplete applicant. Staff submit employee details and require a new Admin decision and assignment. No old role is restored, and invalid/expired/used invitations leave the profile archived.

Staff-recovery-26 recognizes existing accounts at the invitation credential step, supports fresh invitation links after a deleted-account screen, and adds a staff-specific registration entry. Migration 017 additionally accepts formerly approved staff or accounts with an audited Admin removal of a staff assignment while their profile remained present. Active assignments and pending applications cannot be reset. Fresh-code verification and new Admin approval remain mandatory.

Operating-units-27 replaces the workspace branch-only selector with a district-first **Operating units** selector. Choosing a district immediately scopes members, approval queues, financial synchronization, reports and activity to its branches. A dependent Branch selector then narrows the view within that district. Changing district clears stale branch selections and pagination; All assigned districts resets the location scope. Options follow existing Admin/DM/BM/BS/BC permissions. No SQL migration is required.

Staff application/profile labels now use **First name Middle name Last name . Employee number**. Legacy headings that included a numeric employee identifier as the middle-name component display it at the end once; stored identity records are not modified by this presentation fix.

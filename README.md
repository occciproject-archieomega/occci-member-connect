# OCCCI Member Connect

Responsive installable PWA for Metro Ormoc Community Multi-Purpose Cooperative, with a member app and a role-scoped cooperative CMS. Uses bundled Poppins fonts, OCCCI branding and six visual temporary avatars. Static HTML/CSS/JavaScript; no build step.

- Admin → District Manager → Branch Manager → Staff → Member, with database-enforced district/branch assignments.
- Separate Member/OCCCI Staff signup, Admin-reviewed DM/BM/Staff applications, and a one-time verified-email developer Admin bootstrap.
- Full member registration, email confirmation and membership verification with unique official account numbers.
- Staff request permission → BM or DM approval → one logged profile edit.
- Multiple private original documents (PDF, Word, Excel, scans or other files) → DM review → Admin approval → savings/loan snapshot synchronization.
- Branch-filtered typo-tolerant name search and exact account-number lookup.
- Editable CMS announcements/events/services, branch directory, team assignments and scoped activity logs.
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

The latest upgrade adds district-first Branch Directory, unified reason/comments/notes fields, cooperative-wide audit visibility for Admin/DM/BM, safe assignment saving, and Google PKCE sign-in with required profile completion. Apply `supabase/migrations/004_activity_google.sql` after migration 003 and enable the Google provider as described in [SUPABASE-SETUP.md](SUPABASE-SETUP.md). Google OAuth credentials belong in Supabase provider settings, never in frontend code.

## Member/document upgrade

Migration `005_member_documents.sql` enables DM membership approval, branch-scoped ID assignment for Staff/BM/DM/Admin, permission-first Staff profile editing and multiple original attachments. ID assignment alone does not activate membership. Archive is an Admin soft archive with activity retained. Native form tests reproduce and prevent the `form.action` handler-name collision that blocked CMS submissions.

Original supporting files remain private: up to 10 files per request, 10 MB per file and 50 MB total. Reviewers see every original filename; approved snapshots retain all attachments. The optional record reference is a ledger/form/statement label and defaults to filenames. Documents download through short-lived signed links.

Run native form regression tests with:
```sh
npm install --prefix /tmp/occci-dom-test jsdom
JSDOM_MODULE=/tmp/occci-dom-test/node_modules/jsdom/lib/api.js node tests/cms-form-submission.mjs
```

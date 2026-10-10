# OCCCI Member Connect

Responsive installable PWA for Metro Ormoc Community Multi-Purpose Cooperative, with a member app and a role-scoped cooperative CMS. Uses bundled Poppins fonts, OCCCI branding and six visual temporary avatars. Static HTML/CSS/JavaScript; no build step.

- Admin → District Manager → Branch Manager → Staff → Member, with database-enforced district/branch assignments.
- Separate Member/OCCCI Staff signup, Admin-reviewed DM/BM/Staff applications, and a one-time verified-email developer Admin bootstrap.
- Full member registration, email confirmation and membership verification with unique official account numbers.
- Staff profile proposals → BM approval → single logged application.
- Actual source documents → DM review → Admin approval → savings/loan snapshot synchronization.
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

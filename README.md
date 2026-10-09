# OCCCI Member Connect — UI / UX preview

Responsive, static front-end prototype for a cooperative member PWA and administrator CMS.

## Run locally

Serve the `dist` directory with any static HTTP server, for example `python -m http.server 8000 --directory dist`. There are no build dependencies. `dist/index.html`, `styles.css`, and `app.js` contain the layout, theme, and interactive workflows. The web app manifest and service worker provide the installable app shell.

## Demo scope

Member accounts, passbook and statement export; loan calculator, three-step application and tracker; receipt submission; membership card preview; goals; appointments; assistance and support threads; document and profile change requests; announcements, event registration, and a business directory.

The admin CMS includes member search and pagination, application review, receipt review, announcement and event editing, business listing moderation, member support replies, reports and an audit export, and demo branch settings.

Records are sample data in JavaScript memory. Reload resets the session. Demo mode is not authentication or access control. No financial posting, payment processing, real messaging, uploads, or official benefit eligibility are implemented. Selected files retain filenames only. The membership QR is intentionally pending verified member identity.

## Backend phase

Replace the in-memory data adapter with authenticated server operations. Add Supabase authentication, RLS, private document storage, staff roles, verified member/accounting integration, and server-controlled approval workflows before using actual member data. Restrict service-worker caching to the public app shell.

Branding uses the user-supplied OCCCI logo; all people, financial values, vendors, and events are illustrative.

## Branches and mobile delivery

The directory contains 52 user-supplied branches across six districts (10, 6, 9, 9, 9, 9). Ormoc retains its existing internal BR-01 reference so demo accounts and request queues stay assigned correctly. The admin directory supports district filtering and search; all branch selectors are grouped by district. Branch references are internal demo identifiers. Addresses other than the previously provided Ormoc entry await supplied details. The truncated “Guiuan Branc” entry is stored as “OCCCI Guiuan Branch.”

This deliverable is the web/PWA front end, with a responsive design shared by the mobile app. Native Android/iOS projects, store submissions, verified branch access, and native installation packages are future phases.

## Mockup-aligned design revision

The member dashboard now follows the reference screen order: large OCCCI header, greeting, compact navy savings card, four quick actions, payment card, and transaction list. Loan screens place the application tracker and cooperative service tiles ahead of the calculator on mobile. The admin CMS uses a larger centered sidebar logo, stronger typography, bigger navigation and metric icons, and aligned table avatars.

Poppins Regular, SemiBold, and Bold are bundled under `dist/fonts`, with their SIL Open Font License, so typography does not depend on a third-party font request. The public PWA shell caches these fonts alongside its UI assets.

Branch layout update: mobile header controls use a separate spaced row; page actions stack below titles; member directory uses branch groups and cards. Team page lists Admin Head, Admin and Staff slots per branch. Role preview restricts Admin/Staff workspace scope to an assigned branch, while Admin Head can switch branches. This is a front-end demonstration, not verified authentication or backend authorization. Added sample members for Baybay, Tacloban and Naval.

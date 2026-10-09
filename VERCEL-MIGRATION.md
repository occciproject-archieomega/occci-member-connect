# OCCCI Vercel migration

Target team: occciproject-archieomega
Suggested project name: occci-member-connect
Fetched source commit: d00d9cd08fb24005ae0fc23b41b6c8f37fc7da69

This project serves the existing dist directory directly. It needs no framework, build command, install step, or environment variables for the current front-end prototype. vercel.json configures the output directory.

After authorized Vercel access is available, select the target team, inspect existing projects to avoid replacing an unrelated app, and deploy this source. Verify the index, logo, bundled fonts, manifest, service worker, and mobile/member/admin routes.

This remains a front-end demonstration with session-only sample data. Hosting migration does not add Supabase, verified login, financial integration, or native mobile packaging. The existing Site remains available until the Vercel deployment is verified. Preserve restricted access when configuring the new project.

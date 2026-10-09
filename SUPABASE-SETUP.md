# Supabase connection

The app uses browser REST APIs and the supplied publishable key in dist/supabase-config.js. No Next.js build environment is required because this is a static site.

1. Run supabase/setup.sql in the project's Supabase SQL Editor before allowing registration.
2. In Authentication > URL Configuration set Site URL to https://occci-member-connect.vercel.app and allow that URL for redirects.
3. Email authentication is enabled and confirmation is required. Member account (on Profile or the preview bar) offers sign-in, registration and profile editing.
4. Create verified staff accounts and assign them using the SQL Editor. Members cannot self-assign staff roles or change branch/membership approval fields.

This integration stores real auth accounts and member profiles. Financial screens and admin role switching remain a separate demo; they are not connected to the database. Do not infer financial or admin authority from the demo role switch. Photo uploads are not stored by this integration; six avatar choices are supported.

No service-role key is used. Service worker caches static code only and never caches Supabase API responses. Session tokens are device-local and are cleared on sign-out.

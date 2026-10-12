# Activate OCCCI Huddle

The deployed application contains the Sessions panel and LiveKit integration. The session database is required to create/list sessions. LiveKit is required only when joining an audio/video call.

1. In Supabase SQL Editor, run `supabase/migrations/024_occci_huddle.sql` if it has not been applied, then run `supabase/migrations/025_occci_huddle_sessions.sql`. Both migrations can safely be run again. Alternatively, run `supabase/huddle-update.sql`, which includes both in the correct order. Use these migrations for an existing OCCCI database; the complete installer is for a fresh database.
2. Create or select your [LiveKit Cloud project](https://cloud.livekit.io/), then get its connection URL, API key and API secret from the project settings. A self-hosted LiveKit server with HTTPS/WSS can also be used.
3. In the [OCCCI Vercel project's environment settings](https://vercel.com/occciproject-archieomega/occci-member-connect/settings/environment-variables), add these **Production** variables:

   | Variable | Value |
   | --- | --- |
   | `LIVEKIT_URL` | Your secure `wss://…` project connection URL |
   | `LIVEKIT_API_KEY` | Your LiveKit API key |
   | `LIVEKIT_API_SECRET` | Your LiveKit API secret, saved as a Secret/sensitive variable |

   The existing OCCCI Supabase URL and publishable key are already configured for the server. No Supabase service-role key is used. Keep LiveKit credentials server-only; never add a `NEXT_PUBLIC_` prefix or paste the secret into chat or the source repository.
4. Redeploy the latest `main` commit so the functions receive the new environment variables.
5. Sign in as Admin, DM, BM, Branch Staff or BC. Open **OCCCI Huddle** in the top header, enter a session title and select **Create session**. Its card appears in **Sessions**, and a generated code is shown to the host. Create another session to verify that both appear without automatically joining either one. Copy the invitation, then open its portal in a second active OCCCI account and enter the special code. Enable the microphone/camera and check audio in both directions, host mute/allow, screen sharing, chat, and data cards.

## Behavior

- All five official positions can create multiple sessions. Creation requires only a title, with no operating-unit selector. It generates a unique code and does not join the host or activate media. Sessions can be created, listed and ended before LiveKit credentials are configured.
- All active OCCCI accounts see the active Sessions panel. Tapping a session opens a code-entry form. Only the host sees its generated code or invitation controls on the panel. A code from another session cannot join the selected session. New invitation links identify the session and require its code to be entered; older code-containing links remain compatible.
- Active cooperative members and assigned staff from any district/branch can join with the correct code. A session invitation does not grant access to another unit's records. Unregistered, pending and deleted accounts cannot join.
- The panel checks for session updates every 12 seconds and has a Refresh button. New sessions created by the current user appear immediately; ended and expired sessions disappear. The refresh updates the panel without replacing an in-progress title or code form.
- The host can mute individual attendees or all attendees, and allow microphones again. Enabling permission never turns on someone else's microphone. Users enable their own microphone/camera.
- Shared operating-unit data is calculated by Supabase. Cards are visible only to staff authorized for that unit; members receive no cooperative financial summaries. Data is not broadcast as an unrestricted LiveKit packet.
- Session chat is visible only to authorized participants. The UI displays the 60 most recent messages.
- Meetings remain connected when navigating within the app or opening Sessions to create another meeting. The active-call bar returns to the call. Leaving the current call is required before joining another. Sign-out, account removal and assignment changes stop the room and release media. Session codes expire after 12 hours, and ending a meeting invalidates its code. Ending one session does not end the host's other sessions.
- Room creation, joining, moderation, ending, leaving and data sharing are recorded in the CMS audit activity. No automatic recording or transcript capture is enabled.
- Screen capture depends on the browser/device. The browser asks the user which screen, tab or window to share. Microphone/camera permissions and audio playback may require a user tap, especially on iOS.

## Developer verification

`npm ci --ignore-scripts` installs the pinned server SDK. `npm run check:huddle` verifies the server endpoint and token grants.

The frontend and SQL workflow checks are in `tests/huddle-frontend.mjs` and `tests/huddle-workflow.mjs`; these use the existing JSDOM and PGlite test environment. They do not make production conference calls or alter actual member records.

The LiveKit browser SDK is loaded only when joining, at the pinned version 2.22.4 from its documented CDN. Creating/listing sessions and regular OCCCI pages do not download it. API responses and credentials are excluded from the PWA's offline cache. A failed service-side join rolls back attendance without ending the saved session. Ending persists in Supabase first; if media-service cleanup is unavailable, clients leave when their authorization check detects the ended session.

References: [LiveKit JavaScript SDK](https://docs.livekit.io/reference/client-sdk-js/), [server SDK](https://docs.livekit.io/reference/server-sdk-js/), [room-service API](https://docs.livekit.io/reference/other/roomservice-api/), [Vercel Node.js Functions](https://vercel.com/docs/functions/runtimes/node-js).

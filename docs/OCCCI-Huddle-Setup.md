# Activate OCCCI Huddle

The deployed application contains the LiveKit integration. It requires the following setup before actual audio/video meetings can begin.

1. In Supabase SQL Editor, run `supabase/migrations/024_occci_huddle.sql` once. It can safely be run again. Use migration 024 for an existing OCCCI database; the complete installer is for a fresh database.
2. Create or select your [LiveKit Cloud project](https://cloud.livekit.io/), then get its connection URL, API key and API secret from the project settings. A self-hosted LiveKit server with HTTPS/WSS can also be used.
3. In the [OCCCI Vercel project's environment settings](https://vercel.com/occciproject-archieomega/occci-member-connect/settings/environment-variables), add these **Production** variables:

   | Variable | Value |
   | --- | --- |
   | `LIVEKIT_URL` | Your secure `wss://…` project connection URL |
   | `LIVEKIT_API_KEY` | Your LiveKit API key |
   | `LIVEKIT_API_SECRET` | Your LiveKit API secret, saved as a Secret/sensitive variable |

   The existing OCCCI Supabase URL and publishable key are already configured for the server. No Supabase service-role key is used. Keep LiveKit credentials server-only; never add a `NEXT_PUBLIC_` prefix or paste the secret into chat or the source repository.
4. Redeploy the latest `main` commit so the functions receive the new environment variables.
5. Sign in as Admin, DM, BM, Branch Staff or BC. Open **Huddle**, create a session and copy its invitation. In a second signed-in account, open the link and enter the special code. Enable the microphone/camera and check audio in both directions, host mute/allow, screen sharing, chat, and data cards.

## Behavior

- All five official positions can host. Admin can host cooperative-wide, district or branch meetings. DM can host their district or its branches. Branch positions host their own branch.
- Active cooperative members and assigned staff can join using the code when the meeting's operating unit includes their account. An invitation does not grant access to another unit's records.
- The host can mute individual attendees or all attendees, and allow microphones again. Enabling permission never turns on someone else's microphone. Users enable their own microphone/camera.
- Shared operating-unit data is calculated by Supabase. Cards are visible only to staff authorized for that unit; members receive no cooperative financial summaries. Data is not broadcast as an unrestricted LiveKit packet.
- Session chat is visible only to authorized participants. The UI displays the 60 most recent messages.
- Meetings remain connected when navigating within the app. Sign-out, account removal and assignment changes stop the room and release media. Session codes expire after 12 hours, and ending a meeting invalidates its code.
- Room creation, joining, moderation, ending, leaving and data sharing are recorded in the CMS audit activity. No automatic recording or transcript capture is enabled.
- Screen capture depends on the browser/device. The browser asks the user which screen, tab or window to share. Microphone/camera permissions and audio playback may require a user tap, especially on iOS.

## Developer verification

`npm ci --ignore-scripts` installs the pinned server SDK. `npm run check:huddle` verifies the server endpoint and token grants.

The frontend and SQL workflow checks are in `tests/huddle-frontend.mjs` and `tests/huddle-workflow.mjs`; these use the existing JSDOM and PGlite test environment. They do not make production conference calls or alter actual member records.

The LiveKit browser SDK is loaded on demand at the pinned version 2.22.4 from its documented CDN, so regular OCCCI pages do not download it. API responses and credentials are excluded from the PWA's offline cache.

References: [LiveKit JavaScript SDK](https://docs.livekit.io/reference/client-sdk-js/), [server SDK](https://docs.livekit.io/reference/server-sdk-js/), [room-service API](https://docs.livekit.io/reference/other/roomservice-api/), [Vercel Node.js Functions](https://vercel.com/docs/functions/runtimes/node-js).

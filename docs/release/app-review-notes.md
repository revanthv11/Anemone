# App Review notes (template)

*Copy everything below the line into App Store Connect › the version › App Review Information › Notes, and fill in the sign-in fields there. Replace each `[…]`. The demo server and the reviewer's account come from `scripts/review-server/` ([`review-server.md`](review-server.md)): the server must be reachable from the internet for the whole review and holds only media that's legally free to stream (public domain or Creative Commons Attribution). `scripts/review-server/check.sh` checks it the day you submit.*

---

**What Anemone is**

Anemone is a client for Jellyfin, a free, open-source media server that people install on their own computer or NAS. Anemone has no content of its own: it shows and plays the movies, shows and music on the user's Jellyfin server. It's free software (GPL-3.0); the source is at https://github.com/revanthv11/Anemone.

**How to sign in**

We've set up a Jellyfin server with public-domain and Creative Commons media for review:

- Server address: `https://anemone-review.revanth.us`
- User name: `reviewer`
- Password: `[REVIEWER_PASSWORD from ~/.anemone-agents/review-server/.env]` (also in the Sign-in Information fields)

1. Open Anemone. On "Add a server", type the server address above and choose Connect.
2. Choose the user `reviewer`, or "Other user", and sign in with the user name and password.
3. Home shows rows such as Continue Watching and Recently Added. Select any title, then Play.

**Things to try**

- Movies: "Big Buck Bunny" and "Sintel" (Blender's open movies), "Night of the Living Dead" (1968) and "The General" (1926).
- Shows: "Caminandes", three short episodes that play one after another; Max Fleischer's "Superman" shorts; the first episodes of "The Beverly Hillbillies".
- Music: Kevin MacLeod's "Classical Sampler" and "Jazz Sampler", Josh Woodward's "Ashes" and "The Shade From Our Trees", and Kimiko Ishizaka's "The Open Goldberg Variations".
- Settings › About shows the version, the GPL and the licenses of the software Anemone includes.

**About the content**

All media on the review server is in the public domain or under a Creative Commons Attribution license: Blender Foundation's open movies and Caminandes shorts (CC BY), Night of the Living Dead (1968), The General (1926), His Girl Friday (1940), Plan 9 from Outer Space (1957), the Fleischer Superman shorts (1941) and the first season of The Beverly Hillbillies (1962) (public domain in the United States), Kevin MacLeod's and Josh Woodward's music (CC BY), and Kimiko Ishizaka's Open Goldberg Variations (CC0). `[Paste media/LICENSES.md, which fetch-media.sh writes, with each title's source and license.]` In normal use, people only see what's on their own server.

**Network security (App Transport Security)**

The app sets `NSAllowsArbitraryLoads` because users type the address of their own home server, which is usually plain HTTP on their local network (Jellyfin's default is http://<address>:8096) and can't be listed in advance. The app connects only to the servers the user adds, has no web views, and tries HTTPS first when the user doesn't type a scheme. `[Paste the longer justification from docs/release/ats.md if asked.]`

**Encryption**

The app uses only the HTTPS and Keychain encryption built into tvOS (`ITSAppUsesNonExemptEncryption` is `NO`).

**Contact**

`[name]`, `[phone]`, `[email]`

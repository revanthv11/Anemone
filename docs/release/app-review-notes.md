# App Review notes (template)

*Copy everything below the line into App Store Connect › the version › App Review Information › Notes, and fill in the sign-in fields there. Replace each `[…]`. The demo server and the reviewer's account are the developer's to set up: the server must be reachable from the internet for the whole review and hold only media that's legally free to stream (public domain or Creative Commons).*

---

**What Anemone is**

Anemone is a client for Jellyfin, a free, open-source media server that people install on their own computer or NAS. Anemone has no content of its own: it shows and plays the movies, shows and music on the user's Jellyfin server. It's free software (GPL-3.0); the source is at https://github.com/revanthv11/Anemone.

**How to sign in**

We've set up a Jellyfin server with public-domain and Creative Commons media for review:

- Server address: `[https://demo-server.example.com]`
- User name: `[reviewer user name]`
- Password: `[reviewer password]` (also in the Sign-in Information fields)

1. Open Anemone. On "Add a server", type the server address above and choose Connect.
2. Choose the user `[reviewer user name]`, or "Other user", and sign in with the user name and password.
3. Home shows rows such as Continue Watching and Recently Added. Select any title, then Play.

**Things to try**

- Movies: `[a title on the demo server, e.g. "Night of the Living Dead" (1968, public domain)]`.
- Shows: `[a series, e.g. "Pioneer One" (CC BY-NC-SA)]`; its episodes play one after another.
- Settings › About shows the version, the GPL and the licenses of the software Anemone includes.

**About the content**

All media on the review server is `[public domain or Creative Commons; list each title and its license]`. In normal use, people only see what's on their own server.

**Network security (App Transport Security)**

The app sets `NSAllowsArbitraryLoads` because users type the address of their own home server, which is usually plain HTTP on their local network (Jellyfin's default is http://<address>:8096) and can't be listed in advance. The app connects only to the servers the user adds, has no web views, and tries HTTPS first when the user doesn't type a scheme. `[Paste the longer justification from docs/release/ats.md if asked.]`

**Encryption**

The app uses only the HTTPS and Keychain encryption built into tvOS (`ITSAppUsesNonExemptEncryption` is `NO`).

**Contact**

`[name]`, `[phone]`, `[email]`

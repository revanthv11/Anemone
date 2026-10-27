# App Transport Security

Both the app (`App/Info.plist`) and the Top Shelf extension (`TopShelf/Info.plist`) set `NSAllowsArbitraryLoads`. This page is the reasoning, and the text to give App Review when they ask about it.

## For App Review

Paste this into the App Review notes, or into a reply if App Review asks why the app allows insecure loads:

> Anemone is a client for Jellyfin, a free media server that people install on their own computer or NAS at home. The first time the app opens, the user types the address of their own server. Most home Jellyfin servers are reached over plain HTTP: Jellyfin listens on http://<address>:8096 by default, and a device on a home network can't easily get a publicly trusted TLS certificate. Others are reached through a VPN, a home DNS name or a dynamic DNS name, again often over HTTP.
>
> Every user's server has a different address, typed by the user, so the app can't name them in `NSExceptionDomains`. `NSAllowsLocalNetworking` is meant for local names (unqualified host names and `.local`), so it would still block servers reached through a VPN or by a DNS name over HTTP. The app therefore sets `NSAllowsArbitraryLoads`.
>
> The app only connects to servers the user adds: their Jellyfin server for sign-in, browsing, artwork and video streams. It has no web views and loads no third-party content over HTTP. When the user types an address without `http://` or `https://`, the app tries HTTPS first and uses HTTP only when HTTPS doesn't answer.

## Why not something narrower

- **`NSExceptionDomains`:** needs the domains at build time. Every user's server is different.
- **`NSAllowsLocalNetworking`:** is meant for local names (unqualified host names and `.local`). It misses `http://jellyfin.home.example:8096`, a Tailscale or WireGuard name over HTTP, and other addresses people use for home servers. On iOS 10 and later, adding it next to `NSAllowsArbitraryLoads` also makes the system ignore `NSAllowsArbitraryLoads`, so the two can't be combined.
- **`NSAllowsArbitraryLoadsForMedia`:** covers AVFoundation media only, not the API requests and artwork the app loads from the same server.

Swiftfin, the official Jellyfin app for Apple platforms, sets `NSAllowsArbitraryLoads` for the same reason.

## The extension

The Top Shelf extension reads Continue Watching and Next Up from the same user-chosen server (Phase 5e), so it needs the same exception. Its `Info.plist` points here.

## Local network

`NSLocalNetworkUsageDescription` in `App/Info.plist` explains the system's local network prompt where the system shows one: "Anemone connects to the Jellyfin servers you add, including ones on your home network." When the add-server screen starts listing servers found by discovery (Phase 1, waiting on Apple's multicast entitlement), say so in it too, e.g. "Anemone finds Jellyfin servers on your home network and connects to the ones you add."

# Export compliance

`App/Info.plist` sets `ITSAppUsesNonExemptEncryption` to `NO`, so App Store Connect doesn't ask the encryption questions for each build, and no documents are needed (including for France).

## Why `NO` is right today

Anemone uses only encryption that's built into Apple's operating system, which is exempt:

- **HTTPS** to the user's Jellyfin server, through `URLSession` and AVFoundation (and, inside jellyfin-sdk-swift, Network.framework). The app has no TLS library of its own; swift-nio-ssl and OpenSSL aren't linked.
- **The Keychain**, for the server access token.
- **SHA-256** of a salted profile PIN (`PINHash`, through CryptoKit). Hashing for authentication isn't encryption of data.

## When to look again

Answer the questions again, and change the key if needed, when a change brings its own cryptography:

- **The MPV engine (Phase 4).** MPVKit's FFmpeg builds can include their own TLS library (OpenSSL, GnuTLS or mbedTLS) for HTTPS streams. If the shipped build links one, the app uses non-exempt standard encryption: set the key to `YES`, answer App Store Connect's questions, and file the year-end self-classification report with BIS that they point to.
- **Any new dependency** that links a crypto or TLS library, or code that encrypts data itself.

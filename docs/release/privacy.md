# Privacy

Anemone collects no data. Everything it sends goes to the Jellyfin server the user adds, which the user runs or chooses; the developer runs no server and receives nothing. Apple counts data as collected only when it leaves the device in a way the developer or a third-party partner can access, so the App Privacy answer is **Data Not Collected**.

## What leaves the device, and where it goes

All of it goes to the user's own Jellyfin server, and nowhere else:

- the user's name and password when signing in (the server returns an access token, kept in the Keychain);
- a device name and a random device ID, which Jellyfin needs to tell sessions apart;
- browsing requests, artwork and video streams;
- playback progress and watched state, so the server can resume and mark items played;
- home-row and library settings the user chooses to save on the server.

Remote trailers open the YouTube app; Anemone itself doesn't contact YouTube. There's no analytics, advertising, crash-reporting or tracking SDK.

## App Store Connect › App Privacy

- **Data collection:** "No, we do not collect data from this app."
- **Tracking:** none.
- **Privacy policy URL:** required for every app. `privacy-policy.md` is a draft to publish, for example as a page in the public repo.

## Privacy manifests

| File | Says |
|---|---|
| `App/PrivacyInfo.xcprivacy` | No tracking, no tracking domains, no collected data. Required-reason APIs: UserDefaults (`CA92.1`, the app's own settings, and `1C8F.1`, the settings it leaves for the Top Shelf in the App Group) and file timestamps (`C617.1`, Nuke's artwork disk cache reading the access dates of its files in the app's container to evict the oldest). |
| `TopShelf/PrivacyInfo.xcprivacy` | No tracking, no collected data. Required-reason APIs: UserDefaults (`1C8F.1`, reading the App Group's settings). |

Both sit in synchronized folders, so Xcode copies them into the app and the extension without a project change.

Update them when code starts using another [required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api):

- **System boot time** (`ProcessInfo.systemUptime`, `mach_absolute_time()`), **disk space** or **active keyboards**: add the category with the reason that fits.
- **A new dependency**: if it ships its own `PrivacyInfo.xcprivacy` (swift-nio does), Xcode includes it; if it doesn't and uses a required-reason API, declare that use in the app's manifest.

Before each submission, check the merged result: in Xcode's Organizer, right-click the archive and choose **Generate Privacy Report**.

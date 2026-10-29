# Release checklist

How Anemone goes to TestFlight and the App Store. Most of it is App Store Connect work only the developer can do. The other pages in this folder:

- [`ats.md`](ats.md): why the app allows plain HTTP, with text for App Review.
- [`export-compliance.md`](export-compliance.md): why `ITSAppUsesNonExemptEncryption` is `NO`, and when to look again.
- [`privacy.md`](privacy.md): the privacy manifests and the App Privacy answers.
- [`privacy-policy.md`](privacy-policy.md): a privacy policy to publish.
- [`eula.md`](eula.md): the custom GPL EULA, a draft.
- [`app-review-notes.md`](app-review-notes.md): the App Review notes, a template.
- [`review-server.md`](review-server.md): the demo Jellyfin server App Review signs in to, and `scripts/review-server/`, which builds it.
- [`../../scripts/tag-build.sh`](../../scripts/tag-build.sh): tags the source of each build.
- [`../../scripts/update-licenses.sh`](../../scripts/update-licenses.sh): refreshes the license texts in Settings › About.

## Once, before the first upload

- [ ] **Bundle ID.** Confirm `com.revanthv11.anemone` (shared later with the iOS app), then register it, the Top Shelf extension's `com.revanthv11.anemone.topshelf`, and the App Group and Keychain group Top Shelf uses (Phase 5e) in the developer account.
- [ ] **Multicast entitlement**, only if server discovery ships in the build: request `com.apple.developer.networking.multicast` from Apple, then add it to the app's entitlements (`docs/PLAN.md`, Phase 1).
- [ ] **App record.** Create the app in App Store Connect, platform tvOS, with that bundle ID.
- [ ] **Source.** Keep https://github.com/revanthv11/Anemone public: the GPL needs every shipped build's source to be available, and Settings › About points there.
- [ ] **Privacy policy.** Fill in and publish `privacy-policy.md`; enter its URL in App Information.
- [ ] **Support URL.** For example https://github.com/revanthv11/Anemone/issues.
- [ ] **App Privacy.** Answer "Data Not Collected" (`privacy.md`).
- [ ] **License agreement.** Review `eula.md`, fill it in and paste it as the custom EULA in App Information.
- [ ] **Age rating.** Answer the questionnaire. Anemone has no content of its own and shows only what's on the user's server.
- [x] **Artwork.** The Monogram app icon (layered, small and large), the App Store icon (1280×768) and the Top Shelf image (wide, and wide 2x) are in `App Icon & Top Shelf Image.brandassets`, rendered from `docs/brand/monogram` by `scripts/render-brand-assets.mjs` (Phase 0).
- [x] **Review server.** https://anemone-review.revanth.us, built with `scripts/review-server/` (`review-server.md`): legally free media, a reviewer account that can only browse and play, behind a Cloudflare Tunnel. Keep it up for every review.

## Every build

1. **Start clean** on `main`, with CI green on the commit you'll archive.
2. **Bump the build number** (`CURRENT_PROJECT_VERSION`, and `MARKETING_VERSION` for a new version) in the project, commit and push. Every target shares them.
3. **Licenses.** Run `scripts/update-licenses.sh` after any dependency change. It warns about a package that NOTICE.md doesn't credit or that has no license text. Commit what it changes.
4. **Archive** in Xcode: scheme Anemone, destination Any tvOS Device, Product › Archive. Leave `ANEMONE_SEERR` unset: Seerr isn't in 1.0 (`docs/PLAN.md`, Decisions).
5. **Check privacy.** In the Organizer, right-click the archive › Generate Privacy Report, and check it against `privacy.md`.
6. **Upload.** Distribute App › App Store Connect. Untick "Manage Version and Build Number", so the uploaded build number is the committed one; otherwise pass the uploaded number to the next step with `--build`.
7. **Tag the source:** `scripts/tag-build.sh --archive <path to the .xcarchive> --push`. It refuses a commit that isn't on GitHub yet or a build number that's already tagged. Settings › About names the same tag.
8. **TestFlight.** Add "What to Test" and the testers. Export compliance is answered by `ITSAppUsesNonExemptEncryption`.

## Every App Store submission

- [ ] **Screenshots** of the current UI (Apple TV: 1920×1080 or 3840×2160). A set from 28 October 2026 is listed in [`screenshots/README.md`](screenshots/README.md), the PNGs kept out of git; retake after visible changes.
- [ ] **Description, keywords and promotional text.** The app's name is Anemone; "Jellyfin" names the server it works with.
- [ ] **App Review notes** from `app-review-notes.md`, with the review server's address, the reviewer's sign-in and `media/LICENSES.md` filled in. Run `scripts/review-server/check.sh` against the public address the day you submit: it checks the server is up, the sign-in works and the media is there.
- [ ] **Look at Settings › About** in the build: the version, the GPL, Wholphin and Swiftfin, and every package.
- [ ] **Check export compliance** again if the MPV engine or another library with its own TLS has landed (`export-compliance.md`).

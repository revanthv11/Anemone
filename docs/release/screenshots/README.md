# App Store screenshots

The PNGs aren't in git (`.gitignore` leaves them out, at 1 MB each); the set below sits in the maintainer's checkout and goes straight to App Store Connect. Apple TV, 1920×1080 PNG without alpha, taken on 28 October 2026 in the tvOS 26 simulator ("Apple TV 4K (3rd generation) (at 1080p)") signed in to the review server as the reviewer, with the purple theme and Anemone's player controls. App Store Connect takes up to ten per language, so leave one out (06 or 11 are the least telling).

| File | Screen |
|---|---|
| `01-home.png` | Home: Continue Watching and Recently Added in Movies, Sintel's backdrop behind the header |
| `02-movies.png` | The Movies library's Recommended tab, with its tab row |
| `03-movie.png` | Sintel's page: details, Resume, the actions and the People row |
| `04-player.png` | Anemone's player controls over Sintel, with the Speed and Max bitrate menus |
| `05-shows.png` | The Shows library's Recommended tab, episode cards for Caminandes and The Beverly Hillbillies |
| `06-series.png` | Caminandes' season page with its three episodes |
| `07-music.png` | The Music library's Recommended tab |
| `08-album.png` | The Open Goldberg Variations' album page with its songs |
| `09-now-playing.png` | Music Now Playing with the queue |
| `10-search.png` | Search for "bunny" with Big Buck Bunny in Movies |
| `11-appearance.png` | Settings › Appearance with the eight themes |

Retake them with a throwaway UI test (the recipe in PLAN.md 6a) after any visible change; the media is the review server's, all public domain or Creative Commons Attribution (`scripts/review-server/media.txt`).

# The App Review demo server

App Review needs to sign in to something. Anemone has no content of its own, so the developer keeps a Jellyfin server on the internet with media that is legally free to stream, and a reviewer account on it, for as long as a build is in review. The App Review notes ([`app-review-notes.md`](app-review-notes.md)) give its address and the sign-in.

`scripts/review-server/` makes the server reproducible, so it can be rebuilt on any machine with Docker in an hour, most of it downloading:

| File | What it does |
|---|---|
| `media.txt` | The titles, where each comes from on the Internet Archive, and its license. The only place to add or drop a title. |
| `fetch-media.sh` | Downloads them into `media/` in Jellyfin's folder layout, writes `.nfo` files for the shows, and writes `media/LICENSES.md`, the attribution to paste into the notes. Resumable. |
| `docker-compose.yml`, `Caddyfile` | Jellyfin 12.4 with `media/` mounted read-only; with `--profile https`, Caddy in front with a Let's Encrypt certificate. |
| `setup.sh` | Finishes Jellyfin's startup wizard, names the server, adds the three libraries, creates the reviewer account with a browse-and-play policy, hides the administrator from the sign-in screen, scans, and signs in as the reviewer to check. Rerunnable. |
| `check.sh` | The day-of-submission check from anywhere: reachable, reviewer signs in, isn't an admin, sees the media, a movie streams. |
| `cloudflare-tunnel.sh` | Puts a Cloudflare Tunnel in front, for an https address on one of the developer's zones without opening a port: creates the tunnel, adds the DNS record, writes cloudflared's config, and on a Mac runs it as a login item. |
| `.env.example` | The settings and secrets, copied to `.env`, which git ignores along with `config/`, `cache/` and `media/`. |

## What's on it, and why it's allowed

Everything in `media.txt` is either in the public domain in the United States or under a Creative Commons Attribution license, which allows streaming it to anyone, including for a commercial app's review. Nothing on the server has a NonCommercial or NoDerivatives clause, and nothing depends on an argument about its status. Keep it that way when adding a title: a film being on the Internet Archive isn't proof of anything, since anyone can upload there. `LICENSES.md` carries the attribution the CC licenses ask for.

| Title | Why it's free |
|---|---|
| Big Buck Bunny (2008), Elephants Dream (2006), Sintel (2010), Tears of Steel (2012), Cosmos Laundromat (2015) | Blender Foundation's open movies, released by their maker under CC BY 3.0 (Cosmos Laundromat 4.0). |
| Caminandes: Llama Drama, Gran Dillama, Llamigos | Blender's shorts, CC BY 3.0, kept as a three-episode series so the Shows library and episode playback have something to show. No metadata provider knows them as a series, so `fetch-media.sh` writes their titles and overviews as `.nfo` files and, as the `frame` mark on their line in `media.txt` asks, cuts a poster from a frame of the first episode, which CC BY allows. |
| Superman (1941), five of Max Fleischer's shorts | Made by Fleischer Studios for Paramount in 1941 and 1942; their copyrights were not renewed, as US law then required after 28 years, so they are in the public domain. TMDB doesn't know the shorts as a series either, so the poster is a frame of the title card. |
| The Beverly Hillbillies (1962), the first three episodes | The first two seasons' copyrights were not renewed, so those 55 episodes are in the public domain. Later seasons are not, so take episodes only from seasons 1 and 2. TMDB knows the series, so Jellyfin fetches its poster and logo. |
| Night of the Living Dead (1968) | Released without a copyright notice, which under the law of the time put it in the public domain on release. |
| The General (1926) | Published before 1930; its copyright has expired. |
| His Girl Friday (1940), Plan 9 from Outer Space (1957) | Their copyrights were not renewed, as US law then required after 28 years. |
| Kevin MacLeod's Classical Sampler and Jazz Sampler | Released by the composer under CC BY 3.0 (incompetech.com). |
| Josh Woodward's Ashes and The Shade From Our Trees | Released by the songwriter under CC BY 4.0 (joshwoodward.com). |
| Kimiko Ishizaka's Open Goldberg Variations | The pianist released the recording into the public domain with CC0 (opengoldbergvariations.org), and Bach's score is long out of copyright. |

The video files are H.264 in MP4, so the Apple TV plays them directly and the server never has to transcode; the 1940s and 1960s television is standard definition. The lot is about 4.6 GB.

What's missing from it: Live TV and photos, which the app supports but the demo server doesn't have. If App Review asks about them, the notes can say so; the local fixture server covers them in testing.

## Setting it up

A small virtual machine anywhere (1 CPU, 1 GB of memory, 10 GB of disk, Docker installed) is enough, since nothing is transcoded. The developer's own machine works too if it stays on and reachable for the whole review.

1. Clone the repository on the machine and go to `scripts/review-server`.
2. `cp .env.example .env`, then set `ADMIN_PASSWORD` (the administrator's; keep it) and leave `REVIEWER_PASSWORD` empty, so `setup.sh` makes one up.
3. `./fetch-media.sh`. Rerun it if it stops; it skips what it has. `--list` shows what it would get.
4. Give it an address. Either:
   - **HTTPS with Caddy.** Point a DNS name at the machine, open ports 80 and 443, set `REVIEW_SERVER_HOST` to that name and `REVIEW_SERVER_BIND` to `127.0.0.1` in `.env`, and run `docker compose --profile https up -d`. The address is `https://<that name>`.
   - **A Cloudflare Tunnel.** `docker compose up -d` with `REVIEW_SERVER_BIND=127.0.0.1`, then `brew install cloudflared`, `cloudflared tunnel login` (pick the zone in the browser and wait for it to say the certificate was written), and `./cloudflare-tunnel.sh anemone-review.<zone>`, which creates the tunnel, adds the DNS record, writes `~/.cloudflared/config.yml`, sets `JELLYFIN_URL` in `.env` and, on a Mac, runs the tunnel as a login item (`com.anemone.review-tunnel`, log in `~/Library/Logs`); on Linux it says to install cloudflared's system service. Homebrew's own `brew services start cloudflared` doesn't run a named tunnel. An HTTPS address without opening ports; a Tailscale Funnel does the same by hand.
   - **Plain HTTP** on port 8096 works too, since the app allows it ([`ats.md`](ats.md)), but give reviewers HTTPS when you can.
5. Set `JELLYFIN_URL` in `.env` to the address reviewers will type, then `./setup.sh`. It prints what the reviewer sees. If it says media is missing, the scan hasn't found it: check the libraries' paths in the dashboard (they're `/media/movies`, `/media/shows` and `/media/music` inside the container).
6. `./check.sh` from your Mac, with the same `.env`, to see what a reviewer would.

The administrator is hidden from the sign-in screen and the reviewer's account can browse and play, change its own settings, and nothing else: no deleting, downloading, Live TV, or controlling other sessions. A wrong password never locks it out. The reviewer can mark things watched and favourite, which is fine; `setup.sh` doesn't reset that.

## Where it runs now

On the maintainer's Mac, which stays on and already runs their own Jellyfin on port 8096: the kit is copied to `~/.anemone-agents/review-server` (next to the UI tests' fixture server), Jellyfin listens on `127.0.0.1:8296` only, and the Cloudflare Tunnel `anemone-review` makes it https://anemone-review.revanth.us (the passwords are in that folder's `.env`). The zone `revanth.us` has a catch-all redirect rule ("LLC Redirect", to devantstudios.org) whose expression excludes this hostname; a new rule that matches it would cut the server off before the tunnel. The tunnel is the login item `com.anemone.review-tunnel`, so it comes back with each login; the container restarts with Docker, but Docker Desktop isn't set to start at login, so after a reboot open Docker. Running `check.sh` there confirms both are back.

## Every submission

- Run `./check.sh` the day you submit, against the public address. It fails loudly if the server is down, the password changed, or the media isn't there.
- Paste the address and the sign-in into the notes and App Store Connect's Sign-in Information, and `media/LICENSES.md` under "About the content".
- Keep the server up until the review is over. Watch for Jellyfin's own updates only when you choose to move: the version is pinned in `docker-compose.yml`, and `check.sh` after moving.

To change the reviewer's password, set `REVIEWER_PASSWORD` in `.env` and rerun `setup.sh`. To start over, `docker compose down`, delete `config/` and `cache/`, and run from step 4; the media stays.

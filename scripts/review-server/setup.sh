#!/usr/bin/env bash
# Turns a running Jellyfin into the App Review demo server: finishes the startup wizard on a fresh
# server, names it, adds the Movies, Shows and Music libraries over the media fetch-media.sh
# downloaded, creates the reviewer's account with a non-admin policy (play and browse, nothing to
# delete, download or manage; no lockout for a mistyped password), hides the administrator from
# the sign-in screen, scans the libraries, and then signs in as the reviewer to prove the account
# works and sees the media. Safe to run again: it changes only what differs.
#
# usage: scripts/review-server/setup.sh [--url <jellyfin url>] [--media-root <path in the server>] [--no-scan]
#
# Settings come from the environment or .env next to this script (see .env.example):
# JELLYFIN_URL, ADMIN_USER and ADMIN_PASSWORD (required), REVIEWER_USER and REVIEWER_PASSWORD
# (made up and written to .env if empty), SERVER_NAME. --media-root is where the server itself
# sees the media: /media with docker-compose.yml.

set -euo pipefail

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

media_root="/media"
scan=true
while [[ $# -gt 0 ]]; do
    case "$1" in
    --url) JELLYFIN_URL="${2%/}"; shift 2 ;;
    --media-root) media_root="${2%/}"; shift 2 ;;
    --no-scan) scan=false; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
    esac
done

[[ -n "${ADMIN_PASSWORD:-}" ]] || fail "set ADMIN_PASSWORD (in .env or the environment)"
if [[ -z "${REVIEWER_PASSWORD:-}" ]]; then
    REVIEWER_PASSWORD="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'a-km-np-z2-9')"
    REVIEWER_PASSWORD="${REVIEWER_PASSWORD:0:16}"
    if [[ -f "$here/.env" ]] && grep -q '^REVIEWER_PASSWORD=' "$here/.env"; then
        sed -i.bak "s/^REVIEWER_PASSWORD=.*/REVIEWER_PASSWORD=$REVIEWER_PASSWORD/" "$here/.env" && rm -f "$here/.env.bak"
    else
        printf 'REVIEWER_PASSWORD=%s\n' "$REVIEWER_PASSWORD" >>"$here/.env"
    fi
    chmod 600 "$here/.env"
    echo "made up a password for $REVIEWER_USER and wrote it to $here/.env"
fi

echo "waiting for $JELLYFIN_URL"
for _ in $(seq 1 60); do
    if [[ "$(curl -s -m 5 "$JELLYFIN_URL/health" 2>/dev/null)" == "Healthy" ]]; then
        break
    fi
    sleep 2
done
[[ "$(curl -s -m 5 "$JELLYFIN_URL/health" 2>/dev/null)" == "Healthy" ]] || fail "$JELLYFIN_URL isn't answering; is the container up?"

public="$(api GET /System/Info/Public)"
echo "Jellyfin $(jq -r .Version <<<"$public") at $JELLYFIN_URL"

if [[ "$(jq -r .StartupWizardCompleted <<<"$public")" != "true" ]]; then
    echo "finishing the startup wizard; administrator $ADMIN_USER"
    api POST /Startup/Configuration "" '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' >/dev/null
    api GET /Startup/User >/dev/null
    api POST /Startup/User "" "$(jq -cn --arg n "$ADMIN_USER" --arg p "$ADMIN_PASSWORD" '{Name: $n, Password: $p}')" >/dev/null
    api POST /Startup/RemoteAccess "" '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}' >/dev/null
    api POST /Startup/Complete >/dev/null
fi

read -r admin_token admin_id < <(authenticate "$ADMIN_USER" "$ADMIN_PASSWORD") ||
    fail "couldn't sign in as $ADMIN_USER; on a server set up before, ADMIN_PASSWORD must be the password the wizard was given"

configuration="$(api GET /System/Configuration "$admin_token")"
if [[ "$(jq -r .ServerName <<<"$configuration")" != "$SERVER_NAME" ]]; then
    echo "naming the server \"$SERVER_NAME\""
    api POST /System/Configuration "$admin_token" "$(jq -c --arg n "$SERVER_NAME" '.ServerName = $n' <<<"$configuration")" >/dev/null
fi

# add_library <name> <collection type> <folder under the media root>
add_library() {
    local name="$1" type="$2" folder="$3" existing
    existing="$(api GET /Library/VirtualFolders "$admin_token")"
    if jq -e --arg n "$name" 'any(.[]; .Name == $n)' <<<"$existing" >/dev/null; then
        echo "library $name exists"
        return
    fi
    echo "adding the $name library over $media_root/$folder"
    api POST "/Library/VirtualFolders?name=$name&collectionType=$type&refreshLibrary=false" "$admin_token" \
        "$(jq -cn --arg p "$media_root/$folder" '{LibraryOptions: {PathInfos: [{Path: $p}], EnableRealtimeMonitor: false}}')" >/dev/null
}
add_library Movies movies movies
add_library Shows tvshows shows
add_library Music music music

users="$(api GET /Users "$admin_token")"
reviewer_id="$(jq -r --arg n "$REVIEWER_USER" 'first(.[] | select(.Name == $n) | .Id) // empty' <<<"$users")"
if [[ -z "$reviewer_id" ]]; then
    echo "creating the reviewer account $REVIEWER_USER"
    reviewer_id="$(api POST /Users/New "$admin_token" "$(jq -cn --arg n "$REVIEWER_USER" --arg p "$REVIEWER_PASSWORD" '{Name: $n, Password: $p}')" | jq -r .Id)"
else
    echo "setting $REVIEWER_USER's password"
    api POST "/Users/$reviewer_id/Password" "$admin_token" "$(jq -cn --arg p "$REVIEWER_PASSWORD" '{NewPw: $p, ResetPassword: false}')" >/dev/null
fi

# set_policy <user id> <jq filter over the user's policy>
set_policy() {
    local policy
    policy="$(api GET "/Users/$1" "$admin_token" | jq -c ".Policy | $2")"
    api POST "/Users/$1/Policy" "$admin_token" "$policy" >/dev/null
}
echo "limiting $REVIEWER_USER to browsing and playback"
set_policy "$reviewer_id" '.IsAdministrator = false
    | .IsHidden = false
    | .IsDisabled = false
    | .EnableAllFolders = true
    | .EnableMediaPlayback = true
    | .EnableAudioPlaybackTranscoding = true
    | .EnableVideoPlaybackTranscoding = true
    | .EnablePlaybackRemuxing = true
    | .EnableRemoteAccess = true
    | .EnableUserPreferenceAccess = true
    | .EnableContentDeletion = false
    | .EnableContentDeletionFromFolders = []
    | .EnableContentDownloading = false
    | .EnableSyncTranscoding = false
    | .EnableMediaConversion = false
    | .EnableRemoteControlOfOtherUsers = false
    | .EnableSharedDeviceControl = false
    | .EnableLiveTvAccess = false
    | .EnableLiveTvManagement = false
    | .EnableCollectionManagement = false
    | .EnableSubtitleManagement = false
    | .EnableLyricManagement = false
    | .EnablePublicSharing = false
    | .LoginAttemptsBeforeLockout = -1
    | .MaxActiveSessions = 0'
echo "hiding $ADMIN_USER from the sign-in screen"
set_policy "$admin_id" '.IsHidden = true'

if $scan; then
    task="$(api GET /ScheduledTasks "$admin_token" | jq -c 'first(.[] | select(.Key == "RefreshLibrary"))')"
    task_id="$(jq -r .Id <<<"$task")"
    if [[ "$(jq -r .State <<<"$task")" == "Idle" ]]; then
        echo "scanning the libraries"
        api POST "/ScheduledTasks/Running/$task_id" "$admin_token" >/dev/null
        sleep 2
    else
        echo "a library scan is already running; waiting for it"
    fi
    for _ in $(seq 1 450); do
        task="$(api GET "/ScheduledTasks/$task_id" "$admin_token")"
        [[ "$(jq -r .State <<<"$task")" == "Idle" ]] && break
        sleep 2
    done
    [[ "$(jq -r .State <<<"$task")" == "Idle" ]] || fail "the scan is still running after 15 minutes; check the dashboard"
fi

echo "signing in as $REVIEWER_USER to check"
read -r reviewer_token reviewer_user_id < <(authenticate "$REVIEWER_USER" "$REVIEWER_PASSWORD") ||
    fail "$REVIEWER_USER can't sign in with the password in .env"
movies="$(count_items "$reviewer_token" "$reviewer_user_id" Movie)"
episodes="$(count_items "$reviewer_token" "$reviewer_user_id" Episode)"
songs="$(count_items "$reviewer_token" "$reviewer_user_id" Audio)"
api POST /Sessions/Logout "$reviewer_token" >/dev/null
api POST /Sessions/Logout "$admin_token" >/dev/null

echo
echo "$REVIEWER_USER sees $movies movies, $episodes episodes and $songs songs (media.txt lists $(expected movie) movies, $(expected episode) episodes and $(expected album) albums)"
if (( movies < $(expected movie) || episodes < $(expected episode) || songs == 0 )); then
    echo "some media is missing: run fetch-media.sh, check the library paths in the dashboard, and run this again" >&2
    exit 1
fi
echo "for the App Review notes: server address $JELLYFIN_URL, user name $REVIEWER_USER, password in $here/.env"

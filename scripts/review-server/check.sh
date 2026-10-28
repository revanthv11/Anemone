#!/usr/bin/env bash
# The check to run the day a build goes to App Review, from anywhere, against the address the
# notes will give: the server answers, the reviewer's sign-in works, the reviewer sees the media
# media.txt lists, and a movie streams. Says PASS or FAIL for each and exits non-zero on any FAIL.
#
# usage: scripts/review-server/check.sh [--url <jellyfin url>]
#
# JELLYFIN_URL, REVIEWER_USER and REVIEWER_PASSWORD come from the environment or .env next to
# this script. Point JELLYFIN_URL at the public address, not localhost, for the real check.

set -euo pipefail

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

while [[ $# -gt 0 ]]; do
    case "$1" in
    --url) JELLYFIN_URL="${2%/}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
    esac
done
[[ -n "${REVIEWER_PASSWORD:-}" ]] || fail "set REVIEWER_PASSWORD (in .env or the environment)"

failures=0
pass() { echo "PASS  $*"; }
flunk() { echo "FAIL  $*"; failures=$((failures + 1)); }

public="$(curl -sS -m 15 "$JELLYFIN_URL/System/Info/Public" 2>/dev/null)" || public=""
if [[ -n "$public" ]] && jq -e .Version <<<"$public" >/dev/null 2>&1; then
    pass "$JELLYFIN_URL answers: \"$(jq -r .ServerName <<<"$public")\", Jellyfin $(jq -r .Version <<<"$public")"
else
    flunk "$JELLYFIN_URL doesn't answer as a Jellyfin server"
    echo "nothing else can be checked" >&2
    exit 1
fi
if [[ "$JELLYFIN_URL" == http://* ]]; then
    echo "note  the address is plain HTTP; the app allows it, but give App Review an https address if there is one"
fi

if reply="$(authenticate "$REVIEWER_USER" "$REVIEWER_PASSWORD" 2>&1)"; then
    read -r token user_id <<<"$reply"
    pass "$REVIEWER_USER signs in"
else
    flunk "$REVIEWER_USER can't sign in: ${reply#error: }"
    exit 1
fi

if [[ "$(api GET /Users/Me "$token" | jq -r .Policy.IsAdministrator)" == "false" ]]; then
    pass "$REVIEWER_USER isn't an administrator"
else
    flunk "$REVIEWER_USER is an administrator; run setup.sh again"
fi

movies="$(count_items "$token" "$user_id" Movie)"
episodes="$(count_items "$token" "$user_id" Episode)"
songs="$(count_items "$token" "$user_id" Audio)"
if (( movies >= $(expected movie) )); then
    pass "$movies movies (media.txt lists $(expected movie))"
else
    flunk "only $movies movies; media.txt lists $(expected movie)"
fi
if (( episodes >= $(expected episode) )); then
    pass "$episodes episodes (media.txt lists $(expected episode))"
else
    flunk "only $episodes episodes; media.txt lists $(expected episode)"
fi
if (( songs > 0 )); then
    pass "$songs songs"
else
    flunk "no songs"
fi

movie="$(api GET "/Items?userId=$user_id&Recursive=true&IncludeItemTypes=Movie&SortBy=SortName&Limit=1" "$token" | jq -c '.Items[0] // empty')"
if [[ -n "$movie" ]]; then
    status="$(curl -sS -m 30 -o /dev/null -w '%{http_code}' -r 0-1023 -H "$(auth_header "$token")" \
        "$JELLYFIN_URL/Videos/$(jq -r .Id <<<"$movie")/stream?static=true" 2>/dev/null || echo 000)"
    if [[ "$status" == 206 || "$status" == 200 ]]; then
        pass "\"$(jq -r .Name <<<"$movie")\" streams (HTTP $status)"
    else
        flunk "\"$(jq -r .Name <<<"$movie")\" doesn't stream (HTTP $status)"
    fi
fi

api POST /Sessions/Logout "$token" >/dev/null || true
echo
if (( failures > 0 )); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all good: server address $JELLYFIN_URL, user name $REVIEWER_USER"

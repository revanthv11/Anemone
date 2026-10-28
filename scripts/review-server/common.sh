# Shared by setup.sh and check.sh: the settings, and small wrappers round Jellyfin's API.
# Not a script of its own; the two source it.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
    echo "error: $*" >&2
    exit 1
}

# Reads KEY=value lines from .env next to the scripts, for the keys the environment doesn't set.
load_env() {
    local key value
    [[ -f "$here/.env" ]] || return 0
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        key="${key// /}"
        if [[ -z "${!key:-}" ]]; then
            export "$key=$value"
        fi
    done <"$here/.env"
}

load_env
: "${JELLYFIN_URL:=http://localhost:8096}"
: "${ADMIN_USER:=admin}"
: "${REVIEWER_USER:=reviewer}"
: "${SERVER_NAME:=Anemone review}"
JELLYFIN_URL="${JELLYFIN_URL%/}"

for tool in curl jq; do
    command -v "$tool" >/dev/null || fail "$tool is needed"
done

# Jellyfin wants this header on every request, token or not, from the startup wizard on.
auth_header() {
    local token="${1:-}"
    printf 'Authorization: MediaBrowser Client="Anemone review server scripts", Device="%s", DeviceId="anemone-review-server-%s", Version="1"%s' \
        "$(hostname -s 2>/dev/null || hostname)" "$(hostname -s 2>/dev/null || hostname)" "${token:+, Token=\"$token\"}"
}

# api <method> <path> [<token>] [<json body>]: the response body, failing loudly on an error status.
api() {
    local method="$1" path="$2" token="${3:-}" body="${4:-}" response status
    response="$(curl -sS -X "$method" -H "$(auth_header "$token")" -H 'Content-Type: application/json' \
        ${body:+--data "$body"} -w '\n%{http_code}' "$JELLYFIN_URL$path")" || fail "couldn't reach $JELLYFIN_URL$path"
    status="${response##*$'\n'}"
    response="${response%$'\n'*}"
    if [[ "$status" != 2* ]]; then
        fail "$method $path answered $status${response:+: $response}"
    fi
    printf '%s' "$response"
}

# authenticate <user> <password>: prints the access token and the user id, space-separated.
authenticate() {
    local reply
    reply="$(api POST /Users/AuthenticateByName "" "$(jq -cn --arg u "$1" --arg p "$2" '{Username: $u, Pw: $p}')")" ||
        return 1
    jq -r '"\(.AccessToken) \(.User.Id)"' <<<"$reply"
}

# count_items <token> <user id> <item type>: how many items of that type the user can see.
count_items() {
    api GET "/Items?userId=$2&Recursive=true&IncludeItemTypes=$3&Limit=0" "$1" | jq -r '.TotalRecordCount'
}

# How many titles of a kind media.txt lists.
expected() {
    grep -c "^$1|" "$here/media.txt" || true
}

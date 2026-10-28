#!/usr/bin/env bash
# Puts a Cloudflare Tunnel in front of the demo server, so it gets an https address on one of the
# developer's Cloudflare zones without opening a port on the machine: creates the tunnel (once),
# points a DNS name at it, writes cloudflared's config, and sets JELLYFIN_URL in .env to the new
# address so check.sh tests what reviewers will type. On a Mac it then runs the tunnel as a login
# item (a LaunchAgent), which starts whenever you're logged in; elsewhere it says how.
#
# usage: scripts/review-server/cloudflare-tunnel.sh <hostname> [--name <tunnel name>]
#   <hostname>   the DNS name reviewers will type, e.g. anemone-review.example.com, on the zone
#                picked at login
#   --name       the tunnel's name in Cloudflare; default anemone-review
#
# Needs cloudflared (brew install cloudflared), logged in once with `cloudflared tunnel login`,
# which opens the browser, has you pick a zone, and writes ~/.cloudflared/cert.pem. Reads
# REVIEW_SERVER_PORT from .env (8096 by default) for where Jellyfin listens on this machine.

set -euo pipefail

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

fail() {
    echo "error: $*" >&2
    exit 1
}

here="$(cd "$(dirname "$0")" && pwd)"
hostname=""
name="anemone-review"
while [[ $# -gt 0 ]]; do
    case "$1" in
    --name) name="${2:?--name needs a value}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) usage >&2; exit 64 ;;
    *) hostname="$1"; shift ;;
    esac
done
[[ -n "$hostname" ]] || { usage >&2; exit 64; }
[[ "$hostname" == *.* && "$hostname" != *://* ]] || fail "$hostname isn't a DNS name"

command -v cloudflared >/dev/null || fail "cloudflared is needed: brew install cloudflared"
cloudflared_dir="$HOME/.cloudflared"
[[ -s "$cloudflared_dir/cert.pem" ]] || fail "not logged in: run \`cloudflared tunnel login\`, pick the zone $hostname is on in the browser, and wait for it to say the certificate was written"

port=8096
if [[ -f "$here/.env" ]]; then
    port="$(sed -n 's/^REVIEW_SERVER_PORT=//p' "$here/.env" | tail -n 1)"
    port="${port:-8096}"
fi

tunnel_id="$(cloudflared tunnel list --name "$name" --output json 2>/dev/null | jq -r '.[0].id // empty')"
if [[ -z "$tunnel_id" ]]; then
    echo "creating the tunnel $name"
    cloudflared tunnel create "$name" >/dev/null
    tunnel_id="$(cloudflared tunnel list --name "$name" --output json | jq -r '.[0].id // empty')"
    [[ -n "$tunnel_id" ]] || fail "the tunnel was created but cloudflared tunnel list doesn't show it"
else
    echo "the tunnel $name exists ($tunnel_id)"
fi
credentials="$cloudflared_dir/$tunnel_id.json"
[[ -s "$credentials" ]] || fail "$credentials is missing; the tunnel was created on another machine. Delete it with \`cloudflared tunnel delete $name\` and run again, or copy the file here"

echo "pointing $hostname at the tunnel"
cloudflared tunnel route dns --overwrite-dns "$name" "$hostname"

config="$cloudflared_dir/config.yml"
if [[ -f "$config" ]] && ! grep -q "^tunnel: $tunnel_id\$" "$config"; then
    fail "$config exists for another tunnel; move it aside and run again"
fi
cat >"$config" <<YAML
# Written by scripts/review-server/cloudflare-tunnel.sh: the App Review demo server.
tunnel: $tunnel_id
credentials-file: $credentials
ingress:
  - hostname: $hostname
    service: http://localhost:$port
  - service: http_status:404
YAML
echo "wrote $config"

if [[ -f "$here/.env" ]]; then
    if grep -q '^JELLYFIN_URL=' "$here/.env"; then
        sed -i.bak "s|^JELLYFIN_URL=.*|JELLYFIN_URL=https://$hostname|" "$here/.env" && rm -f "$here/.env.bak"
    else
        printf 'JELLYFIN_URL=https://%s\n' "$hostname" >>"$here/.env"
    fi
    echo "set JELLYFIN_URL=https://$hostname in .env"
fi

echo
if [[ "$(uname)" == Darwin ]]; then
    agent_label="com.anemone.review-tunnel"
    agent="$HOME/Library/LaunchAgents/$agent_label.plist"
    log="$HOME/Library/Logs/anemone-review-tunnel.log"
    mkdir -p "$(dirname "$agent")" "$(dirname "$log")"
    cat >"$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$agent_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(command -v cloudflared)</string>
        <string>tunnel</string>
        <string>--config</string>
        <string>$config</string>
        <string>--no-autoupdate</string>
        <string>run</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$log</string>
    <key>StandardErrorPath</key>
    <string>$log</string>
</dict>
</plist>
PLIST
    launchctl bootout "gui/$(id -u)/$agent_label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$agent"
    echo "running the tunnel as the login item $agent_label; its log is $log"
    echo "to stop it: launchctl bootout gui/\$(id -u)/$agent_label; to start it again, run this script again"
else
    echo "now run the tunnel as a service, which reads $config:"
    echo "  sudo cloudflared service install"
fi
echo "then check it from anywhere: $here/check.sh --url https://$hostname"

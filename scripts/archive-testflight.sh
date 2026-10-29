#!/usr/bin/env bash
# Builds an App Store Connect .ipa of Anemone for TestFlight or the App Store while the team has
# no registered Apple TV.
#
# Xcode's automatic signing archives with a *development* profile and re-signs for distribution on
# export. A development profile needs at least one registered device, so with none Product › Archive
# fails ("Your team has no devices from which to generate a provisioning profile"), and neither an
# Apple Distribution identity nor ad-hoc signing is accepted by the tvOS SDK at archive time. This
# script goes around that: it archives without signing, ad-hoc signs the archive by hand so the
# entitlements (App Group, Keychain group) are there for the export step to carry over, then lets
# `xcodebuild -exportArchive` sign with the team's Apple Distribution certificate and App Store
# profiles. Once an Apple TV is registered, Product › Archive works again and this script is only a
# convenience.
#
# usage: scripts/archive-testflight.sh [options]
#   --team <id>        the team ID; default: DEVELOPMENT_TEAM from the project
#   --archive <path>   where to write the .xcarchive; default: Xcode's Archives folder for today,
#                      so the Organizer lists it
#   --out <dir>        where to write the .ipa and logs; default: next to the archive
#   --open             hand the .ipa to Transporter when done
#   --dry-run          print what would happen, building nothing
#
# The commit should be clean and on origin, so scripts/tag-build.sh can tag it afterwards.
# Nothing is uploaded: Verify and Deliver the .ipa in Transporter, or upload it any other way.

set -euo pipefail

usage() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
}

fail() {
    echo "error: $*" >&2
    exit 1
}

repo="$(cd "$(dirname "$0")/.." && pwd)"
project="$repo/Anemone.xcodeproj"
scheme="Anemone"
app_entitlements="$repo/App/Anemone.entitlements"
ext_entitlements="$repo/TopShelf/AnemoneTopShelf.entitlements"
ext_name="AnemoneTopShelf"

team=""
archive=""
out=""
open_after=false
dry_run=false

while [ $# -gt 0 ]; do
    case "$1" in
        --team) team="${2:-}"; shift 2 ;;
        --archive) archive="${2:-}"; shift 2 ;;
        --out) out="${2:-}"; shift 2 ;;
        --open) open_after=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; fail "unknown option: $1" ;;
    esac
done

command -v xcodebuild >/dev/null || fail "xcodebuild not found; install Xcode"
[ -f "$app_entitlements" ] || fail "missing $app_entitlements"
[ -f "$ext_entitlements" ] || fail "missing $ext_entitlements"

if [ -z "$team" ]; then
    team="$(grep -m1 -oE 'DEVELOPMENT_TEAM = [A-Z0-9]+' "$project/project.pbxproj" | awk '{ print $3 }' || true)"
    [ -n "$team" ] || fail "no DEVELOPMENT_TEAM in the project; pass --team"
fi
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail "team ID should be ten letters and digits, got '$team'"

today="$(date +%Y-%m-%d)"
if [ -z "$archive" ]; then
    archive="$HOME/Library/Developer/Xcode/Archives/$today/Anemone $today $(date +%H.%M).xcarchive"
fi
[ -e "$archive" ] && fail "archive already exists: $archive"
[ -z "$out" ] && out="${archive%.xcarchive}-export"
[ -e "$out" ] && fail "output directory already exists: $out"

echo "team:    $team"
echo "archive: $archive"
echo "export:  $out"
if $dry_run; then
    echo "dry run: nothing built"
    exit 0
fi

mkdir -p "$out"
archive_log="$out/archive.log"
export_log="$out/export.log"

# 1. Archive without signing. AppIdentifierPrefix normally comes from the provisioning profile; the
#    Info.plists use it in AnemoneKeychainAccessGroup, so supply it or the value expands to nothing
#    and SharedStorage finds no access group at runtime.
echo "archiving (log: $archive_log)..."
if ! xcodebuild archive \
        -project "$project" -scheme "$scheme" -configuration Release \
        -destination 'generic/platform=tvOS' -archivePath "$archive" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "AppIdentifierPrefix=$team." \
        >"$archive_log" 2>&1; then
    grep -E 'error:' "$archive_log" >&2 || tail -20 "$archive_log" >&2
    fail "archive failed; see $archive_log"
fi

app="$archive/Products/Applications/$scheme.app"
ext="$app/PlugIns/$ext_name.appex"
[ -d "$app" ] || fail "no app in the archive at $app"
[ -d "$ext" ] || fail "no Top Shelf extension in the archive at $ext"

# plutil reads a dot in a key as a key path, so escape them in entitlement keys.
plkey() {
    printf '%s' "$1" | sed 's/\./\\./g'
}

# 2. Entitlements for the ad-hoc signatures: the project's files with the team prefix filled in,
#    plus the identifiers a signed app always carries.
make_entitlements() {
    local source="$1" bundle="$2" target="$3"
    sed "s/\$(AppIdentifierPrefix)/$team./g" "$source" >"$target"
    plutil -insert application-identifier -string "$team.$bundle" "$target"
    plutil -insert "$(plkey com.apple.developer.team-identifier)" -string "$team" "$target"
    plutil -lint "$target" >/dev/null
}
app_bundle="$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")"
ext_bundle="$(plutil -extract CFBundleIdentifier raw "$ext/Info.plist")"
make_entitlements "$app_entitlements" "$app_bundle" "$out/app.entitlements"
make_entitlements "$ext_entitlements" "$ext_bundle" "$out/extension.entitlements"

# 3. Ad-hoc sign the archive: nested code first, then the extension, then the app. The export step
#    replaces every signature but keeps the entitlements it finds.
echo "ad-hoc signing the archive..."
find "$app" \( -name '*.framework' -o -name '*.bundle' -o -name '*.dylib' \) -not -path "$ext/*" -print0 \
    | while IFS= read -r -d '' nested; do codesign -s - -f "$nested" 2>/dev/null; done
codesign -s - -f --entitlements "$out/extension.entitlements" "$ext"
codesign -s - -f --entitlements "$out/app.entitlements" "$app"

# 4. Export for App Store Connect. Xcode signs with the team's Apple Distribution certificate and
#    App Store profiles, creating them when it has to (-allowProvisioningUpdates).
cat >"$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$team</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST
echo "exporting (log: $export_log)..."
if ! xcodebuild -exportArchive -archivePath "$archive" \
        -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out/export" \
        -allowProvisioningUpdates >"$export_log" 2>&1; then
    grep -iE 'error' "$export_log" >&2 || tail -20 "$export_log" >&2
    fail "export failed; see $export_log"
fi
exported="$out/export/$scheme.ipa"
[ -f "$exported" ] || fail "export produced no $exported"

# 5. Check the .ipa before anyone uploads it: distribution signature, and the entitlements that
#    sign-in persistence and Top Shelf depend on.
echo "verifying..."
check_dir="$out/verify"
mkdir -p "$check_dir"
unzip -q "$exported" -d "$check_dir"
ipa_app="$check_dir/Payload/$scheme.app"
ipa_ext="$ipa_app/PlugIns/$ext_name.appex"
codesign -vv --deep --strict "$ipa_app" 2>"$out/verify-codesign.txt" \
    || fail "the exported app fails codesign verification; see $out/verify-codesign.txt"

expect_entitlements() {
    local bundle="$1" expected="$2" key actual wanted signature
    # Capture first: grep -q closing the pipe early would fail the pipeline under pipefail.
    signature="$(codesign -dv --verbose=2 "$bundle" 2>&1)"
    grep -q '^Authority=Apple Distribution' <<<"$signature" \
        || fail "$(basename "$bundle") is not signed with an Apple Distribution certificate"
    codesign -d --entitlements :- "$bundle" 2>/dev/null >"$out/verify-$(basename "$bundle").entitlements"
    for key in com.apple.security.application-groups keychain-access-groups application-identifier; do
        wanted="$(plutil -extract "$(plkey "$key")" json -o - "$expected")"
        actual="$(plutil -extract "$(plkey "$key")" json -o - "$out/verify-$(basename "$bundle").entitlements" 2>/dev/null || echo missing)"
        [ "$actual" = "$wanted" ] || fail "$(basename "$bundle"): $key is $actual, expected $wanted"
    done
}
expect_entitlements "$ipa_app" "$out/app.entitlements"
expect_entitlements "$ipa_ext" "$out/extension.entitlements"
[ "$(plutil -extract AnemoneKeychainAccessGroup raw "$ipa_app/Info.plist")" = "$team.com.revanthv11.anemone.shared" ] \
    || fail "AnemoneKeychainAccessGroup in the app's Info.plist did not get the team prefix"
grep -q arm64 <<<"$(plutil -extract UIRequiredDeviceCapabilities json -o - "$ipa_ext/Info.plist" 2>/dev/null)" \
    || fail "the Top Shelf extension's Info.plist lacks UIRequiredDeviceCapabilities arm64, which App Store Connect rejects"

version="$(plutil -extract CFBundleShortVersionString raw "$ipa_app/Info.plist")"
build="$(plutil -extract CFBundleVersion raw "$ipa_app/Info.plist")"
ipa="$out/Anemone-$version-$build.ipa"
mv "$exported" "$ipa"
rm -rf "$check_dir"

echo
echo "Anemone $version ($build)"
echo "archive: $archive"
echo "ipa:     $ipa"
echo "next:    Verify and Deliver it in Transporter, then scripts/tag-build.sh --archive \"$archive\" --push"
if $open_after; then
    open -a Transporter "$ipa"
fi

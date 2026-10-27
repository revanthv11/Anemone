#!/usr/bin/env bash
# Tags the commit a TestFlight or App Store build was archived from, so every build that ships
# has public source to match ("GPL and the App Store" in docs/PLAN.md).
#
# The tag is build/<version>-<build>, e.g. build/1.0.0-12, annotated "Anemone 1.0.0 (12)".
# Settings › About names the same tag (AppVersion.sourceTag); keep the two in step.
#
# usage: scripts/tag-build.sh [options]
#   --archive <path>   read the version and build from an .xcarchive
#   --version <v>      the version (CFBundleShortVersionString); default: the commit's MARKETING_VERSION
#   --build <n>        the build (CFBundleVersion); default: the commit's CURRENT_PROJECT_VERSION
#   --commit <rev>     the commit to tag; default: HEAD, which must have no uncommitted changes
#   --push             push the tag to origin (without it, the tag stays local)
#   --dry-run          check everything and say what would happen, changing nothing
#
# The commit must already be on origin: a tag for source nobody can see doesn't help.

set -euo pipefail

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

fail() {
    echo "error: $*" >&2
    exit 1
}

archive=""
version=""
build=""
commit=""
push=false
dry_run=false

while [[ $# -gt 0 ]]; do
    case "$1" in
    --archive) archive="${2:?--archive needs a path}"; shift 2 ;;
    --version) version="${2:?--version needs a value}"; shift 2 ;;
    --build) build="${2:?--build needs a value}"; shift 2 ;;
    --commit) commit="${2:?--commit needs a revision}"; shift 2 ;;
    --push) push=true; shift ;;
    --dry-run | -n) dry_run=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
    esac
done

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
git rev-parse --git-dir >/dev/null 2>&1 || fail "$repo isn't a git checkout"

if [[ -z "$commit" ]]; then
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
        fail "there are uncommitted changes, so HEAD may not be what was archived; commit them, or pass --commit"
    fi
    commit="HEAD"
fi
sha="$(git rev-parse --verify --quiet "$commit^{commit}")" || fail "$commit isn't a commit"

if [[ -n "$archive" ]]; then
    info="$archive/Info.plist"
    [[ -f "$info" ]] || fail "$info doesn't exist; is $archive an .xcarchive?"
    plist() {
        /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:$1" "$info" 2>/dev/null || true
    }
    [[ -n "$version" ]] || version="$(plist CFBundleShortVersionString)"
    [[ -n "$build" ]] || build="$(plist CFBundleVersion)"
fi

# The build settings as committed, so the tag names what that commit builds. Every target
# shares them today; if they ever differ, pass --version and --build.
setting() {
    local values
    values="$(git show "$sha:Anemone.xcodeproj/project.pbxproj" |
        sed -n "s/^[[:space:]]*$1 = \"\{0,1\}\([^\";]*\)\"\{0,1\};/\1/p" | sort -u)"
    if [[ "$(grep -c . <<<"$values")" -ne 1 ]]; then
        fail "the targets don't agree on $1 (${values//$'\n'/, }); pass it with --version or --build"
    fi
    echo "$values"
}
[[ -n "$version" ]] || version="$(setting MARKETING_VERSION)"
[[ -n "$build" ]] || build="$(setting CURRENT_PROJECT_VERSION)"

[[ "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "\"$version\" isn't a version like 1.2.3"
[[ "$build" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "\"$build\" isn't a build number like 12"

tag="build/$version-$build"
message="Anemone $version ($build)"

# The source must be public before the tag means anything.
git fetch --quiet origin || fail "couldn't fetch origin"
if [[ -z "$(git branch --remotes --contains "$sha")" ]]; then
    fail "${sha:0:7} isn't on origin yet; push it first"
fi

existing="$(git rev-parse --verify --quiet "refs/tags/$tag^{commit}" || true)"
remote="$(git ls-remote --tags origin "refs/tags/$tag^{}" | cut -f1)"
[[ -n "$remote" ]] || remote="$(git ls-remote --tags origin "refs/tags/$tag" | cut -f1)"
for other in "$existing" "$remote"; do
    if [[ -n "$other" && "$other" != "$sha" ]]; then
        fail "$tag already names ${other:0:7}, not ${sha:0:7}; each build number is tagged once"
    fi
done

echo "$tag -> ${sha:0:7} $(git log -1 --format=%s "$sha")"
if $dry_run; then
    echo "dry run: nothing tagged or pushed"
    exit 0
fi

if [[ -z "$existing" ]]; then
    git tag --annotate "$tag" "$sha" --message "$message"
    echo "tagged $tag"
else
    echo "$tag already exists here"
fi

if $push; then
    if [[ -n "$remote" ]]; then
        echo "$tag is already on origin"
    else
        git push origin "refs/tags/$tag"
    fi
else
    echo "not pushed; run: git push origin refs/tags/$tag"
fi

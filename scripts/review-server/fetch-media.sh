#!/usr/bin/env bash
# Downloads the App Review demo server's media from the Internet Archive, as media.txt lists it,
# into media/ next to this script, laid out the way Jellyfin's naming rules expect (one folder per
# movie, Season folders for the show, artist/album folders for the music), and writes
# media/LICENSES.md, the list of titles and licenses for the App Review notes. For the show, whose
# shorts no metadata provider knows as a series, it writes .nfo files with the titles and overviews
# and, with ffmpeg installed, a poster cut from a frame of its first episode.
#
# A file whose size already matches the archive's is left alone and a partial one resumes, so the
# script can be rerun after a dropped connection or a new line in media.txt. About 2.6 GB in all.
#
# usage: scripts/review-server/fetch-media.sh [options]
#   --only <regex>   only the titles matching the regex, case-insensitively, e.g. --only 'bunny|caminandes'
#   --list           say what would be fetched, with sizes, and stop
#   --media <dir>    download into <dir> instead of media/ next to this script
#
# Needs curl and jq.

set -euo pipefail

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

fail() {
    echo "error: $*" >&2
    exit 1
}

here="$(cd "$(dirname "$0")" && pwd)"
manifest="$here/media.txt"
media_dir="$here/media"
only=""
list=false

while [[ $# -gt 0 ]]; do
    case "$1" in
    --only) only="${2:?--only needs a regex}"; shift 2 ;;
    --list) list=true; shift ;;
    --media) media_dir="${2:?--media needs a directory}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
    esac
done

for tool in curl jq; do
    command -v "$tool" >/dev/null || fail "$tool is needed"
done
[[ -f "$manifest" ]] || fail "$manifest is missing"

archive="https://archive.org"
metadata_cache="$(mktemp -d)"
trap 'rm -rf "$metadata_cache"' EXIT

# The archive's description of an item, fetched once.
item_metadata() {
    local id="$1" cache="$metadata_cache/$1.json"
    if [[ ! -s "$cache" ]]; then
        curl -fsSL --retry 3 "$archive/metadata/$id" -o "$cache" || fail "couldn't read the archive's metadata for $id"
        jq -e '.files | length > 0' "$cache" >/dev/null 2>&1 || fail "the archive has no item called $id"
    fi
    cat "$cache"
}

# The size the archive reports for one of an item's files, or nothing if there's no such file.
remote_size() {
    item_metadata "$1" | jq -r --arg name "$2" 'first(.files[] | select(.name == $name) | .size) // empty'
}

# The original MP3s in an item, one name per line.
album_files() {
    item_metadata "$1" | jq -r '.files[] | select(.source == "original" and (.name | test("\\.mp3$"))) | .name'
}

local_size() {
    if [[ ! -f "$1" ]]; then
        echo 0
    else
        stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
    fi
}

megabytes() {
    echo "$(( ($1 + 524288) / 1048576 )) MB"
}

# Downloads one of an item's files to a path, skipping it when it's already complete.
fetch() {
    local id="$1" name="$2" dest="$3" want have url
    want="$(remote_size "$id" "$name")"
    [[ -n "$want" ]] || fail "$id has no file called \"$name\"; compare media.txt with $archive/details/$id"
    have="$(local_size "$dest")"
    if [[ "$have" == "$want" ]]; then
        echo "  have   ${dest#"$media_dir"/}"
        return
    fi
    if $list; then
        echo "  fetch  ${dest#"$media_dir"/} ($(megabytes "$want"))"
        return
    fi
    if (( have > want )); then
        rm -f "$dest"
    fi
    mkdir -p "$(dirname "$dest")"
    url="$archive/download/$id/$(jq -rn --arg s "$name" '$s | split("/") | map(@uri) | join("/")')"
    echo "  fetch  ${dest#"$media_dir"/} ($(megabytes "$want"))"
    curl -fL --retry 5 --retry-delay 10 --retry-all-errors -C - --progress-bar -o "$dest" "$url"
    have="$(local_size "$dest")"
    [[ "$have" == "$want" ]] || fail "$dest is $have bytes but the archive says $want; delete it and run again"
}

xml_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\&apos;/g" -e 's/"/\&quot;/g' <<<"$1"
}

write_show_nfo() {
    local dir="$1" title="$2" year="$3" overview="$4" credit="$5" license="$6"
    $list && return
    mkdir -p "$dir"
    cat >"$dir/tvshow.nfo" <<NFO
<?xml version="1.0" encoding="utf-8"?>
<tvshow>
  <title>$(xml_escape "$title")</title>
  <year>$year</year>
  <premiered>$year-01-01</premiered>
  <plot>$(xml_escape "$overview") $(xml_escape "$credit"), $(xml_escape "$license").</plot>
  <genre>Animation</genre>
  <status>Ended</status>
</tvshow>
NFO
}

write_episode_nfo() {
    local path="$1" title="$2" year="$3" overview="$4" credit="$5" license="$6" season episode
    $list && return
    [[ "$(basename "$path")" =~ S([0-9]+)E([0-9]+) ]] || fail "$path doesn't say which episode it is (S01E01)"
    season=$((10#${BASH_REMATCH[1]}))
    episode=$((10#${BASH_REMATCH[2]}))
    cat >"${path%.*}.nfo" <<NFO
<?xml version="1.0" encoding="utf-8"?>
<episodedetails>
  <title>$(xml_escape "$title")</title>
  <season>$season</season>
  <episode>$episode</episode>
  <aired>$year-01-01</aired>
  <plot>$(xml_escape "$overview") $(xml_escape "$credit"), $(xml_escape "$license").</plot>
</episodedetails>
NFO
}

shopt -s nocasematch
licenses="$media_dir/LICENSES.md"
show_dirs=()
movies_md=""
shows_md=""
music_md=""
fetched=0

while IFS='|' read -r kind id name dest title year license license_url credit overview; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    if [[ -n "$only" && ! "$title" =~ $only ]]; then
        continue
    fi
    path="$media_dir/$dest"
    echo "$title ($year)"
    case "$kind" in
    movie)
        fetch "$id" "$name" "$path"
        movies_md+="- **$title** ($year). $credit. $license, $license_url. Source: $archive/details/$id"$'\n'
        ;;
    show)
        write_show_nfo "$path" "$title" "$year" "$overview" "$credit" "$license"
        show_dirs+=("$path")
        shows_md+="- **$title** ($year). $credit. $license, $license_url."$'\n'
        ;;
    episode)
        fetch "$id" "$name" "$path"
        write_episode_nfo "$path" "$title" "$year" "$overview" "$credit" "$license"
        shows_md+="  - $(basename "${dest%.*}") ($year). $credit. $license. Source: $archive/details/$id"$'\n'
        ;;
    album)
        [[ "$name" == "*.mp3" ]] || fail "an album's file field must be *.mp3 (got \"$name\")"
        tracks=0
        while IFS= read -r track; do
            fetch "$id" "$track" "$path/$track"
            tracks=$((tracks + 1))
        done < <(album_files "$id")
        (( tracks > 0 )) || fail "$id has no MP3s"
        music_md+="- **$title** ($year), $tracks tracks. $credit. $license, $license_url. Source: $archive/details/$id"$'\n'
        ;;
    *)
        fail "media.txt has a line of kind \"$kind\"; it must be movie, show, episode or album"
        ;;
    esac
    fetched=$((fetched + 1))
done <"$manifest"
shopt -u nocasematch

(( fetched > 0 )) || fail "nothing in media.txt matches --only $only"
$list && exit 0

# A poster for each show from a frame of its first episode, since no provider has one.
for dir in "${show_dirs[@]+"${show_dirs[@]}"}"; do
    [[ -f "$dir/poster.jpg" ]] && continue
    first="$(find "$dir" -name '*.mp4' | sort | head -n 1)"
    [[ -n "$first" ]] || continue
    if ! command -v ffmpeg >/dev/null; then
        echo "no ffmpeg, so no poster for ${dir#"$media_dir"/}; Jellyfin shows a placeholder"
        continue
    fi
    echo "cutting a poster for ${dir#"$media_dir"/} from ${first#"$dir"/}"
    ffmpeg -loglevel error -y -ss 20 -i "$first" -frames:v 1 -vf 'crop=ih*2/3:ih,scale=1000:1500' "$dir/poster.jpg"
done

if [[ -n "$only" ]]; then
    echo
    echo "fetched with --only, so ${licenses#"$media_dir"/} is left as it was; run without --only to rewrite it"
    exit 0
fi
mkdir -p "$media_dir"
{
    echo "# What's on the review server"
    echo
    echo "Downloaded from the Internet Archive by \`scripts/review-server/fetch-media.sh\` on $(date -u +%Y-%m-%d), as \`media.txt\` lists it. Every title is in the public domain or under a Creative Commons Attribution license, so it's legally free to stream to App Review; \`docs/release/review-server.md\` has the reasoning. Paste the lists below into the App Review notes under \"About the content\"."
    if [[ -n "$movies_md" ]]; then
        echo; echo "## Movies"; echo; printf '%s' "$movies_md"
    fi
    if [[ -n "$shows_md" ]]; then
        echo; echo "## Shows"; echo; printf '%s' "$shows_md"
    fi
    if [[ -n "$music_md" ]]; then
        echo; echo "## Music"; echo; printf '%s' "$music_md"
    fi
} >"$licenses"
echo
echo "wrote ${licenses#"$media_dir"/} under $media_dir"

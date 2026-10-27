#!/usr/bin/env bash
# Copies each Swift package's license from Xcode's package checkouts into
# App/Settings/About/Licenses/LICENSE-<package>.txt, where Settings › About shows it next to the
# package's row from NOTICE.md. Apache-2.0 packages that ship a NOTICE file get it appended, as
# section 4(d) of that license asks.
#
# Run it after adding or updating a package dependency (and add the package to NOTICE.md's
# "Third-party packages" table). It warns about packages NOTICE.md doesn't credit, and about
# credited packages with no license file.
#
# LICENSE-Anemone.txt is a link to the repo's LICENSE. LICENSE-Wholphin.txt and
# LICENSE-Swiftfin.txt are copied by hand from those projects, since they aren't packages.
#
# usage: scripts/update-licenses.sh [<SourcePackages dir>]
#   The directory holds Xcode's package checkouts, e.g. the one passed to xcodebuild's
#   -clonedSourcePackagesDirPath. Without it, the newest Anemone DerivedData is used.

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
destination="$repo/App/Settings/About/Licenses"
notice="$repo/NOTICE.md"

if [[ $# -gt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 64
fi

if [[ $# -eq 1 ]]; then
    packages="$1"
else
    # The most recently used DerivedData folder for this project.
    newest="$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/Anemone-*/SourcePackages 2>/dev/null | head -1 || true)"
    if [[ -z "$newest" ]]; then
        echo "error: no SourcePackages found; build the app once or pass the directory" >&2
        exit 1
    fi
    packages="$newest"
fi

checkouts="$packages/checkouts"
if [[ ! -d "$checkouts" ]]; then
    echo "error: $checkouts doesn't exist" >&2
    exit 1
fi

# Package names NOTICE.md credits: the link text in the first column of its tables.
credited="$(grep -E '^\|' "$notice" | cut -d'|' -f2 | grep -oE '\[[^]]+\]' | tr -d '[]`' | sort -u)"

status=0
for checkout in "$checkouts"/*/; do
    name="$(basename "$checkout")"
    license=""
    for candidate in LICENSE LICENSE.txt LICENSE.md LICENCE COPYING; do
        if [[ -f "$checkout$candidate" ]]; then
            license="$checkout$candidate"
            break
        fi
    done
    if [[ -z "$license" ]]; then
        echo "warning: $name has no license file; add its text to $destination by hand" >&2
        status=1
        continue
    fi

    # Package checkouts are read-only; write a fresh file rather than copy the mode along.
    output="$destination/LICENSE-$name.txt"
    rm -f "$output"
    cat "$license" >"$output"
    for candidate in NOTICE NOTICE.txt NOTICE.md; do
        if [[ -f "$checkout$candidate" ]]; then
            printf '\n\n---\n\n' >>"$output"
            cat "$checkout$candidate" >>"$output"
            break
        fi
    done
    echo "copied $name"

    if ! grep -qxF "$name" <<<"$credited"; then
        echo "warning: NOTICE.md doesn't credit $name; add it to the \"Third-party packages\" table" >&2
        status=1
    fi
done

while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ ! -e "$destination/LICENSE-$name.txt" ]]; then
        echo "warning: no license text for $name, which NOTICE.md credits" >&2
        status=1
    fi
done <<<"$credited"

exit "$status"

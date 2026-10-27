#!/usr/bin/env python3
"""Fills Anemone's String Catalogs with Wholphin's translations.

Wholphin (https://github.com/damontecres/Wholphin, GPL-2.0-or-later) is translated by its
contributors on Weblate. For each string an Anemone catalog uses, this script looks for a Wholphin
string with the same English text, exactly, once Android's quoting and escapes are resolved and
its format specifiers are written the way Swift writes them (`%1$s` as `%1$@`, `%d` as `%lld`).
It copies Wholphin's translations of that string, including its plural forms, and nothing else:
it never translates anything itself, and strings Wholphin doesn't have stay English.

Run it with Python 3 (standard library only), from anywhere:

    python3 -I scripts/import-wholphin-strings.py ~/src/Wholphin

That fills every catalog in the repository (App/Localizable.xcstrings and each package target's)
and prints how much of each language it covers and which strings found no match. Name catalogs
after the checkout to fill only those. `--dry-run` reports without writing; `--replace` also
replaces translations the catalogs already have. Strings that differ from Wholphin's only in
capitals ("Continue Watching", Wholphin's "Continue watching") are listed but not matched;
`--ignore-case` matches them too.

Build the app first, so the catalogs hold every string the code uses: Xcode adds them when it
builds. Strings a catalog marks stale (no longer in the code) or not to translate are left alone.
"""

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Wholphin's `values-*` folders, by the language Apple calls them. Android keeps old codes for
# Indonesian (`in`) and Hebrew (`iw`), and its `pt` is Portugal's Portuguese.
LOCALES = {
    "ar": "ar",
    "be": "be",
    "ca": "ca",
    "cs": "cs",
    "da": "da",
    "de": "de",
    "el": "el",
    "en-rGB": "en-GB",
    "es": "es",
    "et": "et",
    "fi": "fi",
    "fr": "fr",
    "hr": "hr",
    "hu": "hu",
    "in": "id",
    "it": "it",
    "iw": "he",
    "kab": "kab",
    "ko": "ko",
    "lo": "lo",
    "lv": "lv",
    "nb-rNO": "nb",
    "nl": "nl",
    "nn": "nn",
    "pl": "pl",
    "pt": "pt-PT",
    "pt-rBR": "pt-BR",
    "ro": "ro",
    "ru": "ru",
    "sk": "sk",
    "sl": "sl",
    "sq": "sq",
    "sr": "sr",
    "sv": "sv",
    "th": "th",
    "tr": "tr",
    "uk": "uk",
    "vi": "vi",
    "zh-rCN": "zh-Hans",
    "zh-rTW": "zh-Hant",
}

QUANTITIES = ("zero", "one", "two", "few", "many", "other")
XLIFF_G = "{urn:oasis:names:tc:xliff:document:1.2}g"
SPECIFIER = re.compile(r"%(?:(\d+)\$)?([-#+ 0,(]*)(\d+)?(?:\.(\d+))?([a-zA-Z%])")


# MARK: - Android strings


def android_text(raw):
    """A resource string as Android shows it: double quotes keep their whitespace and are
    dropped, other runs of whitespace become one space (none at the ends), and backslash
    escapes are resolved."""
    out = []  # (text, kept): kept text is quoted or escaped, so never trimmed.
    quoted = False
    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch == "\\" and i + 1 < len(raw):
            following = raw[i + 1]
            code = raw[i + 2 : i + 6]
            if following == "u" and re.fullmatch(r"[0-9a-fA-F]{4}", code):
                out.append((chr(int(code, 16)), True))
                i += 6
                continue
            out.append(({"n": "\n", "t": "\t"}.get(following, following), True))
            i += 2
        elif ch == '"':
            quoted = not quoted
            i += 1
        elif ch.isspace() and not quoted:
            while i < len(raw) and raw[i].isspace():
                i += 1
            out.append((" ", False))
        else:
            out.append((ch, quoted))
            i += 1
    while out and out[0] == (" ", False):
        out.pop(0)
    while out and out[-1] == (" ", False):
        out.pop()
    return "".join(text for text, _ in out)


def element_text(element):
    """The element's text, or `None` when it holds markup other than `xliff:g` placeholders,
    which a plain string can't carry."""
    if any(child.tag != XLIFF_G for child in element.iter() if child is not element):
        return None
    return android_text("".join(element.itertext()))


def apple_format(text):
    """Android's format specifiers as Swift's String Catalogs write them: `%s` as `%@` and `%d`
    as `%lld`, keeping positions, flags and widths. `None` when it has one Swift can't take."""
    unsupported = False

    def convert(match):
        nonlocal unsupported
        position, flags, width, precision, conversion = match.groups()
        if conversion == "%":
            return "%%"
        prefix = "%" + (f"{position}$" if position else "") + flags + (width or "")
        if conversion == "s":
            return prefix + "@"
        if conversion == "d":
            return prefix + "lld"
        if conversion in "fe":
            return prefix + (f".{precision}" if precision is not None else "") + conversion
        unsupported = True
        return match.group(0)

    converted = SPECIFIER.sub(convert, text)
    return None if unsupported else converted


def arguments(text):
    """The arguments a format string takes, by position: {1: "@", 2: "lld"}. `None` when it
    mixes numbered and unnumbered specifiers."""
    found = {}
    numbered = unnumbered = 0
    for match in SPECIFIER.finditer(text):
        position, _, _, precision, conversion = match.groups()
        if conversion == "%":
            continue
        kind = text[match.start() : match.end()].split("$")[-1].lstrip("%-#+ 0,(0123456789.")
        if position:
            numbered += 1
            found[int(position)] = kind
        else:
            unnumbered += 1
            found[unnumbered] = kind
    if numbered and unnumbered:
        return None
    return found


def canonical(text):
    """The text as Xcode writes a key: no argument numbers, which it only adds to values.
    `None` when the numbers aren't 1, 2, 3… in order, so dropping them would change the text."""
    if text is None:
        return None
    positions = [int(p) for p in re.findall(r"%(\d+)\$", text)]
    if positions != list(range(1, len(positions) + 1)):
        return None
    return re.sub(r"%\d+\$", "%", text)


def read_strings(path):
    """{name: text} for plain strings and {name: {quantity: text}} for plurals, in Swift's
    format, leaving out strings Wholphin marks untranslatable."""
    strings, plurals = {}, {}
    root = ET.parse(path).getroot()
    for element in root:
        name = element.get("name")
        if element.get("translatable") == "false" or not name:
            continue
        if element.tag == "string":
            text = element_text(element)
            if text:
                text = apple_format(text)
            if text:
                strings[name] = text
        elif element.tag == "plurals":
            items = {}
            for item in element.findall("item"):
                text = element_text(item)
                text = apple_format(text) if text else None
                if text and item.get("quantity") in QUANTITIES:
                    items[item.get("quantity")] = text
            if "other" in items:
                plurals[name] = items
    return strings, plurals


class Wholphin:
    """Wholphin's English strings, by their canonical text, and its translations."""

    def __init__(self, checkout):
        res = Path(checkout).expanduser()
        if (res / "app/src/main/res").is_dir():
            res = res / "app/src/main/res"
        english = res / "values/strings.xml"
        if not english.is_file():
            raise SystemExit(f"No Wholphin strings at {english}")
        self.strings, self.plurals = read_strings(english)
        self.by_text = {}
        for name, text in sorted(self.strings.items()):
            key = canonical(text)
            if key:
                self.by_text.setdefault(key, []).append(("string", name))
        for name, items in sorted(self.plurals.items()):
            key = canonical(items["other"])
            if key:
                self.by_text.setdefault(key, []).append(("plurals", name))
        self.by_folded_text = {}
        for key, matches in sorted(self.by_text.items()):
            self.by_folded_text.setdefault(key.casefold(), []).extend(matches)
        self.translations = {}
        for folder, locale in LOCALES.items():
            path = res / f"values-{folder}/strings.xml"
            if path.is_file():
                self.translations[locale] = read_strings(path)

    def matches(self, text, ignore_case=False):
        """Wholphin's strings whose English is `text`, exactly or, with `ignore_case`, but for
        capitals."""
        exact = self.by_text.get(text)
        return exact or (self.by_folded_text.get(text.casefold()) if ignore_case else None)

    def english(self, kind, name):
        return self.strings[name] if kind == "string" else self.plurals[name]["other"]

    def translation(self, locale, matches):
        """The first of the matching strings translated into `locale`, as a catalog
        localization, or `None`. A translation whose arguments differ from the English is
        skipped, so a wrong placeholder can never reach the app."""
        strings, plurals = self.translations.get(locale, ({}, {}))
        for kind, name in matches:
            expected = arguments(self.english(kind, name))
            if kind == "string" and name in strings:
                value = strings[name]
                if arguments(value) == expected:
                    return {"stringUnit": {"state": "translated", "value": value}}
            elif kind == "plurals" and name in plurals:
                items = plurals[name]
                # A form may leave the number out ("One episode"), but never takes others.
                if "other" not in items or arguments(items["other"]) != expected:
                    continue
                if any(not set((arguments(t) or {}).items()) <= set(expected.items()) for t in items.values()):
                    continue
                if not expected:
                    return {"stringUnit": {"state": "translated", "value": items["other"]}}
                forms = {
                    quantity: {"stringUnit": {"state": "translated", "value": text}}
                    for quantity, text in items.items()
                }
                return {"variations": {"plural": forms}}
        return None


# MARK: - String Catalogs


def source_text(key, entry, source_language):
    """What the catalog's own language says for `key`: its plural "other" form, its value, or
    the key itself."""
    localization = entry.get("localizations", {}).get(source_language, {})
    other = localization.get("variations", {}).get("plural", {}).get("other", {})
    value = other.get("stringUnit", {}).get("value") or localization.get("stringUnit", {}).get("value")
    return canonical(value) if value else key


def dump(value, level=0):
    """JSON the way Xcode writes a String Catalog, so a later build doesn't rewrite the file."""
    pad = "  " * level
    if isinstance(value, dict):
        if not value:
            return "{\n\n" + pad + "}"
        items = [
            f"{pad}  {json.dumps(key, ensure_ascii=False)} : {dump(value[key], level + 1)}" for key in sorted(value)
        ]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[\n\n" + pad + "]"
        return "[\n" + ",\n".join(f"{pad}  {dump(item, level + 1)}" for item in value) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def fill(catalog, wholphin, replace=False, ignore_case=False):
    """Adds Wholphin's translations to `catalog` (parsed JSON). Returns the keys it uses, the
    keys with no English match, and how many keys each language now has."""
    source_language = catalog.get("sourceLanguage", "en")
    used, unmatched = [], []
    for key, entry in catalog.get("strings", {}).items():
        if entry.get("extractionState") == "stale" or entry.get("shouldTranslate") is False:
            continue
        if not re.search(r"[^\W\d_]", re.sub(r"%[\d$.]*[@a-z]+", "", key)):
            continue  # Nothing but placeholders and punctuation, such as "%@ (%@)".
        used.append(key)
        matches = wholphin.matches(source_text(key, entry, source_language), ignore_case)
        if not matches:
            unmatched.append(key)
            continue
        localizations = entry.setdefault("localizations", {})
        for locale in wholphin.translations:
            if locale == source_language or (locale in localizations and not replace):
                continue
            localization = wholphin.translation(locale, matches)
            if localization:
                localizations[locale] = localization
    covered = {}
    for key in used:
        for locale in catalog["strings"][key].get("localizations", {}):
            if locale != source_language:
                covered[locale] = covered.get(locale, 0) + 1
    return used, unmatched, covered


def default_catalogs(root):
    return [root / "App/Localizable.xcstrings", *sorted(root.glob("Packages/*/Sources/*/Localizable.xcstrings"))]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("wholphin", help="a Wholphin checkout, or its app/src/main/res folder")
    parser.add_argument("catalogs", nargs="*", type=Path, help="the catalogs to fill (default: all)")
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    parser.add_argument("--replace", action="store_true", help="replace translations already there")
    parser.add_argument("--ignore-case", action="store_true", help="also match English that differs in capitals")
    args = parser.parse_args(argv)

    wholphin = Wholphin(args.wholphin)
    catalogs = args.catalogs or default_catalogs(Path(__file__).resolve().parent.parent)
    total, unmatched, covered = 0, [], {}
    for path in catalogs:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        used, missing, counts = fill(catalog, wholphin, replace=args.replace, ignore_case=args.ignore_case)
        total += len(used)
        unmatched += [(path, key) for key in missing]
        for locale, count in counts.items():
            covered[locale] = covered.get(locale, 0) + count
        if not args.dry_run:
            # Xcode ends the file without a newline.
            path.write_text(dump(catalog), encoding="utf-8")
        print(f"{path}: {len(used)} strings, {len(used) - len(missing)} found in Wholphin")

    print(f"\nCoverage of {total} strings by language:")
    for locale, count in sorted(covered.items(), key=lambda item: (-item[1], item[0])):
        print(f"  {locale:8} {count:5}  {100 * count / max(total, 1):5.1f}%")
    print(f"\n{len(unmatched)} strings Wholphin doesn't have (they stay English):")
    for path, key in unmatched:
        near = wholphin.matches(key, ignore_case=True)
        hint = f"  (Wholphin: {wholphin.english(*near[0])!r})" if near else ""
        print(f"  {path.name if len(catalogs) == 1 else path}: {key!r}{hint}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

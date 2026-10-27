#!/usr/bin/env python3
"""Tests for import-wholphin-strings.py, on a small made-up Wholphin.

    python3 -I scripts/test_import_wholphin_strings.py
"""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True  # No __pycache__ next to the scripts.
SCRIPT = Path(__file__).resolve().parent / "import-wholphin-strings.py"
spec = importlib.util.spec_from_file_location("import_wholphin_strings", SCRIPT)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)

ENGLISH = """<resources xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2">
    <string name="app_name" translatable="false">Wholphin</string>
    <string name="add_favorite">Favorite</string>
    <string name="favorite">Favorite</string>
    <string name="continue_watching">Continue watching</string>
    <string name="unwatched">%d unwatched</string>
    <string name="seasons_of">Season %1$d of %2$s</string>
    <string name="cant_play">Can\\'t play \\"%1$s\\"</string>
    <string name="spaced">"  Two  spaces "</string>
    <string name="styled">Press <b>OK</b></string>
    <string name="placeholder">Ends at <xliff:g id="time">%1$s</xliff:g></string>
    <plurals name="episodes">
        <item quantity="one">%d episode</item>
        <item quantity="other">%d episodes</item>
    </plurals>
    <plurals name="trailers">
        <item quantity="one">Trailer</item>
        <item quantity="other">Trailers</item>
    </plurals>
</resources>
"""

GERMAN = """<resources>
    <string name="favorite">Favorit</string>
    <string name="continue_watching">Weiterschauen</string>
    <string name="unwatched">%d nicht gesehen</string>
    <string name="seasons_of">%2$s: Staffel %1$d</string>
    <string name="cant_play">\\"%1$s\\" kann nicht abgespielt werden</string>
    <string name="placeholder">Endet um %1$s</string>
    <plurals name="episodes">
        <item quantity="one">Eine Folge</item>
        <item quantity="other">%d Folgen</item>
    </plurals>
    <plurals name="trailers">
        <item quantity="one">Trailer</item>
        <item quantity="other">Trailer</item>
    </plurals>
</resources>
"""

# A broken translation: its placeholder is a string where the English has a number.
FRENCH = """<resources>
    <string name="add_favorite">Favori</string>
    <string name="unwatched">%s non vus</string>
</resources>
"""

INDONESIAN = """<resources>
    <string name="favorite">Favorit (id)</string>
</resources>
"""


def entry(**localizations):
    return {"localizations": localizations} if localizations else {}


def catalog():
    plural = {
        "plural": {
            "one": {"stringUnit": {"state": "translated", "value": "%lld episode"}},
            "other": {"stringUnit": {"state": "translated", "value": "%lld episodes"}},
        },
    }
    return {
        "sourceLanguage": "en",
        "strings": {
            "Favorite": entry(),
            "%lld unwatched": entry(),
            "Season %lld of %@": entry(en={"stringUnit": {"state": "new", "value": "Season %1$lld of %2$@"}}),
            "Can't play \"%@\"": entry(),
            "Ends at %@": entry(),
            "%lld episodes": entry(en={"variations": plural}),
            "Trailers": entry(),
            "Continue Watching": entry(),
            "Not in Wholphin": entry(),
            "Gone": {"extractionState": "stale"},
            "%@ (%@)": entry(),
        },
        "version": "1.0",
    }


class ImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        res = Path(cls.directory.name) / "app/src/main/res"
        files = [("values", ENGLISH), ("values-de", GERMAN), ("values-fr", FRENCH), ("values-in", INDONESIAN)]
        for folder, text in files:
            (res / folder).mkdir(parents=True)
            (res / folder / "strings.xml").write_text(text, encoding="utf-8")
        cls.wholphin = importer.Wholphin(cls.directory.name)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def filled(self, **options):
        strings = catalog()
        result = importer.fill(strings, self.wholphin, **options)
        return strings["strings"], result

    def value(self, strings, key, locale):
        return strings[key]["localizations"][locale]["stringUnit"]["value"]

    def test_android_escapes_quotes_and_whitespace_are_resolved(self):
        self.assertEqual(importer.android_text("Can\\'t  stop\\nnow"), "Can't stop\nnow")
        self.assertEqual(importer.android_text('"  Two  spaces "'), "  Two  spaces ")
        self.assertEqual(importer.android_text("caf\\u00e9"), "café")

    def test_format_specifiers_become_swift_ones(self):
        self.assertEqual(importer.apple_format("%1$s of %2$d"), "%1$@ of %2$lld")
        self.assertEqual(importer.apple_format("%s, %d, %02d, %.2f, 100%%"), "%@, %lld, %02lld, %.2f, 100%%")
        self.assertIsNone(importer.apple_format("%x"))

    def test_keys_drop_argument_numbers_only_when_in_order(self):
        self.assertEqual(importer.canonical("Season %1$lld of %2$@"), "Season %lld of %@")
        self.assertIsNone(importer.canonical("%2$@ then %1$@"))

    def test_untranslatable_and_styled_strings_are_left_out(self):
        self.assertNotIn("app_name", self.wholphin.strings)
        self.assertNotIn("styled", self.wholphin.strings)
        self.assertEqual(self.wholphin.strings["placeholder"], "Ends at %1$@")

    def test_translations_are_copied_for_exact_matches(self):
        strings, _ = self.filled()
        self.assertEqual(self.value(strings, "Favorite", "de"), "Favorit")
        self.assertEqual(self.value(strings, "%lld unwatched", "de"), "%lld nicht gesehen")
        self.assertEqual(self.value(strings, "Season %lld of %@", "de"), "%2$@: Staffel %1$lld")
        self.assertEqual(self.value(strings, "Can't play \"%@\"", "de"), '"%1$@" kann nicht abgespielt werden')
        self.assertEqual(self.value(strings, "Ends at %@", "de"), "Endet um %1$@")

    def test_any_of_several_matching_strings_can_supply_a_language(self):
        strings, _ = self.filled()
        # "Favorite" is both add_favorite and favorite; French has only the first.
        self.assertEqual(self.value(strings, "Favorite", "fr"), "Favori")

    def test_android_locale_codes_become_apple_ones(self):
        strings, _ = self.filled()
        self.assertEqual(self.value(strings, "Favorite", "id"), "Favorit (id)")
        self.assertNotIn("in", strings["Favorite"]["localizations"])

    def test_plurals_keep_their_forms(self):
        strings, _ = self.filled()
        forms = strings["%lld episodes"]["localizations"]["de"]["variations"]["plural"]
        self.assertEqual(forms["one"]["stringUnit"]["value"], "Eine Folge")
        self.assertEqual(forms["other"]["stringUnit"]["value"], "%lld Folgen")
        # A plural without a number is a plain string.
        self.assertEqual(self.value(strings, "Trailers", "de"), "Trailer")

    def test_a_translation_with_other_placeholders_is_skipped(self):
        strings, _ = self.filled()
        self.assertNotIn("fr", strings["%lld unwatched"]["localizations"])

    def test_strings_wholphin_lacks_stay_english_and_are_reported(self):
        strings, (used, unmatched, covered) = self.filled()
        self.assertNotIn("localizations", strings["Not in Wholphin"])
        self.assertIn("Not in Wholphin", unmatched)
        self.assertNotIn("Gone", used)
        self.assertNotIn("%@ (%@)", used)
        self.assertEqual(covered["de"], 7)
        self.assertEqual(covered["fr"], 1)

    def test_strings_that_differ_in_capitals_match_only_when_asked(self):
        strings, (_, unmatched, _) = self.filled()
        self.assertIn("Continue Watching", unmatched)
        matches = self.wholphin.matches("Continue Watching", ignore_case=True)
        self.assertEqual(matches, [("string", "continue_watching")])
        strings, _ = self.filled(ignore_case=True)
        self.assertEqual(self.value(strings, "Continue Watching", "de"), "Weiterschauen")

    def test_existing_translations_are_kept_unless_replaced(self):
        strings = catalog()
        strings["strings"]["Favorite"] = entry(de={"stringUnit": {"state": "translated", "value": "Mein Favorit"}})
        importer.fill(strings, self.wholphin)
        self.assertEqual(self.value(strings["strings"], "Favorite", "de"), "Mein Favorit")
        importer.fill(strings, self.wholphin, replace=True)
        self.assertEqual(self.value(strings["strings"], "Favorite", "de"), "Favorit")

    def test_catalogs_are_written_as_xcode_writes_them(self):
        text = importer.dump({"strings": {"": {}, "Hi": {"comment": "A \"greeting\"\n"}}, "version": "1.0"})
        self.assertEqual(
            text,
            '{\n  "strings" : {\n    "" : {\n\n    },\n    "Hi" : {\n'
            '      "comment" : "A \\"greeting\\"\\n"\n    }\n  },\n  "version" : "1.0"\n}',
        )
        self.assertEqual(json.loads(text)["strings"]["Hi"]["comment"], 'A "greeting"\n')


if __name__ == "__main__":
    unittest.main()

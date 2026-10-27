import AnemoneCore
import Testing

struct LicenseTextTests {
    @Test func `splits at blank lines and keeps line breaks`() {
        let text = """
        MIT License

        Copyright (c) 2015 Someone

        Permission is hereby granted,
          free of charge,
        \t to any person.
        """

        #expect(LicenseText.paragraphs(text) == [
            "MIT License",
            "Copyright (c) 2015 Someone",
            "Permission is hereby granted,\n  free of charge,\n     to any person.",
        ])
    }

    @Test func `cuts long paragraphs so each fits on screen`() {
        let text = (1 ... 5).map { "line \($0)" }.joined(separator: "\n")

        #expect(LicenseText.paragraphs(text, maxLines: 2) == [
            "line 1\nline 2",
            "line 3\nline 4",
            "line 5",
        ])
    }

    @Test func `treats Windows line endings and runs of blank lines as one break`() {
        #expect(LicenseText.paragraphs("a\r\nb\r\n\r\n   \r\n\r\nc\r\n") == ["a\nb", "c"])
    }

    @Test func `an empty text has no paragraphs`() {
        #expect(LicenseText.paragraphs("").isEmpty)
        #expect(LicenseText.paragraphs("\n \n").isEmpty)
    }
}

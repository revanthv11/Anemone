import Foundation

/// Compares the language codes on streams and in settings. Files tag streams with ISO 639-2
/// codes in either form (`fre` or `fra`), players and settings sometimes use ISO 639-1 (`fr`),
/// and Jellyfin's own language list uses the first form. Wholphin compares the strings as they
/// are; this treats every spelling of a language as the same.
public enum LanguageCode {
    /// Missing, or a code that names no particular language, as in Wholphin.
    public static func isUnknown(_ code: String?) -> Bool {
        guard let code = code?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { return true }
        return ["unknown", "und", "undetermined", "mul", "zxx"].contains(code.lowercased())
    }

    /// Whether two codes name the same language; never for an unknown one.
    public static func same(_ lhs: String?, _ rhs: String?) -> Bool {
        guard !isUnknown(lhs), !isUnknown(rhs), let lhs, let rhs else { return false }
        return canonical(lhs) == canonical(rhs)
    }

    /// The same language, or a stream whose language isn't known: Wholphin's
    /// `equalsLangOrUnknown`, for subtitles that may well be in the wanted language.
    public static func sameOrUnknown(_ code: String?, _ language: String) -> Bool {
        isUnknown(code) || same(code, language)
    }

    /// The ISO 639-2 terminology code (`fra`), from any of the three spellings.
    static func canonical(_ code: String) -> String {
        let primary = code.lowercased().split { $0 == "-" || $0 == "_" }.first.map(String.init) ?? code.lowercased()
        if let terminology = terminologyCodes[primary] {
            return terminology
        }
        if primary.count == 2, let alpha3 = Locale.LanguageCode(primary).identifier(.alpha3) {
            return alpha3
        }
        return primary
    }

    /// ISO 639-2's bibliographic codes that differ from the terminology codes.
    private static let terminologyCodes = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho",
        "cze": "ces", "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu",
        "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri", "may": "msa",
        "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]
}

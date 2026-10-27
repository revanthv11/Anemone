// swiftformat:disable all
import Foundation

// Deliberate SwiftLint violations to check the lint job on Linux. Removed before merging.
enum LintCheck {
    // optional_data_string_conversion, a SwiftSyntax rule.
    static func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    // statement_position, a rule that needs SourceKit.
    static func sign(_ value: Int) -> Int {
        if value < 0 {
            return -1
        }else {
            return 1
        }
    }
}

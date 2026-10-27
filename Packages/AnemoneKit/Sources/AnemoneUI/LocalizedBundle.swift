import Foundation

public extension LocalizedStringResource.BundleDescription {
    /// AnemoneUI's own bundle, which holds its String Catalog. A `LocalizedStringResource`
    /// otherwise looks in the app's bundle, where the words AnemoneUI says itself aren't.
    static var anemoneUI: Self {
        .atURL(Bundle.module.bundleURL)
    }
}

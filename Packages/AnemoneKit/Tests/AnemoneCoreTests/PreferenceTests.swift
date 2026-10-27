import AnemoneCore
import Foundation
import Testing

/// Settings kept in UserDefaults.
struct PreferenceTests {
    private enum SkipBehaviour: String, PreferenceValue {
        case ignore
        case ask
        case autoSkip
    }

    private let defaults: UserDefaults

    init() throws {
        let suite = "PreferenceTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func `a preference has its default until it's set`() {
        let autoPlay = Preference("autoPlayNext", default: true)
        let delay = Preference("autoPlayNextDelay", default: 15)

        #expect(autoPlay.value(in: defaults))
        #expect(delay.value(in: defaults) == 15)

        autoPlay.set(false, in: defaults)
        delay.set(30, in: defaults)

        #expect(!autoPlay.value(in: defaults))
        #expect(delay.value(in: defaults) == 30)
        autoPlay.reset(in: defaults)
        #expect(autoPlay.value(in: defaults))
    }

    @Test func `values are stored the way AppStorage stores them`() {
        let behaviour = Preference("skipIntro", default: SkipBehaviour.ask)
        let scale = Preference("scale", default: 1.0)

        behaviour.set(.autoSkip, in: defaults)
        scale.set(1.5, in: defaults)

        #expect(defaults.string(forKey: "skipIntro") == "autoSkip")
        #expect(defaults.double(forKey: "scale") == 1.5)
        defaults.set("ask", forKey: "skipIntro")
        #expect(behaviour.value(in: defaults) == .ask)
    }

    @Test func `a stored value that no longer fits falls back to the default`() {
        let behaviour = Preference("skipIntro", default: SkipBehaviour.ask)
        let count = Preference("count", default: 3)

        defaults.set("removedCase", forKey: "skipIntro")
        defaults.set("three", forKey: "count")

        #expect(behaviour.value(in: defaults) == .ask)
        #expect(count.value(in: defaults) == 3)
    }
}

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

    private enum RepeatMode: Int, PreferenceValue {
        case off
        case all
        case one
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

    /// A launch argument such as `-controllerTimeoutMs 500` reaches UserDefaults as text, as
    /// these do; a test can't set the process's own arguments without replacing them for every
    /// test running beside it.
    @Test func `numbers and switches given as launch arguments are read`() {
        let timeout = Preference("controllerTimeoutMs", default: 5000)
        let scale = Preference("scale", default: 1.0)
        let autoPlay = Preference("autoPlayNext", default: false)
        let refreshRate = Preference("refreshRate", default: false)

        defaults.set("500", forKey: "controllerTimeoutMs")
        defaults.set("1.25", forKey: "scale")
        defaults.set("YES", forKey: "autoPlayNext")
        defaults.set("true", forKey: "refreshRate")

        #expect(timeout.value(in: defaults) == 500)
        #expect(scale.value(in: defaults) == 1.25)
        #expect(autoPlay.value(in: defaults))
        #expect(refreshRate.value(in: defaults))

        defaults.set("NO", forKey: "autoPlayNext")
        defaults.set("0", forKey: "refreshRate")
        #expect(!autoPlay.value(in: defaults, default: true))
        #expect(!refreshRate.value(in: defaults, default: true))
    }

    @Test func `an enum with an Int raw value is read from a launch argument too`() {
        let mode = Preference("repeatMode", default: RepeatMode.off)

        defaults.set("2", forKey: "repeatMode")

        #expect(mode.value(in: defaults) == .one)
    }

    @Test func `text that isn't a number or a switch falls back to the default`() {
        let timeout = Preference("controllerTimeoutMs", default: 5000)
        let scale = Preference("scale", default: 1.0)
        let autoPlay = Preference("autoPlayNext", default: true)

        defaults.set("soon", forKey: "controllerTimeoutMs")
        defaults.set("", forKey: "scale")
        defaults.set("maybe", forKey: "autoPlayNext")

        #expect(timeout.value(in: defaults) == 5000)
        #expect(scale.value(in: defaults) == 1.0)
        #expect(autoPlay.value(in: defaults))
    }

    @Test func `stored numbers keep being read as they were`() {
        let timeout = Preference("controllerTimeoutMs", default: 5000)
        let autoPlay = Preference("autoPlayNext", default: false)
        let scale = Preference("scale", default: 1.0)

        defaults.set(800, forKey: "controllerTimeoutMs")
        defaults.set(true, forKey: "autoPlayNext")
        defaults.set(2, forKey: "scale")

        #expect(timeout.value(in: defaults) == 800)
        #expect(autoPlay.value(in: defaults))
        #expect(scale.value(in: defaults) == 2.0)
    }
}

private extension Preference<Bool> {
    /// The value with another default, to tell a stored `false` from a missing one.
    func value(in defaults: UserDefaults, default fallback: Bool) -> Bool {
        Preference(key, default: fallback).value(in: defaults)
    }
}

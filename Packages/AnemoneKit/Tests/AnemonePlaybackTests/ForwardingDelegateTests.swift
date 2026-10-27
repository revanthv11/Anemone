@testable import AnemonePlayback
import Foundation
import Testing

/// A delegate standing in front of another, as the drawn subtitles' transport-bar watcher does
/// with the system player's: whoever set theirs still hears everything.
@MainActor
struct ForwardingDelegateTests {
    @Test func `messages it doesn't answer go on to the delegate it stands in front of`() {
        let control = TestControl()
        let own = OwnDelegate()
        control.delegate = own
        let watcher = Watcher()

        watcher.standInFront(of: control, at: \.delegate)
        control.delegate?.controlWillShow?()
        control.delegate?.controlDidHide?()

        #expect(control.delegate === watcher)
        // Its own message, which it passes on, and one it doesn't answer.
        #expect(watcher.shown == 1)
        #expect(own.shown == 1)
        #expect(own.hidden == 1)
    }

    @Test func `it steps aside for the delegate it stood in front of`() {
        let control = TestControl()
        let own = OwnDelegate()
        control.delegate = own
        let watcher = Watcher()
        watcher.standInFront(of: control, at: \.delegate)

        watcher.stepAside(from: control, at: \.delegate)

        #expect(control.delegate === own)
        control.delegate?.controlWillShow?()
        #expect(watcher.shown == 0)
        #expect(own.shown == 1)
    }

    @Test func `a delegate set after it is stood in front of again, not forgotten`() {
        let control = TestControl()
        let watcher = Watcher()
        watcher.standInFront(of: control, at: \.delegate)
        let later = OwnDelegate()
        control.delegate = later

        watcher.standInFront(of: control, at: \.delegate)
        // Again, while it's in front: it doesn't stand in front of itself.
        watcher.standInFront(of: control, at: \.delegate)
        control.delegate?.controlDidHide?()

        #expect(control.delegate === watcher)
        #expect(later.hidden == 1)
        // A delegate set after it, which it isn't in front of, stays when it steps aside.
        let last = OwnDelegate()
        control.delegate = last
        watcher.stepAside(from: control, at: \.delegate)
        #expect(control.delegate === last)
    }

    @Test func `without a delegate before it, it answers alone`() {
        let control = TestControl()
        let watcher = Watcher()

        watcher.standInFront(of: control, at: \.delegate)

        #expect(control.delegate?.responds(to: #selector(TestControlDelegate.controlDidHide)) == false)
        control.delegate?.controlWillShow?()
        #expect(watcher.shown == 1)
        watcher.stepAside(from: control, at: \.delegate)
        #expect(control.delegate == nil)
    }
}

@MainActor
@objc private protocol TestControlDelegate: NSObjectProtocol {
    @objc optional func controlWillShow()
    @objc optional func controlDidHide()
}

/// A control with a weak delegate, as `AVPlayerViewController` has.
@MainActor
private final class TestControl {
    weak var delegate: (any TestControlDelegate)?
}

@MainActor
private final class OwnDelegate: NSObject, TestControlDelegate {
    var shown = 0
    var hidden = 0

    func controlWillShow() {
        shown += 1
    }

    func controlDidHide() {
        hidden += 1
    }
}

@MainActor
private final class Watcher: ForwardingDelegate, TestControlDelegate {
    var shown = 0

    func controlWillShow() {
        shown += 1
        (forwardee as? any TestControlDelegate)?.controlWillShow?()
    }
}

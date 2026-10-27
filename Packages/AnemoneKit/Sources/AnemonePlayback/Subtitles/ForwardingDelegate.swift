import Foundation

/// A delegate that stands in front of the one already set, to hear a message of its own: what
/// it doesn't answer goes on to that one (`forwardee`), and it steps aside when it's done. So
/// taking a system controller's delegate, as the drawn subtitles do to hear when the system
/// player's transport bar shows (`App/Playback/Subtitles`), takes nothing from whoever set it,
/// before or after. A subclass passes on the messages it answers itself.
@MainActor
open class ForwardingDelegate: NSObject {
    /// The delegate this stands in front of, if one was set.
    public nonisolated(unsafe) weak var forwardee: NSObjectProtocol?

    override public init() {
        super.init()
    }

    /// Becomes the delegate at `delegate` of `owner`, in front of the one there; again, if
    /// another has been set since.
    public func standInFront<Owner: AnyObject, Delegate>(
        of owner: Owner,
        at delegate: ReferenceWritableKeyPath<Owner, Delegate?>,
    ) {
        guard let this = self as? Delegate else { return }
        let current = owner[keyPath: delegate] as? NSObjectProtocol
        guard current !== self else { return }
        forwardee = current
        owner[keyPath: delegate] = this
    }

    /// Puts back the delegate this stood in front of, unless another has been set since.
    public func stepAside<Owner: AnyObject, Delegate>(
        from owner: Owner,
        at delegate: ReferenceWritableKeyPath<Owner, Delegate?>,
    ) {
        guard (owner[keyPath: delegate] as? NSObjectProtocol) === self else { return }
        owner[keyPath: delegate] = forwardee as? Delegate
        forwardee = nil
    }

    override public nonisolated func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwardee?.responds(to: selector) == true
    }

    override public nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
        guard let forwardee, forwardee.responds(to: selector) else { return nil }
        return forwardee
    }
}

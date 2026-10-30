/// What the overlay hears from the remote, and what it says back to the view controller.
public extension PlayerOverlay {
    /// The Siri Remote's buttons, as the overlay hears them.
    enum Button: Hashable, Sendable {
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case select
        case menu
        case playPause
    }

    /// Where focus is, as far as presses are concerned.
    enum Focus: Sendable {
        /// On the video: the controls are hidden.
        case video
        case seekBar
        /// On a feature's action over the video, such as Skip Intro.
        case action
        /// On the controls' button that skips the rest of the segment playing.
        case skipButton
        /// On any other button.
        case control
    }

    /// What the view controller does with a press.
    enum Outcome: Sendable {
        case handled
        /// Left to the focus engine, which moves focus or presses the focused button.
        case passedOn
        /// Close the player.
        case close
    }
}

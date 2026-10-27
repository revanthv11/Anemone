import AnemoneJellyfin

/// Playback, through the controller and its engine.
public extension PlayerOverlay {
    func togglePlayPause() {
        guard !controller.hasEnded else { return }
        if isPaused {
            controller.engine.play()
        } else {
            controller.engine.pause()
        }
        pulse()
    }

    /// Wholphin's Previous: the previous entry near the start of this one, otherwise back to the
    /// start. Intros are passed over.
    func previous() {
        if let index = controller.queue.previousIndex, controller.engine.currentTime < Self.restartThreshold {
            play(entryAt: index)
        } else {
            seeker.jump(to: .zero)
            pulse()
        }
    }

    var hasNext: Bool {
        controller.queue.next != nil
    }

    /// The next entry, passing over intros.
    func next() {
        guard let index = controller.queue.nextIndex else { return }
        play(entryAt: index)
    }

    /// Plays another queue entry, as the queue row does. From the credits, the entry playing is
    /// marked played, as when Up Next moves on from them.
    func play(entryAt index: Int) {
        seeker.cancel()
        hideControls()
        controller.play(entryAt: index, markingCurrentPlayed: controller.hasReachedCredits)
    }

    /// Jumps to a chapter and hides the controls, as Wholphin's chapter row does.
    func jump(to chapter: Chapter) {
        seeker.jump(to: chapter.start)
        hideControls()
    }

    /// Skips the rest of a segment from the controls, as Wholphin's button there does: just past
    /// its end, as `SegmentSkipping`'s own skip lands (so playback is out of the segment however
    /// the engine rounds), or the end of the video when it runs past it.
    func skipRest(of segment: MediaSegment) {
        seeker.jump(to: segment.end + .milliseconds(1))
        pulse()
    }
}

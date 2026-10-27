import AnemoneJellyfin

/// The note about skipped items.
extension UpNext {
    /// Once, when the first entry gets under way, after any intros.
    func noteSkipped(in controller: PlaybackController) {
        let queue = controller.queue
        guard !hasNotedSkipped, !queue.current.isIntro, queue.skippedCount + queue.overLimitCount > 0 else { return }
        hasNotedSkipped = true
        let accessories = controller.accessories
        let (title, message) = Self.skippedNote(for: queue)
        accessories.show(PlayerCard(
            id: Self.skippedCard,
            title: title,
            message: message,
            actions: [
                PlayerAction(id: "skipped.ok", title: "OK") {
                    accessories.dismissCard(Self.skippedCard)
                },
            ],
        ))
        // Eight seconds, long enough to read.
        let length = second * 8
        noteTimer = Task {
            try? await Task.sleep(for: length)
            guard !Task.isCancelled else { return }
            accessories.dismissCard(Self.skippedCard)
        }
    }

    /// How many items were left out, and why, not counting intros among those playing. Wholphin
    /// leaves out what's past its 100 items without a word.
    static func skippedNote(for queue: PlaybackQueue) -> (title: String, message: String) {
        let playing = queue.countWithoutIntros
        let skipped = queue.skippedCount
        let overLimit = queue.overLimitCount
        let title = if overLimit > 0 {
            "Playing \(playing) of \(playing + skipped + overLimit) items"
        } else {
            skipped == 1 ? "Skipping 1 item" : "Skipping \(skipped) items"
        }
        let reasons = [
            overLimit > 0 ? "A queue holds up to \(JellyfinSession.queueLimit) items." : nil,
            skipped > 0 ? "Only videos play here for now." : nil,
        ]
        return (title, reasons.compactMap(\.self).joined(separator: "\n"))
    }
}

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
                PlayerAction(id: "skipped.ok", title: String(localized: "OK", bundle: .module)) {
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
            String(localized: "Playing \(playing) of \(playing + skipped + overLimit) items", bundle: .module)
        } else {
            // One key with plural forms in the String Catalog.
            String(localized: "Skipping \(skipped) items", bundle: .module)
        }
        let reasons = [
            overLimit > 0
                ? String(localized: "A queue holds up to \(JellyfinSession.queueLimit) items.", bundle: .module)
                : nil,
            skipped > 0 ? String(localized: "Only videos play here for now.", bundle: .module) : nil,
        ]
        return (title, reasons.compactMap(\.self).joined(separator: "\n"))
    }
}

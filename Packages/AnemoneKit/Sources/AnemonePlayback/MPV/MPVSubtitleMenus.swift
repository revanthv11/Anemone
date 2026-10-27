import AnemoneJellyfin
import Foundation

/// What only MPV does with subtitles, as menus in the overlay while MPV plays: Wholphin's
/// subtitle delay (`SubtitleDelay.kt`), and finding subtitles through the server and showing the
/// one downloaded (`SubtitleSearchUtils.kt`, `DownloadSubtitlesDialog.kt`).
@MainActor
public final class MPVSubtitleMenus: PlaybackFeature {
    /// Wholphin's steps, each way.
    static let delaySteps: [Duration] = [.milliseconds(50), .milliseconds(250), .seconds(1)]
    static let delayMenuID = "subtitleDelay"
    static let searchMenuID = "subtitleSearch"
    /// As many results as fit the menu's list.
    static let resultLimit = 8

    enum SearchState: Equatable {
        case idle
        case searching(String)
        case found([RemoteSubtitle], language: String)
        case downloading(String)
        case added(String)
        case failed(String)
    }

    private let session: JellyfinSession
    /// The languages to search in, as three-letter codes; the device's first.
    private let languages: [String]
    /// How often to look for a download on the server; Wholphin's 1.5 s.
    private let pollInterval: Duration
    private weak var controller: PlaybackController?
    private var stream: PlaybackStream?
    private var work: Task<Void, Never>?
    private(set) var state = SearchState.idle

    public init(
        session: JellyfinSession,
        languages: [String] = MPVSubtitleMenus.deviceLanguages,
        pollInterval: Duration = .milliseconds(1500),
    ) {
        self.session = session
        self.languages = languages
        self.pollInterval = pollInterval
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case let .loaded(stream, _):
            self.controller = controller
            self.stream = stream
            work?.cancel()
            state = .idle
            if let mpv = controller.engine.mpv {
                // Like Wholphin's, the delay is the entry's own.
                mpv.subtitleDelay = .zero
                showMenus()
            } else {
                controller.accessories.removeMenu(Self.delayMenuID)
                controller.accessories.removeMenu(Self.searchMenuID)
            }
        case .stopped:
            if controller.isStopped {
                work?.cancel()
            }
        default:
            break
        }
    }

    private var mpv: MPVPlayerEngine? {
        controller?.engine.mpv
    }

    private func showMenus() {
        guard let controller, let mpv else { return }
        controller.accessories.show(delayMenu(mpv))
        controller.accessories.show(searchMenu())
    }

    // MARK: - Delay

    private func delayMenu(_ mpv: MPVPlayerEngine) -> PlayerMenu {
        let delay = mpv.subtitleDelay
        let steps = Self.delaySteps.reversed().map { .zero - $0 } + [.zero] + Self.delaySteps
        return PlayerMenu(
            id: Self.delayMenuID,
            title: "Subtitle delay: \(Self.delayText(delay))",
            systemImage: "timer",
            options: steps.map { step in
                PlayerMenu.Option(
                    id: step == .zero ? "reset" : Self.delayText(step),
                    title: step == .zero ? "No delay" : Self.delayText(step),
                    isSelected: step == .zero && delay == .zero,
                ) { [weak self] in
                    self?.changeDelay(by: step)
                }
            },
        )
    }

    /// Adds `step` to the delay; zero resets it, as Wholphin's Reset does.
    func changeDelay(by step: Duration) {
        guard let mpv else { return }
        mpv.subtitleDelay = step == .zero ? .zero : mpv.subtitleDelay + step
        showMenus()
    }

    /// Such as "+0.25 s" or "-1 s".
    static func delayText(_ delay: Duration) -> String {
        let seconds = delay / .seconds(1)
        guard seconds != 0 else { return "0 s" }
        let text = String(format: "%.2f", abs(seconds))
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return "\(seconds < 0 ? "-" : "+")\(text) s"
    }

    // MARK: - Search and download

    private func searchMenu() -> PlayerMenu {
        PlayerMenu(
            id: Self.searchMenuID,
            title: searchTitle,
            systemImage: "captions.bubble",
            options: searchOptions,
        )
    }

    private var searchTitle: String {
        switch state {
        case .idle: "Download subtitles"
        case let .searching(language): "Searching in \(Self.languageName(language))…"
        case let .found(results, language) where results.isEmpty: "None found in \(Self.languageName(language))"
        case .found: "Download subtitles"
        case let .downloading(name): "Downloading \(name)…"
        case let .added(name): "Showing \(name)"
        case let .failed(message): message
        }
    }

    private var searchOptions: [PlayerMenu.Option] {
        let searches = languages.map { language in
            PlayerMenu.Option(
                id: "search.\(language)",
                title: "Search in \(Self.languageName(language))",
                isSelected: false,
            ) { [weak self] in
                self?.search(in: language)
            }
        }
        guard case let .found(results, _) = state else { return searches }
        let downloads = results.prefix(Self.resultLimit).map { result in
            let download: @MainActor () -> Void = { [weak self] in
                self?.download(result)
            }
            return PlayerMenu.Option(
                id: "result.\(result.id)",
                title: Self.describe(result),
                isSelected: false,
                select: download,
            )
        }
        return downloads + searches
    }

    func search(in language: String) {
        guard let stream else { return }
        work?.cancel()
        state = .searching(language)
        showMenus()
        work = Task { [weak self, session] in
            do {
                let results = try await session.searchSubtitles(for: stream.itemID, language: language)
                guard !Task.isCancelled else { return }
                self?.state = .found(results, language: language)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed("Couldn't search for subtitles")
            }
            self?.showMenus()
        }
    }

    /// Has the server download the subtitles, waits for them to show up beside the video, and
    /// adds them to MPV, as Wholphin switches to them.
    func download(_ subtitle: RemoteSubtitle) {
        guard let stream else { return }
        work?.cancel()
        state = .downloading(subtitle.name)
        showMenus()
        let mediaSourceID = stream.mediaSourceID ?? stream.itemID
        work = Task { [weak self, session, pollInterval] in
            do {
                let known = try await session.subtitleStreams(of: stream.itemID, mediaSourceID: mediaSourceID)
                try await session.downloadSubtitles(subtitle.id, for: stream.itemID)
                let new = try await session.newSubtitleStream(
                    of: stream.itemID,
                    mediaSourceID: mediaSourceID,
                    besides: known,
                    interval: pollInterval,
                )
                guard !Task.isCancelled else { return }
                guard let new,
                      let url = session.subtitleURL(for: new, of: stream.itemID, mediaSourceID: mediaSourceID)
                else {
                    self?.state = .failed("The server is taking too long to add them")
                    self?.showMenus()
                    return
                }
                self?.mpv?.addSubtitles(from: url, title: new.title, language: new.language)
                self?.state = .added(new.title)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed("Couldn't download the subtitles")
            }
            self?.showMenus()
        }
    }

    /// The name, then what helps choose: a match of the file, the provider, rating and downloads,
    /// and whether they're forced, for the hard of hearing, or machine-translated.
    static func describe(_ subtitle: RemoteSubtitle) -> String {
        var parts = [subtitle.name]
        if subtitle.isHashMatch {
            parts.append("Matches this file")
        }
        if let provider = subtitle.provider {
            parts.append(provider)
        }
        if let rating = subtitle.rating, rating > 0 {
            parts.append(String(format: "★ %.1f", rating))
        }
        if let downloads = subtitle.downloads {
            parts.append("\(downloads) downloads")
        }
        if subtitle.isForced {
            parts.append("Forced")
        }
        if subtitle.isHearingImpaired {
            parts.append("SDH")
        }
        if subtitle.isMachineTranslated {
            parts.append("Machine-translated")
        }
        return parts.joined(separator: " · ")
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// The device's language and English, as three-letter codes, which Jellyfin's subtitle
    /// search takes. Wholphin uses the user's subtitle language, else the device's.
    public static var deviceLanguages: [String] {
        let device = Locale.current.language.languageCode?.identifier(.alpha3) ?? "eng"
        return device == "eng" ? ["eng"] : [device, "eng"]
    }
}

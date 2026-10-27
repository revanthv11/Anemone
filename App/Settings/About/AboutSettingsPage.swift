import AnemoneCore
import SwiftUI

/// Settings › About: the app's version, its license and where its source is, then the
/// licenses of what it's built on, crediting Wholphin. Wholphin lists its libraries with
/// AboutLibraries (`ui/components/LicenseInfo.kt`); here the list comes from the repo's
/// `NOTICE.md`, which the app bundles at build time, so a credit added there shows up here.
struct AboutSettingsPage: View {
    private let version = AppVersion.current
    private let notice = BundledLicenses.notice

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LicenseTextPage(title: "GNU General Public License v3.0", licenseName: "Anemone")
                } label: {
                    LabeledContent("License", value: "GPL-3.0")
                }
                .accessibilityIdentifier("about.license")
                LabeledContent("Source code", value: AppVersion.repository)
                    .focusable()
                    .accessibilityIdentifier("about.source")
            } header: {
                Text("Anemone \(version.text)")
                    .accessibilityIdentifier("about.version")
            } footer: {
                Text("""
                Anemone is free software: you can redistribute it and modify it under the terms of the \
                GNU General Public License, version 3. The source code of every App Store and \
                TestFlight build is tagged in that repository; this one is \(version.sourceTag).
                """)
            }

            if let notice {
                credits(notice)
            } else {
                Text("This build is missing its NOTICE.md; the credits are at \(AppVersion.repository).")
                    .foregroundStyle(.secondary)
                    .focusable()
            }
        }
        .navigationTitle("About")
    }

    @ViewBuilder
    private func credits(_ notice: Notice) -> some View {
        let projects = notice.sections.filter(\.packages.isEmpty)
        if !projects.isEmpty {
            Section("Based on") {
                ForEach(projects) { section in
                    NavigationLink(section.title) {
                        CreditPage(section: section)
                    }
                    .accessibilityIdentifier("about.credit.\(section.title)")
                }
            }
        }
        ForEach(notice.sections.filter { !$0.packages.isEmpty }) { section in
            Section {
                ForEach(section.packages) { package in
                    NavigationLink {
                        PackagePage(package: package)
                    } label: {
                        LabeledContent(package.name, value: package.license)
                    }
                    .accessibilityIdentifier("about.package.\(package.name)")
                }
            } header: {
                Text(section.title)
            } footer: {
                // Anything the section says besides its table, such as a note on how a package is used.
                let notes = section.blocks.compactMap(\.text)
                if !notes.isEmpty {
                    MarkdownText(notes.joined(separator: "\n"))
                }
            }
        }
    }
}

/// This copy of Anemone's version and build, and the git tag of its source.
struct AppVersion {
    /// Shown, not linked: a TV can't open it.
    static let repository = "github.com/revanthv11/Anemone"

    let version: String
    let build: String

    static let current = AppVersion(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
    )

    var text: String {
        "\(version) (\(build))"
    }

    /// The tag `scripts/tag-build.sh` gives the commit this build was archived from; keep the two in step.
    var sourceTag: String {
        "build/\(version)-\(build)"
    }
}

/// NOTICE.md and the full license texts, linked or copied into this folder so Xcode copies them
/// into the app. `scripts/update-licenses.sh` refreshes the packages' texts.
enum BundledLicenses {
    static let notice: Notice? = text(named: "NOTICE", extension: "md")
        .map { Notice(markdown: $0).leavingOut(SeerrCredits.leftOut) }

    /// `Licenses/LICENSE-<name>.txt`, named after a NOTICE.md section ("Wholphin") or package ("Nuke").
    static func licenseText(for name: String) -> String? {
        text(named: "LICENSE-\(name)", extension: "txt")
    }

    private static func text(named name: String, extension fileExtension: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

extension Notice.Block {
    /// The block as Markdown lines for a footer; tables have their own rows.
    var text: String? {
        switch self {
        case let .heading(text), let .paragraph(text):
            text
        case let .list(items):
            items.map { "• " + $0 }.joined(separator: "\n")
        case .table:
            nil
        }
    }
}

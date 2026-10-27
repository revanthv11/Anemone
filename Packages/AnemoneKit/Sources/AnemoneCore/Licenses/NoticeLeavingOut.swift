public extension Notice {
    /// The notice without the sections titled, and the packages named, in `names`, for a build
    /// that leaves out what they credit, such as one without Seerr (docs/seerr.md). A table row
    /// goes once every package it credits is left out.
    func leavingOut(_ names: Set<String>) -> Notice {
        guard !names.isEmpty else { return self }
        return Notice(sections: sections.compactMap { section in
            guard !names.contains(section.title) else { return nil }
            var section = section
            section.blocks = section.blocks.map { block in
                guard case var .table(table) = block else { return block }
                table.rows = table.rows.filter { row in
                    let packages = Table(header: table.header, rows: [row]).packages
                    return packages.isEmpty || !packages.allSatisfy { names.contains($0.name) }
                }
                return .table(table)
            }
            return section
        })
    }
}

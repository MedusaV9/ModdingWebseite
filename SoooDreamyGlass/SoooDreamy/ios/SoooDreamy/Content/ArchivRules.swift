import Foundation

/// The six named drawers of station 4 ARCHIV (NEUBAU ENTSCHEID §4.4):
/// the cabinet front that replaces the 18-tile grid. On compact widths
/// the drawers are the Schrankfront cards; on regular widths they ARE
/// the sidebar groups of the hand-built split (`MemoriesSidebarGroup`
/// 4 → 6 — a pure mapping change, `sidebarAdaptable` stays deferred).
enum ArchivFach: String, CaseIterable, Identifiable {
    case alben, planfach, wertfach, chronik, lagerfach, tresorfach

    var id: String { rawValue }

    /// L10n key of the drawer's label plate.
    var titleKey: String { "archiv.fach.\(rawValue)" }

    /// SF Symbol on the drawer front (commandment 1: symbols, never emoji).
    var symbol: String {
        switch self {
        case .alben: return "photo.stack"
        case .planfach: return "list.clipboard"
        case .wertfach: return "banknote"
        case .chronik: return "books.vertical"
        case .lagerfach: return "shippingbox"
        case .tresorfach: return "lock.square.stack"
        }
    }
}

/// Pure drawer assignment — the authoritative ENTSCHEID §2.2 table as
/// code. Every Memories section id belongs to exactly ONE drawer, so the
/// cabinet can never lose a section; `ArchivRulesTests` pins the full
/// inventory (completeness guarantee stays testable, Welle N4).
enum ArchivRules {
    /// Section ids (`MemoriesSection.rawValue`) per drawer, in display
    /// order. The three Chronik/Lagerfach newcomers (week review, express-
    /// note history, countdown calendars) join the eighteen tile sections.
    static let sectionIds: [ArchivFach: [String]] = [
        .alben: ["gallery", "videos", "potd", "events", "story", "yearReview"],
        .planfach: ["lists", "bucket", "weekplan"],
        .wertfach: ["coupons", "goals"],
        .chronik: ["journal", "stats", "soundtrack", "canvas", "magazine",
                   "weekReview", "needsHistory"],
        .lagerfach: ["capsules", "seasonCalendar"],
        .tresorfach: ["vault"]
    ]

    /// Ordered section ids of one drawer.
    static func sections(in fach: ArchivFach) -> [String] {
        sectionIds[fach] ?? []
    }

    /// The drawer a section lives in — nil only for unknown ids.
    static func fach(forSection id: String) -> ArchivFach? {
        for fach in ArchivFach.allCases where sections(in: fach).contains(id) {
            return fach
        }
        return nil
    }

    /// Every mapped section id, cabinet order (drawer by drawer).
    static var allSectionIds: [String] {
        ArchivFach.allCases.flatMap { sections(in: $0) }
    }

    // MARK: Archive search (Fix-C Befund 5c — pure rule, view-free)

    /// Case- and diacritic-insensitive fold for title matching, so
    /// "traume" finds „Träumeliste" and "GALERIE" finds „Galerie".
    /// POSIX locale keeps the fold deterministic across devices.
    static func searchFold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Curated search aliases per section id (Re-Eval Runde 2: the index
    /// knew only the exact display titles — „Fotos" found nothing). The
    /// everyday words people actually try, DE+EN, stored ALREADY FOLDED
    /// (lowercase, no diacritics — pinned by tests) so matching stays a
    /// plain `contains` against `searchFold(query)`.
    static let sectionAliases: [String: [String]] = [
        "gallery": ["fotos", "bilder", "photos", "pictures"],
        "videos": ["filme", "clips", "movies"],
        "potd": ["tagesfoto", "daily photo"],
        "events": ["termine", "countdown", "dates"],
        "story": ["meilensteine", "zeitreise", "milestones", "timeline"],
        "lists": ["einkauf", "einkaufsliste", "todo", "shopping", "groceries"],
        "bucket": ["wunschliste", "wunsche", "dreams", "wishes"],
        "weekplan": ["woche", "week", "termine"],
        "coupons": ["gutschein", "vouchers", "coupons"],
        "goals": ["geld", "sparen", "sparziel", "money", "saving", "savings"],
        "journal": ["tagebuch", "fragen", "diary", "questions"],
        "stats": ["statistik", "zahlen", "statistics", "numbers"],
        "soundtrack": ["musik", "lieder", "songs", "playlist", "music"],
        "canvas": ["malen", "zeichnen", "drawing"],
        "magazine": ["magazin", "monatsruckblick", "magazine"],
        "yearReview": ["jahresruckblick", "year in review"],
        "weekReview": ["wochenruckblick", "week in review"],
        "capsules": ["zeitkapsel", "kapsel", "time capsule"],
        "seasonCalendar": ["adventskalender", "turchen", "advent calendar"],
        "vault": ["geheim", "privat", "secret", "private"],
    ]

    /// Section ids matching `query`, in cabinet order. Three index
    /// layers (Re-Eval Runde 2): the section's display title, its
    /// curated aliases, and its DRAWER's name — „Alben" opens the whole
    /// Alben drawer even though no section title contains the word.
    ///
    /// Sprachunabhängiger Index (Fix-Runde 3, Archiv-Befund 7): `titles`
    /// and `fachTitles` carry ALL language variants of a name (the view
    /// hands in DE + EN of every Fach/Bereich title — see
    /// `MemoriesL10n.searchTitleVariants`), and every variant joins the
    /// ONE fold index next to the aliases. „tresor"/„listen"/„alben"
    /// hit in the EN UI exactly like in the DE UI, and vice versa. The
    /// RULE stays Foundation-pure and Linux-testable; an id without any
    /// variant falls back to the id itself. An empty/whitespace query
    /// matches everything — the cabinet shows its full front.
    static func matchingSectionIds(query: String,
                                   titles: [String: [String]],
                                   fachTitles: [ArchivFach: [String]] = [:]) -> [String] {
        let needle = searchFold(query)
        guard !needle.isEmpty else { return allSectionIds }
        let hitFaecher = Set(ArchivFach.allCases.filter { fach in
            (fachTitles[fach] ?? []).contains { searchFold($0).contains(needle) }
        })
        return allSectionIds.filter { id in
            if let fach = fach(forSection: id), hitFaecher.contains(fach) {
                return true
            }
            let variants = titles[id].flatMap { $0.isEmpty ? nil : $0 } ?? [id]
            if variants.contains(where: { searchFold($0).contains(needle) }) {
                return true
            }
            return (sectionAliases[id] ?? []).contains { $0.contains(needle) }
        }
    }

    /// The drawers holding at least one match — while searching, exactly
    /// these open on the Schrankfront (Treffer öffnen das Fach).
    static func matchingFaecher(query: String,
                                titles: [String: [String]],
                                fachTitles: [ArchivFach: [String]] = [:]) -> [ArchivFach] {
        let hits = Set(matchingSectionIds(query: query, titles: titles,
                                          fachTitles: fachTitles))
        return ArchivFach.allCases.filter { fach in
            sections(in: fach).contains { hits.contains($0) }
        }
    }

    /// The closed drawer's one-line content preview („Galerie · Videos ·
    /// Momente …"): the drawer's section titles joined mid-dot — pure,
    /// so the joining rule is pinned once and the card only renders it.
    static func previewLine(titles: [String]) -> String {
        titles.joined(separator: " · ")
    }
}

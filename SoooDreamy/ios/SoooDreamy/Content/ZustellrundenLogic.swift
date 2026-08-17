import Foundation

// Zustellrunden — das Rundenmodell des Nachtpostamts (NEUBAU_POSTAMT §4,
// NEUBAU_ENTSCHEID §4.6). Drei Runden inszenieren nur, was ohnehin da ist;
// sie ERZEUGEN nichts, pushen nichts und sperren nichts (Bühne, nie Gate).
//
// Ehrlichkeits-Vertrag (dokumentiert, weil er die Poesie begrenzt):
//   * Runden sind GERÄTELOKAL: `from(hour:)` bekommt die lokale Stunde des
//     Geräts (Kalender/Zeitzone des Nutzers). Ein Paar über Zeitzonen sieht
//     zwei verschiedene Bühnen desselben Inhalts — das ist gewollt und wird
//     nirgends als „gemeinsamer Amtstag" verkauft (Dossier §8, Selbstkritik 3).
//   * Runden-gebunden (Re-Eval №1): die Runde leitet sich aus dem `now`
//     des Minuten-Ticks ab — wechselt sie im SICHTBAREN Tab, stellt die
//     neue Marke die Bühne und inszeniert neu. Der Bühnenwechsel im Blick
//     ist gewollt: er IST die Zustellung (dieselbe Wahrheit wie ein neuer
//     Brief im Fach), nie ein stiller Zustandssprung.
//   * Deterministisch: gleiche Stunde → gleiche Runde, gleiche Marke →
//     gleiche Antwort. Keine Uhr, kein Zufall, kein globaler Zustand.

/// Die drei Zustellrunden des Paar-Tages. Ersetzt das alte `DayPhase`
/// (morning/midday/evening/night) verlustfrei: `nachtpost` deckt den
/// früheren Abend- UND Nachtblock (17–05 Uhr), in dem beide dasselbe
/// Verhalten trugen (Gute-Nacht-Vorschlag).
enum Zustellrunde: String, Codable, CaseIterable {
    case morgenpost
    case tagespost
    case nachtpost

    /// Rundengrenzen nach Dossier §4: 05–11 Morgenpost · 11–17 Tagespost ·
    /// 17–05 Nachtpost (lokale Stunde des Geräts, 0–23).
    static func from(hour: Int) -> Zustellrunde {
        switch hour {
        case 5..<11: return .morgenpost
        case 11..<17: return .tagespost
        default: return .nachtpost
        }
    }

    /// L10n-Schlüssel des Rundennamens („Morgenpost" / "Morning post") —
    /// Stempelzeile und Zustellzettel lesen denselben Namen.
    var titleKey: String { "postfach.runde.\(rawValue)" }
}

/// Das Runden-Mengen-Modell (Fix2-A №6, vorher Ein-Marken-Modell): genau
/// EINE Inszenierung (Briefschlitz) pro Runde, Tag und Gerät. Die Marke
/// lebt in `@AppStorage("postfach.letzteInszenierung")` und sammelt pro
/// Datum ALLE bereits gespielten Runden — „2026-08-16#morgenpost,tagespost"
/// — damit eine Uhr-Rückstellung (Zeitzonen-Reise) nie eine schon
/// gespielte Runde erneut inszeniert. Die alte Ein-Marken-Form
/// („2026-08-16#tagespost") liest sich verlustfrei als Ein-Runden-Menge
/// (Migration ohne Sonderpfad). Die Marke steuert AUSSCHLIESSLICH
/// Briefschlitz + Stempelzeile — die Karten-Rangfolge bleibt
/// `DashboardPriority.layout`.
enum ZustellrundenLogic {
    /// Kanonische Choreografie-Identität EINER Runde: „2026-08-16#tagespost".
    /// (Task-Identität des Briefschlitz-Auftritts — der Speicher unten
    /// sammelt dagegen die ganze Tages-Menge.)
    static func marke(dateKey: String, runde: Zustellrunde) -> String {
        "\(dateKey)#\(runde.rawValue)"
    }

    /// Die an `dateKey` bereits gespielten Runden aus der gespeicherten
    /// Marke. Eine Marke eines ANDEREN Tages zählt nicht (neuer Tag =
    /// leere Menge, jede Runde darf wieder inszenieren); unbekannte
    /// Runden-Namen werden still ignoriert (vorwärts-kompatibel).
    static func gespielteRunden(dateKey: String, zuletzt: String?) -> Set<Zustellrunde> {
        guard let zuletzt, !zuletzt.isEmpty else { return [] }
        let teile = zuletzt.split(separator: "#", maxSplits: 1,
                                  omittingEmptySubsequences: false)
        guard teile.count == 2, teile[0] == dateKey else { return [] }
        return Set(teile[1].split(separator: ",")
            .compactMap { Zustellrunde(rawValue: String($0)) })
    }

    /// True genau dann, wenn diese Runde auf diesem Gerät heute noch nicht
    /// inszeniert wurde — auch nach einer Uhr-Rückstellung in eine schon
    /// gespielte Runde (die Menge vergisst nichts). Bewusste
    /// Mitternachts-Nuance: die Nachtpost, die über Mitternacht läuft,
    /// gilt ab 0 Uhr als Runde des NEUEN Tages — der neue Brief
    /// (Tagesfrage wechselt am dateKey) liegt dann ja wirklich im Fach.
    static func sollInszenieren(runde: Zustellrunde, dateKey: String,
                                zuletzt: String?) -> Bool {
        !gespielteRunden(dateKey: dateKey, zuletzt: zuletzt).contains(runde)
    }

    /// Die neue Speicher-Marke, nachdem `runde` an `dateKey` gespielt hat:
    /// die bisherige Tages-Menge plus diese Runde, kanonisch in
    /// Runden-Reihenfolge („{dateKey}#morgenpost,tagespost"). Idempotent —
    /// dieselbe Runde erneut zu markieren ändert die Marke nicht; ein
    /// Tageswechsel beginnt eine frische Menge.
    static func naechsteMarke(runde: Zustellrunde, dateKey: String,
                              zuletzt: String?) -> String {
        let runden = gespielteRunden(dateKey: dateKey, zuletzt: zuletzt)
            .union([runde])
        let liste = Zustellrunde.allCases.filter(runden.contains)
            .map(\.rawValue).joined(separator: ",")
        return "\(dateKey)#\(liste)"
    }
}

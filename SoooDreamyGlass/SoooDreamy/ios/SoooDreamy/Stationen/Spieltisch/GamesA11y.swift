import SwiftUI

/// Shared VoiceOver helpers for the games section. Boards describe
/// themselves via label/value; everything a sighted player only SEES
/// happen (reveals, verdicts, partner moves) is additionally posted as a
/// spoken announcement so VoiceOver players never miss a beat.
@MainActor
enum GamesA11y {
    /// Posts a VoiceOver announcement (game endings, reveals, partner moves).
    static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    /// Spoken name of a Battleship cell — column letter + row number
    /// ("A1" … "H8"), the classic call-out both partners can shout.
    static func battleshipCellName(_ cell: Int) -> String {
        let row = cell / Battleship.size
        let column = cell % Battleship.size
        let letter = Character(UnicodeScalar(UInt8(65 + column)))
        return "\(letter)\(row + 1)"
    }
}

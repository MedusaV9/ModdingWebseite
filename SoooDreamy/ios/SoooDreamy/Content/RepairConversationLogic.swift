import Foundation

enum RepairTurnKind: String, Codable, CaseIterable {
    case feeling
    case mirror
    case agreement
}

struct RepairExpectedTurn: Equatable {
    let memberID: String
    let kind: RepairTurnKind
}

enum RepairConversationLogic {
    static func expectedTurn(
        step: Int,
        creatorID: String,
        partnerID: String
    ) -> RepairExpectedTurn? {
        let sequence: [RepairExpectedTurn] = [
            RepairExpectedTurn(memberID: creatorID, kind: .feeling),
            RepairExpectedTurn(memberID: partnerID, kind: .mirror),
            RepairExpectedTurn(memberID: partnerID, kind: .feeling),
            RepairExpectedTurn(memberID: creatorID, kind: .mirror),
            RepairExpectedTurn(memberID: creatorID, kind: .agreement),
            RepairExpectedTurn(memberID: partnerID, kind: .agreement),
        ]
        guard sequence.indices.contains(step) else { return nil }
        return sequence[step]
    }

    static func canSubmit(
        memberID: String,
        kind: RepairTurnKind,
        step: Int,
        creatorID: String,
        partnerID: String,
        cooldownUntil: Date?,
        now: Date = Date()
    ) -> Bool {
        if let cooldownUntil, cooldownUntil > now { return false }
        return expectedTurn(step: step, creatorID: creatorID, partnerID: partnerID)
            == RepairExpectedTurn(memberID: memberID, kind: kind)
    }
}

struct ConsiderationCipherEnvelope: Codable, Equatable {
    let ciphertext: String
    let visibility: String
    let expiresAt: Date

    enum ValidationError: Error, Equatable {
        case invalidCiphertext
        case invalidVisibility
        case invalidExpiry
    }

    func validate(now: Date = Date()) throws {
        guard let data = Data(base64Encoded: ciphertext), data.count >= 16 else {
            throw ValidationError.invalidCiphertext
        }
        guard ["gentle", "detail"].contains(visibility) else {
            throw ValidationError.invalidVisibility
        }
        guard expiresAt > now else { throw ValidationError.invalidExpiry }
    }
}

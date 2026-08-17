import Foundation

// MARK: - Rituals & relationship endpoints

extension API {
    private struct OKResponse: Decodable { let ok: Bool }

    // MARK: Audio check-in

    func daymemos(limit: Int = 30) async throws -> DaymemosResponse {
        try await request("GET", "/api/daymemos", query: ["limit": String(limit)],
                          as: DaymemosResponse.self)
    }

    func daymemo(dateKey: String) async throws -> DaymemoDay {
        try await request("GET", "/api/daymemos/\(dateKey)", as: DaymemoDay.self)
    }

    /// Uploads (or re-records) my memo for `dateKey` (today ±1). AAC/m4a.
    func uploadDaymemo(dateKey: String, data: Data, durationSec: Double) async throws -> DaymemoDay {
        try await request("POST", "/api/daymemos/\(dateKey)",
                          rawBody: data, contentType: "audio/mp4",
                          headers: ["X-Duration-Sec": String(format: "%.2f", durationSec)],
                          longUpload: true,
                          as: DaymemoDay.self)
    }

    // MARK: Time capsules

    func capsules() async throws -> [TimeCapsule] {
        try await request("GET", "/api/capsules", as: CapsulesResponse.self).capsules
    }

    @discardableResult
    func sealCapsule(title: String?, emoji: String?, text: String,
                     photoId: String?, unlockAt: Date) async throws -> TimeCapsule {
        try await request("POST", "/api/capsules",
                          jsonBody: ["title": title, "emoji": emoji, "text": text,
                                     "photoId": photoId,
                                     "unlockAt": API.isoString(unlockAt)],
                          as: CapsuleResponse.self).capsule
    }

    /// Only the recipient may open, only after `unlockAt` — 409 otherwise.
    func openCapsule(id: String) async throws -> TimeCapsule {
        try await request("POST", "/api/capsules/\(id)/open", as: CapsuleResponse.self).capsule
    }

    /// Creator-only, unopened-only.
    func deleteCapsule(id: String) async throws {
        _ = try await request("DELETE", "/api/capsules/\(id)", as: OKResponse.self)
    }

    // MARK: Need button

    func needs(limit: Int = 30) async throws -> [NeedSignal] {
        try await request("GET", "/api/needs", query: ["limit": String(limit)],
                          as: NeedsResponse.self).needs
    }

    @discardableResult
    func sendNeed(type: NeedType, note: String?) async throws -> NeedSignal {
        try await request("POST", "/api/needs",
                          jsonBody: ["type": type.rawValue, "note": note],
                          as: NeedResponse.self).need
    }

    /// "Bin für dich da 🤍" — receiver-only, once.
    @discardableResult
    func ackNeed(id: String, note: String? = nil) async throws -> NeedSignal {
        let body: [String: Any?] = note.map { ["note": $0] } ?? [:]
        return try await request("POST", "/api/needs/\(id)/ack",
                                 jsonBody: body,
                                 as: NeedResponse.self).need
    }

    // MARK: Shared goals

    func goals() async throws -> [SharedGoal] {
        try await request("GET", "/api/goals", as: GoalsResponse.self).goals
    }

    @discardableResult
    func createGoal(title: String, emoji: String?, targetValue: Double,
                    unit: String?, targetDate: String?) async throws -> SharedGoal {
        try await request("POST", "/api/goals",
                          jsonBody: ["title": title, "emoji": emoji, "targetValue": targetValue,
                                     "unit": unit, "targetDate": targetDate],
                          as: GoalResponse.self).goal
    }

    /// Books progress (negative = correction). Returns the crossed milestone.
    func contributeToGoal(id: String, amount: Double, note: String?) async throws -> GoalContributionResponse {
        try await request("POST", "/api/goals/\(id)/contributions",
                          jsonBody: ["amount": amount, "note": note],
                          as: GoalContributionResponse.self)
    }

    @discardableResult
    func updateGoal(id: String, title: String? = nil, emoji: String? = nil,
                    targetValue: Double? = nil, unit: String? = nil,
                    targetDate: String? = nil) async throws -> SharedGoal {
        var body: [String: Any?] = [:]
        if let title { body["title"] = title }
        if let emoji { body["emoji"] = emoji }
        if let targetValue { body["targetValue"] = targetValue }
        if let unit { body["unit"] = unit }
        if let targetDate { body["targetDate"] = targetDate }
        return try await request("PATCH", "/api/goals/\(id)", jsonBody: body,
                                 as: GoalResponse.self).goal
    }

    func deleteGoal(id: String) async throws {
        _ = try await request("DELETE", "/api/goals/\(id)", as: OKResponse.self)
    }

    // MARK: Week plan

    func weekplan(start: String? = nil, days: Int = 7) async throws -> WeekplanResponse {
        var query = ["days": String(days)]
        if let start { query["start"] = start }
        return try await request("GET", "/api/weekplan", query: query,
                                 as: WeekplanResponse.self)
    }

    /// nil status clears my mark for that day.
    @discardableResult
    func setAvailability(dateKey: String, status: String?) async throws -> WeekplanDay {
        try await request("PUT", "/api/weekplan/\(dateKey)/availability",
                          jsonBody: ["status": status ?? NSNull()],
                          as: WeekplanDayResponse.self).day
    }

    /// Exactly one of `dateKey` (one-off) / `weekday` (recurring 0–6, UTC).
    @discardableResult
    func addWeekplanSlot(title: String, emoji: String?, kind: String,
                         dateKey: String?, weekday: Int?, time: String?) async throws -> WeekplanSlot {
        try await request("POST", "/api/weekplan/slots",
                          jsonBody: ["title": title, "emoji": emoji, "kind": kind,
                                     "dateKey": dateKey, "weekday": weekday, "time": time],
                          as: WeekplanSlotResponse.self).slot
    }

    func deleteWeekplanSlot(id: String) async throws {
        _ = try await request("DELETE", "/api/weekplan/slots/\(id)", as: OKResponse.self)
    }

    // MARK: App-event log (shared milestone feed)

    /// `GET /api/app-events` — newest first, optionally filtered by type
    /// (e.g. `movie_match` for the week-plan movie-night banner).
    func appEvents(type: String? = nil, limit: Int = 50) async throws -> [AppEventRecord] {
        var query = ["limit": String(limit)]
        if let type { query["type"] = type }
        return try await request("GET", "/api/app-events", query: query,
                                 as: AppEventsResponse.self).events
    }

    // MARK: Energy traffic light

    @discardableResult
    func setEnergy(level: EnergyLevel, note: String?) async throws -> MemberEnergy {
        let response: EnergyResponse = try await request(
            "PUT", "/api/energy",
            jsonBody: ["level": level.rawValue, "note": note],
            as: EnergyResponse.self)
        guard let energy = response.energy else {
            throw APIError.http(status: 500, code: "no_energy", message: nil, retryAfter: nil)
        }
        return energy
    }

    func clearEnergy() async throws {
        _ = try await request("DELETE", "/api/energy", as: OKResponse.self)
    }

    // MARK: Guided repair & consideration radar

    func repairSessions() async throws -> [RepairSession] {
        try await request("GET", "/api/repair", as: RepairSessionsResponse.self).sessions
    }

    @discardableResult
    func createRepairSession(promptId: String) async throws -> RepairSession {
        try await request("POST", "/api/repair",
                          jsonBody: ["promptId": promptId],
                          as: RepairSessionResponse.self).session
    }

    @discardableResult
    func submitRepairTurn(id: String, kind: String, text: String) async throws -> RepairSession {
        try await request("POST", "/api/repair/\(id)/turn",
                          jsonBody: ["kind": kind, "text": text],
                          as: RepairSessionResponse.self).session
    }

    @discardableResult
    func startRepairCooldown(id: String, minutes: Int) async throws -> RepairSession {
        try await request("POST", "/api/repair/\(id)/cooldown",
                          jsonBody: ["minutes": minutes],
                          as: RepairSessionResponse.self).session
    }

    func considerationHints() async throws -> [ConsiderationHint] {
        try await request("GET", "/api/consideration",
                          as: ConsiderationHintsResponse.self).hints
    }

    @discardableResult
    func shareConsideration(
        ciphertext: String,
        visibility: String,
        hours: Int
    ) async throws -> ConsiderationHint {
        try await request("POST", "/api/consideration",
                          jsonBody: ["ciphertext": ciphertext,
                                     "visibility": visibility,
                                     "hours": hours],
                          as: ConsiderationHintResponse.self).hint
    }

    @discardableResult
    func pauseConsideration(id: String) async throws -> ConsiderationHint {
        try await request("DELETE", "/api/consideration/\(id)",
                          as: ConsiderationHintResponse.self).hint
    }

    func goodThings(dateKey: String) async throws -> GoodThingsDay {
        try await request("GET", "/api/goodthings/\(dateKey)", as: GoodThingsDay.self)
    }

    @discardableResult
    func shareGoodThings(dateKey: String, texts: [String]) async throws -> GoodThingsDay {
        let items: [[String: Any]] = texts.map {
            ["text": $0, "aboutPartner": false]
        }
        return try await request("POST", "/api/goodthings/\(dateKey)",
                                 jsonBody: ["items": items],
                                 as: GoodThingsDay.self)
    }

    // MARK: Season calendars

    func seasonCalendars() async throws -> [CoupleSeasonCalendar] {
        try await request("GET", "/api/season-calendars",
                          as: SeasonCalendarsResponse.self).calendars
    }

    @discardableResult
    func createSeasonCalendar(
        title: String,
        emoji: String?,
        kind: SeasonCalendarKind,
        doors: [SeasonDoorDraft]
    ) async throws -> CoupleSeasonCalendar {
        let encodedDoors: [[String: Any]] = doors.map {
            [
                "unlockAt": API.isoString($0.unlockAt),
                "payload": ["kind": $0.kind.rawValue, "text": $0.text],
            ]
        }
        return try await request(
            "POST",
            "/api/season-calendars",
            jsonBody: [
                "title": title,
                "emoji": emoji,
                "kind": kind.rawValue,
                "doors": encodedDoors,
            ],
            as: SeasonCalendarResponse.self
        ).calendar
    }

    @discardableResult
    func openSeasonCalendarDoor(
        calendarId: String,
        doorId: String
    ) async throws -> CoupleSeasonCalendar {
        try await request(
            "POST",
            "/api/season-calendars/\(calendarId)/open",
            jsonBody: ["doorId": doorId],
            as: SeasonCalendarOpenResponse.self
        ).calendar
    }

    func deleteSeasonCalendar(id: String) async throws {
        _ = try await request("DELETE", "/api/season-calendars/\(id)", as: OKResponse.self)
    }

    // MARK: „Eure Woche" weekly review

    /// nil week = the current ISO week ("so far" view).
    func weekReview(week: String? = nil) async throws -> WeekReviewResponse {
        var query: [String: String] = [:]
        if let week { query["week"] = week }
        return try await request("GET", "/api/week-review", query: query,
                                 as: WeekReviewResponse.self)
    }

    /// Shares (or replaces) my highlight of the week — current or previous
    /// week only; the partner's pick reveals once both shared.
    @discardableResult
    func setWeekHighlight(week: String, text: String, photoId: String? = nil) async throws -> WeekReviewResponse {
        try await request("PUT", "/api/week-review/\(week)/highlight",
                          jsonBody: ["text": text, "photoId": photoId],
                          as: WeekReviewResponse.self)
    }

    /// Read receipt — completed weeks only (409 `week_not_over` otherwise).
    @discardableResult
    func markWeekReviewSeen(week: String) async throws -> WeekReviewSeenResponse {
        try await request("POST", "/api/week-review/\(week)/seen",
                          as: WeekReviewSeenResponse.self)
    }

    // MARK: Eigene Tagesfragen

    /// Only MY questions come back — the partner's pool stays a surprise.
    func customDailyQuestions() async throws -> CustomDailyQuestionsResponse {
        try await request("GET", "/api/daily-questions",
                          as: CustomDailyQuestionsResponse.self)
    }

    @discardableResult
    func addCustomDailyQuestion(text: String) async throws -> CustomDailyQuestionResponse {
        try await request("POST", "/api/daily-questions",
                          jsonBody: ["text": text],
                          as: CustomDailyQuestionResponse.self)
    }

    func deleteCustomDailyQuestion(id: String) async throws {
        _ = try await request("DELETE", "/api/daily-questions/\(id)", as: OKResponse.self)
    }

    // MARK: Monthly magazine

    func magazineMonths() async throws -> [String] {
        try await request("GET", "/api/magazine/months", as: MagazineMonthsResponse.self).months
    }

    func magazine(month: String) async throws -> MagazineIssue {
        try await request("GET", "/api/magazine/\(month)", as: MagazineIssue.self)
    }

    @discardableResult
    func markMagazineSeen(month: String) async throws -> MagazineSeenResponse {
        try await request("POST", "/api/magazine/\(month)/seen", as: MagazineSeenResponse.self)
    }
}

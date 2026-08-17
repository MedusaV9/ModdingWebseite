extends TestCase
## W4-P5 (INFRA) — Lücken-Tests für scripts/logic/vacation.gd: die bislang
## ungetesteten public funcs is_away / phase_at / postcards_due / remaining_ms
## (Coverage-Sweep Plan §2.4-13). Reine Timestamp-Mathematik, Uhr injiziert.

const Vacation := preload("res://scripts/logic/vacation.gd")

const NOW_MS := 1768478400000
const DAY_MS := 86400000


## Ein gebuchter beach-Trip (3 Tage): bookedAt = NOW, returnAt = +3 d,
## pickupBy = returnAt + 24 h.
func _booked_slice() -> Dictionary:
	var v := Vacation.default_slice()
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = "beach"
	v["bookedAt"] = NOW_MS
	v["returnAt"] = NOW_MS + 3 * DAY_MS
	v["pickupBy"] = NOW_MS + 4 * DAY_MS
	return v


func test_is_away_nur_bei_aktiver_phase() -> void:
	assert_false(Vacation.is_away({}), "kein Slice → daheim")
	assert_false(Vacation.is_away({"vacation": Vacation.default_slice()}), "none → daheim")
	assert_true(Vacation.is_away({"vacation": _booked_slice()}), "away → weg")
	var junk := {"vacation": {"phase": "quatschphase"}}
	assert_false(Vacation.is_away(junk), "unbekannte Phase → normalisiert auf none")


func test_phase_at_alle_uebergaenge() -> void:
	var v := _booked_slice()
	assert_eq(Vacation.phase_at({}, NOW_MS), "none", "leerer Slice → none")
	assert_eq(Vacation.phase_at(Vacation.default_slice(), NOW_MS), "none", "none bleibt none")
	assert_eq(Vacation.phase_at(v, NOW_MS), "away", "direkt nach Buchung")
	assert_eq(Vacation.phase_at(v, NOW_MS + 3 * DAY_MS - 1), "away", "kurz vor returnAt")
	assert_eq(Vacation.phase_at(v, NOW_MS + 3 * DAY_MS), "returnReady", "ab returnAt")
	assert_eq(Vacation.phase_at(v, NOW_MS + 4 * DAY_MS - 1), "returnReady", "kurz vor pickupBy")
	assert_eq(Vacation.phase_at(v, NOW_MS + 4 * DAY_MS), "overdue", "ab pickupBy")
	var kaputt := _booked_slice()
	kaputt["returnAt"] = 0
	assert_eq(Vacation.phase_at(kaputt, NOW_MS), "none", "returnAt fehlt → none")


func test_postcards_due_pro_vollem_tag_gedeckelt() -> void:
	var v := _booked_slice()
	assert_eq(Vacation.postcards_due(v, NOW_MS), 0, "Tag 0 → keine Karte")
	assert_eq(Vacation.postcards_due(v, NOW_MS + DAY_MS - 1), 0, "23:59 → noch keine")
	assert_eq(Vacation.postcards_due(v, NOW_MS + DAY_MS), 1, "voller Tag 1")
	assert_eq(Vacation.postcards_due(v, NOW_MS + 2 * DAY_MS), 2, "voller Tag 2")
	# 3-Tage-Trip → Deckel bei days-1 = 2 (letzter Tag = Heimreise).
	assert_eq(Vacation.postcards_due(v, NOW_MS + 3 * DAY_MS), 2, "Deckel days-1")
	assert_eq(Vacation.postcards_due(v, NOW_MS + 30 * DAY_MS), 2, "weit danach → Deckel hält")
	assert_eq(Vacation.postcards_due(Vacation.default_slice(), NOW_MS), 0, "none → 0")
	var kaputt := _booked_slice()
	kaputt["bookedAt"] = kaputt["returnAt"]
	assert_eq(Vacation.postcards_due(kaputt, NOW_MS + DAY_MS), 0, "returnAt<=bookedAt → 0")


func test_remaining_ms_pro_phase() -> void:
	var away := {"vacation": _booked_slice()}
	assert_eq(
		Vacation.remaining_ms(away, NOW_MS + DAY_MS), 2 * DAY_MS, "away → Countdown auf returnAt"
	)
	var ready := _booked_slice()
	ready["phase"] = Vacation.PHASE_RETURN_READY
	assert_eq(
		Vacation.remaining_ms({"vacation": ready}, NOW_MS + 3 * DAY_MS),
		DAY_MS,
		"returnReady → Countdown auf pickupBy"
	)
	var overdue := _booked_slice()
	overdue["phase"] = Vacation.PHASE_OVERDUE
	assert_eq(Vacation.remaining_ms({"vacation": overdue}, NOW_MS), 0, "overdue → 0")
	assert_eq(Vacation.remaining_ms({}, NOW_MS), 0, "kein Slice → 0")
	assert_eq(Vacation.remaining_ms(away, NOW_MS + 9 * DAY_MS), 0, "nach returnAt nie negativ")

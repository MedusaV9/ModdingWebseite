extends TestCase
## iOS-WIDGETS: der pure Snapshot-Builder (widget_snapshot.gd) — Zeit,
## Lokaltag, Zeitzone und Texte sind injiziert, alles laeuft headless.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")

## 2026-08-08 10:00:00 UTC — fester Anker fuer alle Faelle.
const NOW := 1786528800000
const DAY := "2026-08-08"
const MS_PER_DAY := 86400000

## Minimal-Pool fuer die Quest-Zaehler (Zaehler-Messung "feeds").
const POOL: Array = [
	{
		"id": "wq1",
		"kategorie": "pflege",
		"ziel": 2,
		"messung": {"typ": "counter", "key": "feeds"},
		"muenzen": 10,
		"xp": 5
	},
	{
		"id": "wq2",
		"kategorie": "spiel",
		"ziel": 3,
		"messung": {"typ": "spiele_gesamt"},
		"muenzen": 10,
		"xp": 5
	},
	{
		"id": "wq3",
		"kategorie": "garten",
		"ziel": 5,
		"messung": {"typ": "counter", "key": "harvests"},
		"muenzen": 10,
		"xp": 5
	},
]

var _text_calls: Array = []


func test_frischer_stand_baut_sinnvollen_snapshot() -> void:
	var state := _fresh_state()
	var snap := _build(state)
	assert_eq(int(snap["v"]), WidgetSnapshot.VERSION, "Schema-Version")
	assert_eq(str(snap["nickname"]), "Gooby", "Default-Spitzname")
	assert_eq(int(snap["coins"]), int(state["economy"]["coins"]), "Muenzen aus economy.coins")
	assert_eq(int(snap["stats"]["hunger"]), 80, "Default-Hunger 80")
	assert_eq(int(snap["stats"]["energy"]), 90, "Default-Energie 90")
	# Stimmung: 0.35*70 + 0.65*81.25 = 77.3 → happy.
	assert_eq(str(snap["mood"]["band"]), "happy", "Startstimmung happy")
	assert_eq(str(snap["mood"]["emoji"]), "😊", "Emoji zum Band")
	assert_false(bool(snap["sleep"]["sleeping"]), "wach")
	assert_eq(str(snap["vacation"]["phase"]), "none", "kein Urlaub")
	assert_eq(str(snap["countdown"]["kind"]), "dailyReady", "Tagesbonus noch nicht geholt")
	assert_true(
		str(snap["statusText"]).begins_with("widgets.status.gluecklich"), str(snap["statusText"])
	)


func test_frischer_stand_hat_keine_live_activity() -> void:
	assert_eq(_plan(_fresh_state()), {}, "kein Urlaub/Schlaf/Bonus → keine Activity")


func test_schlaf_liefert_countdown_status_und_la() -> void:
	var state := _fresh_state()
	state["gooby"]["sleep"] = {"sleeping": true, "startedAt": NOW - 60000, "wakeAt": NOW + 600000}
	var snap := _build(state)
	assert_true(bool(snap["sleep"]["sleeping"]), "schlaeft")
	assert_eq(str(snap["countdown"]["kind"]), "sleepWake", "Countdown = Aufwachen")
	assert_eq(int(snap["countdown"]["endsAtMs"]), NOW + 600000, "Countdown endet am wakeAt")
	assert_eq(str(snap["mood"]["emoji"]), WidgetSnapshot.EMOJI_SLEEP, "Schlaf-Emoji")
	assert_true(str(snap["statusText"]).begins_with("widgets.status.schlaeft"), "Schlaf-Status")
	var plan := _plan(state)
	assert_eq(str(plan["kind"]), "sleep", "LA-Fall: Langzeit-Aktion Schlaf")
	assert_eq(int(plan["endsAtMs"]), NOW + 600000, "LA endet am wakeAt")
	assert_eq(int(plan["startedAtMs"]), NOW - 60000, "LA-Start = Einschlaf-Zeit")


func test_urlaub_away_zaehlt_zur_rueckkehr() -> void:
	var state := _fresh_state()
	state["vacation"] = _away_slice()
	var snap := _build(state)
	assert_eq(str(snap["vacation"]["phase"]), "away", "Phase away")
	assert_eq(str(snap["vacation"]["destName"]), "travel.ziel.beach", "Zielname lokalisiert")
	assert_eq(str(snap["countdown"]["kind"]), "vacationReturn", "Countdown = Rueckkehr")
	assert_eq(int(snap["countdown"]["endsAtMs"]), NOW + 2 * MS_PER_DAY, "endet am returnAt")
	assert_eq(str(snap["mood"]["emoji"]), WidgetSnapshot.EMOJI_TRAVEL, "Reise-Emoji")
	var plan := _plan(state)
	assert_eq(str(plan["kind"]), "vacation", "LA-Fall: Reise-Countdown")
	assert_eq(int(plan["endsAtMs"]), NOW + 2 * MS_PER_DAY, "LA endet am returnAt")
	assert_true(str(plan["title"]).begins_with("widgets.la.urlaub_titel"), "Urlaubs-Titel")


func test_urlaub_abholbereit_zaehlt_zur_abholfrist() -> void:
	var state := _fresh_state()
	var v := _away_slice()
	v["phase"] = Vacation.PHASE_RETURN_READY
	v["returnAt"] = NOW - 1000
	v["pickupBy"] = NOW + MS_PER_DAY
	state["vacation"] = v
	var snap := _build(state)
	assert_eq(str(snap["countdown"]["kind"]), "vacationPickup", "Countdown = Abholung")
	assert_eq(int(snap["countdown"]["endsAtMs"]), NOW + MS_PER_DAY, "endet an pickupBy")
	assert_true(str(snap["statusText"]).begins_with("widgets.status.abholbereit"), "Status")
	var plan := _plan(state)
	assert_eq(str(plan["kind"]), "vacation", "gleiche LA-Art (Update statt Neustart)")
	assert_eq(int(plan["endsAtMs"]), NOW + MS_PER_DAY, "LA endet an pickupBy")
	assert_true(str(plan["title"]).begins_with("widgets.la.abholung_titel"), "Abhol-Titel")


func test_tagesbonus_serie_startet_la_nur_ab_schwelle() -> void:
	var state := _fresh_state()
	state["daily"] = {"lastClaimDay": DAY, "streak": WidgetSnapshot.DAILY_LA_MIN_STREAK}
	var plan := _plan(state)
	assert_eq(str(plan.get("kind", "")), "daily", "Serie >= Schwelle + heute geholt → LA")
	assert_eq(
		int(plan["endsAtMs"]), WidgetSnapshot.next_midnight_ms(NOW, 0), "endet um Mitternacht"
	)
	state["daily"] = {"lastClaimDay": DAY, "streak": WidgetSnapshot.DAILY_LA_MIN_STREAK - 1}
	assert_eq(_plan(state), {}, "kleine Serie → keine LA (kein Daueralarm)")
	state["daily"] = {"lastClaimDay": "", "streak": 9}
	assert_eq(_plan(state), {}, "heute nicht geholt → keine LA")


func test_tagesbonus_geholt_liefert_reset_countdown() -> void:
	var state := _fresh_state()
	state["daily"] = {"lastClaimDay": DAY, "streak": 1}
	var snap := _build(state)
	assert_eq(str(snap["countdown"]["kind"]), "dailyReset", "Countdown = naechster Bonus")
	assert_eq(
		int(snap["countdown"]["endsAtMs"]),
		WidgetSnapshot.next_midnight_ms(NOW, 0),
		"endet um Mitternacht"
	)
	assert_true(bool(snap["daily"]["claimedToday"]), "heute geholt")


func test_quest_zaehler_nur_fuer_heutiges_brett() -> void:
	var state := _fresh_state()
	state["achievements"]["counters"]["feeds"] = 2
	state["quests"] = {
		"completedTotal": 1,
		"day": DAY,
		"active":
		[
			{"id": "wq1", "claimed": false, "base": {"n": 0}},
			{"id": "wq2", "claimed": true, "base": {"n": 0}},
			{"id": "wq3", "claimed": false, "base": {"n": 0}},
		],
	}
	var snap := _build(state)
	assert_eq(int(snap["quests"]["claimed"]), 1, "eine geclaimt")
	assert_eq(int(snap["quests"]["claimable"]), 1, "feeds 2/2 → abholbereit")
	assert_eq(int(snap["quests"]["total"]), 3, "immer drei Karten")
	state["quests"]["day"] = "2026-08-07"
	var stale := _build(state)
	assert_eq(int(stale["quests"]["claimed"]), 0, "gestriges Brett zaehlt nicht")
	assert_eq(int(stale["quests"]["claimable"]), 0, "gestriges Brett zaehlt nicht")


func test_next_midnight_und_zeitformat() -> void:
	assert_eq(WidgetSnapshot.next_midnight_ms(0, 0), MS_PER_DAY, "UTC: naechste Mitternacht")
	assert_eq(WidgetSnapshot.next_midnight_ms(0, 120), 79200000, "UTC+2: 22:00 UTC")
	assert_eq(WidgetSnapshot.next_midnight_ms(NOW, 0) - NOW, 14 * 3600000, "10:00 → +14 h")
	assert_eq(WidgetSnapshot.format_time(0, 0), "00:00", "Epoch-Start UTC")
	assert_eq(WidgetSnapshot.format_time(0, 90), "01:30", "Bias 90 min")


func test_kaputter_state_crasht_nicht() -> void:
	var snap := WidgetSnapshot.build({}, NOW, DAY, 0, Callable(self, "_text"), [])
	assert_eq(str(snap["nickname"]), "Gooby", "Default-Name")
	assert_eq(int(snap["coins"]), 0, "keine Muenzen")
	assert_eq(str(snap["vacation"]["phase"]), "none", "kein Urlaub")
	assert_true(str(snap["statusText"]).begins_with("widgets.status.hunger"), "0er-Stats → Hunger")
	assert_eq(_plan({}), {}, "keine LA aus leerem State")


func test_niedrigster_stat_gewinnt_statuszeile() -> void:
	var state := _fresh_state()
	state["gooby"]["stats"] = {"hunger": 80.0, "energy": 10.0, "hygiene": 85.0, "fun": 70.0}
	var snap := _build(state)
	assert_true(str(snap["statusText"]).begins_with("widgets.status.muede"), "Energie-Warnung")


func test_status_args_enthalten_spitznamen() -> void:
	_text_calls.clear()
	var state := _fresh_state()
	state["meta"]["goobyNickname"] = "Flauschi"
	var snap := _build(state)
	assert_eq(str(snap["nickname"]), "Flauschi", "Spitzname aus meta")
	var status_args: Dictionary = {}
	for call: Array in _text_calls:
		if str(call[0]).begins_with("widgets.status."):
			status_args = call[1]
	assert_eq(str(status_args.get("gooby", "")), "Flauschi", "Statuszeile nennt den Namen")


func _fresh_state() -> Dictionary:
	return SaveSchema.default_state(NOW - 3 * MS_PER_DAY)


func _away_slice() -> Dictionary:
	var v := Vacation.default_slice()
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = "beach"
	v["bookedAt"] = NOW - MS_PER_DAY
	v["returnAt"] = NOW + 2 * MS_PER_DAY
	v["pickupBy"] = NOW + 3 * MS_PER_DAY
	return v


func _build(state: Dictionary) -> Dictionary:
	return WidgetSnapshot.build(state, NOW, DAY, 0, Callable(self, "_text"), POOL)


func _plan(state: Dictionary) -> Dictionary:
	return WidgetSnapshot.live_activity_plan(state, NOW, DAY, 0, Callable(self, "_text"))


## Deterministischer Text-Fake: liefert den Key, protokolliert die Args.
func _text(key: String, args: Dictionary) -> String:
	_text_calls.append([key, args])
	return key

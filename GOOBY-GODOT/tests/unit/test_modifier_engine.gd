extends TestCase
## FERTIG-1 (EVAL Rang 12) — Arcade-Modifier-System: Scheduler (Grace/
## Kadenz/Fenster), Freischaltung über den Spielerlevel, Consume/Refund
## (Anti-Farming), Glücksrolle, zentrale Wirkung im Award (Coins ×n gegen
## das 150-c-Tages-Ledger, Punkte ×n, XP ×n) und die Ticker-Verdrahtung.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const GoobyTicker := preload("res://scripts/state/gooby_ticker.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")

const NOW_MS := 1768478400000
const MIN := ModifierEngine.MS_PER_MIN
const META := {"id": "teaParty", "coin_table": {"divisor": 4, "min": 4, "max": 26}, "target": 40}
const GAME_IDS: Array[String] = ["teaParty", "carrotCatch", "gvz"]


func _fresh_state(level := 12) -> Dictionary:
	var state := SaveSchema.default_state(NOW_MS)
	state["progression"]["level"] = level
	state["modifiers"] = ModifierEngine.default_slice()
	return state


## ── Slice & Freischaltung ────────────────────────────────────────────────


func test_normalize_slice_repariert_junk() -> void:
	assert_eq(ModifierEngine.normalize_slice(null), ModifierEngine.default_slice(), "null → frisch")
	var junk := {"nextAt": -5, "seed": "kaputt", "current": {"type": "gibtsNicht"}}
	var fixed := ModifierEngine.normalize_slice(junk)
	assert_eq(int(fixed["nextAt"]), 0, "negatives nextAt geklemmt")
	assert_eq(int(fixed["seed"]), 0, "Junk-Seed → 0 (wird beim Tick neu abgeleitet)")
	assert_eq(fixed["current"], null, "unbekannter Typ verworfen")
	var ok := (
		ModifierEngine
		. normalize_slice(
			{
				"nextAt": 9,
				"seed": 7,
				"lastGameId": "gvz",
				"current":
				{
					"gameId": "teaParty",
					"type": "turbo",
					"startedAt": 1,
					"endsAt": 99,
					"playsLeft": 2
				},
			}
		)
	)
	assert_eq(str(_cur(ok).get("type")), "turbo", "gültiges Event überlebt")


func test_freischaltung_waechst_mit_dem_level() -> void:
	assert_eq(ModifierEngine.unlocked_types(1).size(), 0, "Level 1: noch nichts")
	assert_eq(ModifierEngine.unlocked_types(2), ["doppelGold"], "Level 2: Doppel-Gold")
	assert_eq(ModifierEngine.unlocked_types(6).size(), 3, "Level 6: drei Typen")
	assert_eq(ModifierEngine.unlocked_types(12).size(), 6, "Level 12: kompletter Pool")
	assert_eq(ModifierEngine.unlocked_types(Leveling.MAX_LEVEL).size(), 6, "Max-Level: alle")


func test_eligible_pairs_meidet_das_letzte_spiel() -> void:
	var pairs := ModifierEngine.eligible_pairs(12, "teaParty", GAME_IDS)
	assert_eq(pairs.size(), 2 * 6, "6 Typen × 2 verbleibende Spiele")
	for pair in pairs:
		assert_ne(str(pair["gameId"]), "teaParty", "No-Repeat-Pin greift")


## ── Scheduler (tick) ─────────────────────────────────────────────────────


func test_tick_plant_grace_und_startet_dann_deterministisch() -> void:
	var state := _fresh_state()
	var res := ModifierEngine.tick(state, NOW_MS, GAME_IDS)
	assert_eq(str(res["event"]), "scheduled", "erster Tick plant nur")
	state["modifiers"] = res["changes"]
	var m: Dictionary = state["modifiers"]
	assert_eq(int(m["nextAt"]), NOW_MS + ModifierEngine.GRACE_MIN * MIN, "Grace = 30 min")
	assert_true(int(m["seed"]) != 0, "Seed aus meta.createdAt abgeleitet")
	var start_ms: int = int(m["nextAt"])
	res = ModifierEngine.tick(state, start_ms, GAME_IDS)
	assert_eq(str(res["event"]), "started", "faelliges nextAt startet das Event")
	state["modifiers"] = res["changes"]
	var cur := _cur(state["modifiers"])
	assert_true(ModifierEngine.TYPES.has(str(cur.get("type"))), "Typ aus dem Pool")
	assert_true(GAME_IDS.has(str(cur.get("gameId"))), "Spiel aus den Kandidaten")
	var plays_expected: int = int(ModifierEngine.TYPES[str(cur["type"])]["plays"])
	assert_eq(int(cur["playsLeft"]), plays_expected, "Runden-Budget des Typs")
	assert_eq(int(cur["endsAt"]), start_ms + ModifierEngine.WINDOW_MIN * MIN, "45-min-Fenster")
	var next: int = int((state["modifiers"] as Dictionary)["nextAt"])
	assert_true(
		(
			next >= start_ms + ModifierEngine.CADENCE_MIN_LO * MIN
			and next <= start_ms + ModifierEngine.CADENCE_MIN_HI * MIN
		),
		"Kadenz 50–120 min (war: +%d min)" % [(next - start_ms) / MIN]
	)
	# Determinismus: identischer Ausgangszustand → identisches Event.
	var state2 := _fresh_state()
	state2["modifiers"] = ModifierEngine.tick(state2, NOW_MS, GAME_IDS)["changes"]
	var res2 := ModifierEngine.tick(state2, start_ms, GAME_IDS)
	assert_eq(_cur(res2["changes"]), cur, "gleicher Seed → gleiches (Spiel, Typ)-Paar")


func test_tick_ohne_freigeschaltete_typen_plant_nur_neu() -> void:
	var state := _fresh_state(1)
	state["modifiers"] = ModifierEngine.tick(state, NOW_MS, GAME_IDS)["changes"]
	var start_ms := int((state["modifiers"] as Dictionary)["nextAt"])
	var res := ModifierEngine.tick(state, start_ms, GAME_IDS)
	assert_eq(str(res["event"]), "rescheduled", "Level 1 hat keinen Pool → nur neu planen")
	assert_eq(_cur(res["changes"]), {}, "kein Event gestartet")


func test_tick_raeumt_abgelaufene_events_auf() -> void:
	var state := _fresh_state()
	ModifierEngine.force_event(state, {"gameId": "gvz", "type": "turbo"}, NOW_MS)
	var ende := NOW_MS + ModifierEngine.WINDOW_MIN * MIN
	# nextAt nach hinten schieben — sonst rollt derselbe Tick sofort das
	# nächste Event (gewolltes Verhalten, hier aber nicht unter Test).
	(state["modifiers"] as Dictionary)["nextAt"] = ende + 10 * MIN
	var res := ModifierEngine.tick(state, ende, GAME_IDS)
	assert_eq(str(res["event"]), "expired", "Fenster vorbei → expired")
	state["modifiers"] = res["changes"]
	assert_eq(_cur(state["modifiers"]), {}, "Event weg")
	assert_eq(str((state["modifiers"] as Dictionary)["lastGameId"]), "gvz", "No-Repeat-Pin bleibt")


## ── Consume / Refund (Anti-Farming) ──────────────────────────────────────


func test_consume_zaehlt_runter_und_leert_am_ende() -> void:
	var state := _fresh_state()
	ModifierEngine.force_event(state, {"gameId": "teaParty", "type": "doppelGold"}, NOW_MS)
	assert_eq(
		ModifierEngine.consume(state, "carrotCatch", NOW_MS).get("ok"),
		false,
		"anderes Spiel konsumiert nicht"
	)
	var r1 := ModifierEngine.consume(state, "teaParty", NOW_MS)
	assert_true(bool(r1["ok"]), "1. Runde konsumiert")
	assert_false(bool(r1["cleared"]), "Budget (2) noch nicht leer")
	assert_eq(int(_cur(state["modifiers"]).get("playsLeft")), 1, "1 Runde übrig")
	var r2 := ModifierEngine.consume(state, "teaParty", NOW_MS)
	assert_true(bool(r2["cleared"]), "2. Runde leert das Event")
	assert_eq(_cur(state["modifiers"]), {}, "Event weg")
	assert_eq(
		str((state["modifiers"] as Dictionary)["lastGameId"]), "teaParty", "Pin gegen Wiederholung"
	)


func test_refund_wirkt_genau_einmal_und_nur_im_fenster() -> void:
	var state := _fresh_state()
	ModifierEngine.force_event(state, {"gameId": "teaParty", "type": "turbo"}, NOW_MS)
	var snap: Dictionary = ModifierEngine.consume(state, "teaParty", NOW_MS)["modifier"]
	assert_true(bool(ModifierEngine.refund(state, snap, NOW_MS + MIN)["ok"]), "1. Refund ok")
	assert_eq(int(_cur(state["modifiers"]).get("playsLeft")), 3, "Runde zurückgegeben")
	var snap2: Dictionary = ModifierEngine.consume(state, "teaParty", NOW_MS)["modifier"]
	assert_true(bool(snap2.get("refundUsed")), "refundUsed klebt am Event")
	assert_false(
		bool(ModifierEngine.refund(state, snap2, NOW_MS + MIN)["ok"]),
		"2. Refund desselben Events verweigert"
	)
	var spaet := NOW_MS + ModifierEngine.WINDOW_MIN * MIN + 1
	var frisch := _fresh_state()
	ModifierEngine.force_event(frisch, {"gameId": "gvz", "type": "turbo"}, NOW_MS)
	var snap3: Dictionary = ModifierEngine.consume(frisch, "gvz", NOW_MS)["modifier"]
	assert_false(
		bool(ModifierEngine.refund(frisch, snap3, spaet)["ok"]), "nach Fensterende kein Refund"
	)


func test_refund_stellt_geleertes_event_wieder_her() -> void:
	var state := _fresh_state()
	ModifierEngine.force_event(state, {"gameId": "teaParty", "type": "doppelGold"}, NOW_MS)
	ModifierEngine.consume(state, "teaParty", NOW_MS)
	var snap: Dictionary = ModifierEngine.consume(state, "teaParty", NOW_MS)["modifier"]
	assert_eq(_cur(state["modifiers"]), {}, "Event ist geleert")
	assert_true(
		bool(ModifierEngine.refund(state, snap, NOW_MS + MIN)["ok"]),
		"Refund nach dem letzten Consume wirkt noch"
	)
	var cur := _cur(state["modifiers"])
	assert_eq(int(cur.get("playsLeft")), 1, "genau die eine Runde zurück")
	assert_true(bool(cur.get("refundUsed")), "und als erstattet markiert")


func test_glueckspilz_rolle_bleibt_in_den_grenzen() -> void:
	var state := _fresh_state()
	var seen_min := 999
	var seen_max := -1
	for _i in 40:
		var bonus := ModifierEngine.roll_glueckspilz(state)
		seen_min = mini(seen_min, bonus)
		seen_max = maxi(seen_max, bonus)
	assert_true(seen_min >= ModifierEngine.GLUECKSPILZ_MIN, "nie unter 10 (war %d)" % seen_min)
	assert_true(seen_max <= ModifierEngine.GLUECKSPILZ_MAX, "nie über 60 (war %d)" % seen_max)
	assert_true(seen_max > seen_min, "Seed wandert (verschiedene Würfe)")


## ── Zentrale Wirkung im Award ────────────────────────────────────────────


func test_award_doppelgold_bucht_ueberschuss_gegen_tagesledger() -> void:
	var state := _fresh_state()
	var plain := _fresh_state()
	var mod := {"type": "doppelGold", "coin_mult": 2.0}
	var b := MinigameAward.award(state, META, 60, "normal", "2026-01-15", [], mod)
	var p := MinigameAward.award(plain, META, 60, "normal", "2026-01-15")
	assert_eq(int(b["coins"]), int(p["coins"]), "reguläre Auszahlung bleibt gleich")
	assert_eq(int(b["modifierBonusCoins"]), int(b["coins"]), "Bonus = Überschuss (×2)")
	assert_eq(
		int(state["economy"]["coins"]),
		int(plain["economy"]["coins"]) + int(b["modifierBonusCoins"]),
		"Kontostand = normal + Bonus"
	)
	assert_eq(
		int(state["economy"]["dayCoins"]), int(b["modifierBonusCoins"]), "Ledger sieht den Bonus"
	)
	assert_false(bool(b["modifierCapped"]), "unter dem 150-c-Deckel")
	assert_eq(int(state["achievements"]["counters"]["modifierPlays"]), 1, "Sticker-Counter tickt")
	assert_true(
		(
			not (plain["achievements"]["counters"] as Dictionary).has("modifierPlays")
			or int(plain["achievements"]["counters"]["modifierPlays"]) == 0
		),
		"ohne Modifier kein Counter"
	)


func test_award_doppelgold_respektiert_den_150c_deckel() -> void:
	var state := _fresh_state()
	state["economy"]["dayCoins"] = 149
	state["economy"]["dayCoinsDay"] = "2026-01-15"
	var mod := {"type": "doppelGold", "coin_mult": 2.0}
	var b := MinigameAward.award(state, META, 60, "normal", "2026-01-15", [], mod)
	assert_eq(int(b["modifierBonusCoins"]), 1, "nur noch 1 c Headroom")
	assert_true(bool(b["modifierCapped"]), "Deckel-Hinweis für den Results-Screen")


func test_award_turbo_boostet_den_score_vor_allem() -> void:
	var state := _fresh_state()
	var mod := {"type": "turbo", "score_mult": 1.5}
	var b := MinigameAward.award(state, META, 40, "normal", "2026-01-15", [], mod)
	assert_eq(int(b["score"]), 60, "40 × 1,5 = 60 (Punkte am Ende)")
	assert_eq(int(b["best"]), 60, "Bestwert sieht den geboosteten Score")
	assert_true(bool(b["beatTarget"]), "Ziel (40) mit Boost geschlagen")


func test_award_lernrausch_verdoppelt_nur_die_xp() -> void:
	var state := _fresh_state()
	var plain := _fresh_state()
	var mod := {"type": "lernrausch", "xp_mult": 2.0}
	var b := MinigameAward.award(state, META, 60, "normal", "2026-01-15", [], mod)
	var p := MinigameAward.award(plain, META, 60, "normal", "2026-01-15")
	assert_eq(int(b["xp"]), 2 * int(p["xp"]), "XP ×2")
	assert_eq(int(b["coins"]), int(p["coins"]), "Coins bleiben unangetastet")


func test_award_glueckspilz_bucht_die_rolle() -> void:
	var state := _fresh_state()
	var plain := _fresh_state()
	var mod := {"type": "glueckspilz", "gluecksrolle": true}
	var b := MinigameAward.award(state, META, 60, "normal", "2026-01-15", [], mod)
	var p := MinigameAward.award(plain, META, 60, "normal", "2026-01-15")
	var glueck := int(b["gluecksrolleCoins"])
	assert_true(
		glueck >= ModifierEngine.GLUECKSPILZ_MIN and glueck <= ModifierEngine.GLUECKSPILZ_MAX,
		"Rolle in 10..60 (war %d)" % glueck
	)
	assert_eq(int(b["coins"]), int(p["coins"]), "reguläre Auszahlung bleibt gleich")
	assert_eq(
		int(state["economy"]["coins"]),
		int(plain["economy"]["coins"]) + glueck,
		"Rolle landet auf dem Konto"
	)
	assert_eq(int(state["economy"]["dayCoins"]), glueck, "gegen das Modifier-Tages-Ledger")


## ── Ticker-Verdrahtung ───────────────────────────────────────────────────


func test_live_tick_startet_faellige_events_und_meldet_sie() -> void:
	var state := _fresh_state()
	state["modifiers"] = ModifierEngine.tick(state, NOW_MS, GAME_IDS)["changes"]
	var start_ms := int((state["modifiers"] as Dictionary)["nextAt"])
	state["gooby"]["lastTickAt"] = start_ms - 5000
	var events := GoobyTicker.live_tick(state, start_ms)
	var cur := _cur(state["modifiers"])
	assert_true(not cur.is_empty(), "Live-Tick startet das fällige Event")
	var expected := "modifierStarted:%s:%s" % [cur.get("gameId"), cur.get("type")]
	assert_true(events.has(expected), "Eventstring für den Toast (war: %s)" % [events])


func test_catch_up_holt_verpasste_events_nach() -> void:
	var state := _fresh_state()
	state["modifiers"] = ModifierEngine.tick(state, NOW_MS, GAME_IDS)["changes"]
	var spaeter := int((state["modifiers"] as Dictionary)["nextAt"]) + 10 * MIN
	state["gooby"]["lastTickAt"] = NOW_MS
	var events := GoobyTicker.catch_up(state, spaeter)
	assert_true(not _cur(state["modifiers"]).is_empty(), "Offline-Nachholung startet das Event")
	var found := false
	for ev: Variant in events:
		if str(ev).begins_with("modifierStarted:"):
			found = true
	assert_true(found, "Start wird auch offline gemeldet (war: %s)" % [events])


static func _cur(m: Variant) -> Dictionary:
	if m is Dictionary and (m as Dictionary).get("current") is Dictionary:
		return (m as Dictionary)["current"]
	return {}

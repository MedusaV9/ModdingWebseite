extends TestCase
## SEELE-2: Beziehung mit Gedächtnis. Kernversprechen: Vorlieben und kleine
## Wünsche entstehen NUR aus echten Save-Daten (nie erfunden), die
## Beziehungs-Stufe färbt die Text-Auswahl, und ein erfüllter Wunsch wird
## genau einmal gefeiert (decide → book → decide gatet).

const MS_D := 86_400_000
const T0 := 1_785_132_000_000


func test_beziehung_stufe() -> void:
	assert_eq(SoulTriggers.beziehung_stufe(0), "neu")
	assert_eq(SoulTriggers.beziehung_stufe(6), "neu")
	assert_eq(SoulTriggers.beziehung_stufe(7), "vertraut")
	assert_eq(SoulTriggers.beziehung_stufe(49), "vertraut")
	assert_eq(SoulTriggers.beziehung_stufe(50), "beste_freunde")


func test_vorlieben_nur_mit_echten_daten() -> void:
	var ohne := _vorlieben_ids({})
	assert_false(ohne.has("vorliebe_spiel"), "kein Lieblingsspiel ohne Daten")
	assert_false(ohne.has("vorliebe_essen"), "kein Lieblingsessen ohne Daten")
	# EIN gespieltes Spiel reicht nicht (MIN_VORLIEBE_SPIELE=2) …
	var eins := _vorlieben_ids({"minigames": {"legacy": {"best": {"memory": 900}}}})
	assert_false(eins.has("vorliebe_spiel"), "1 Spiel ist keine Vorliebe")
	# … zwei Spiele schon; das mit dem besten Score gewinnt.
	var zwei := _vorlieben({"minigames": {"legacy": {"best": {"memory": 900, "fangen": 1200}}}})
	assert_true(_ids(zwei).has("vorliebe_spiel"), "2 Spiele → Lieblingsspiel")
	for kandidat in zwei:
		if str(kandidat["id"]) == "vorliebe_spiel":
			assert_true(
				str(kandidat["args"]["spiel"]).length() > 0, "Spielname aufgelöst (nie leer)"
			)
	# Essen: erst ab 3 Fütterungen desselben Essens.
	var wenig := _vorlieben_ids({"soul": {"foodGiven": {"carrot": 2}}})
	assert_false(wenig.has("vorliebe_essen"), "2 Fütterungen sind keine Vorliebe")
	var genug := _vorlieben({"soul": {"foodGiven": {"carrot": 4, "apple": 1}}})
	assert_true(_ids(genug).has("vorliebe_essen"), "4x carrot → Lieblingsessen")


func test_wunsch_offen_und_erfuellt_aus_echten_daten() -> void:
	assert_true(SoulMemories.wunsch_offen({}, "funkelpark"), "nie im Park → Wunsch offen")
	assert_false(
		SoulMemories.wunsch_offen({"park": {"visits": 2}}, "funkelpark"), "Besuch → erfüllt"
	)
	assert_true(SoulMemories.wunsch_erfuellt({"park": {"visits": 2}}, "funkelpark"))
	assert_true(SoulMemories.wunsch_offen({"daily": {"streak": 4}}, "streak7"))
	assert_false(SoulMemories.wunsch_offen({"daily": {"streak": 7}}, "streak7"))
	assert_true(SoulMemories.wunsch_offen({}, "urlaub"))
	assert_false(SoulMemories.wunsch_offen({"vacation": {"visited": {"strand": 1}}}, "urlaub"))
	assert_true(SoulMemories.wunsch_offen({}, "kissenturm"))
	assert_false(
		SoulMemories.wunsch_offen({"soul": {"surpriseAt": {"sup_turm": T0}}}, "kissenturm")
	)
	assert_false(SoulMemories.wunsch_erfuellt({}, "gibtsnicht"), "unbekannte Id nie erfüllt")


func test_offene_wuensche_ohne_gefeierte() -> void:
	var alle := SoulMemories.offene_wuensche({}, SoulState.default_slice())
	assert_eq(alle.size(), SoulMemories.WUNSCH_IDS.size(), "frischer Save: alles offen")
	var slice := SoulState.default_slice()
	slice["wunschErfuellt"] = {"funkelpark": T0}
	var rest := SoulMemories.offene_wuensche({}, slice)
	assert_false(rest.has("funkelpark"), "gefeierte Wünsche kommen nie wieder")
	var state := {"park": {"visits": 1}, "daily": {"streak": 9}}
	var uebrig := SoulMemories.offene_wuensche(state, SoulState.default_slice())
	assert_false(uebrig.has("funkelpark"), "schon erfüllt = nicht mehr wünschbar")
	assert_false(uebrig.has("streak7"))
	assert_true(uebrig.has("urlaub"))


func test_wunsch_zyklus_decide_book_decide() -> void:
	var defs := [
		{"id": "wunsch", "kind": "wunsch", "text_keys": []},
		{"id": "wunsch_erfuellt", "kind": "wunsch_erfuellt", "text_keys": []},
		{"id": "erinnerung", "kind": "erinnerung", "text_keys": []},
	]
	var slice := SoulState.default_slice()
	slice["firstMetAt"] = T0 - 10 * MS_D
	slice["lastGreetDay"] = "2026-07-27"  # Gruß heute schon gelaufen
	# Jeder Schritt ist ein eigenes Raumbetreten Stunden später — die
	# Frequenzbremse (90 s Mindestabstand) gilt auch für Wunsch-Momente.
	var ctx := _ctx(9)
	# 1) Neuer Wunsch über den Erinnerungs-Slot (roll klein genug).
	var moment := SoulService.decide_enter({}, slice, defs, ctx, 0.01)
	assert_eq(str(moment.get("kind", "")), "wunsch", "kleiner Roll → neuer Wunsch")
	var wunsch_id := str(moment.get("wunsch_id", ""))
	assert_true(SoulMemories.WUNSCH_IDS.has(wunsch_id), "Wunsch-Id aus dem Katalog")
	SoulService.book_enter(slice, moment, ctx)
	assert_eq(str(slice["wunsch"].get("id", "")), wunsch_id, "Wunsch gemerkt")
	# 2) Solange offen: kein zweiter Wunsch, keine Feier.
	var nochmal := SoulService.decide_enter({}, slice, defs, _ctx(11), 0.01)
	assert_ne(str(nochmal.get("kind", "")), "wunsch", "kein Wunsch-Stapeln")
	# 3) Ziel tritt WIRKLICH ein (echte Daten) → sichere Feier, vor Erinnerungen.
	var state := {
		"park": {"visits": 3},
		"daily": {"streak": 9},
		"vacation": {"visited": {"strand": 1}},
		"soul": {"surpriseAt": {"sup_turm": T0}},
	}
	var feier := SoulService.decide_enter(state, slice, defs, _ctx(14), 0.99)
	assert_eq(str(feier.get("kind", "")), "wunsch_erfuellt", "Erfüllung kommt SICHER (roll egal)")
	assert_eq(str(feier.get("wunsch_id", "")), wunsch_id)
	assert_eq(str(feier.get("text_key", "")), "soul.wunsch.%s_erfuellt" % wunsch_id)
	SoulService.book_enter(slice, feier, _ctx(14))
	assert_true(slice["wunschErfuellt"].has(wunsch_id), "Feier gebucht")
	assert_true((slice["wunsch"] as Dictionary).is_empty(), "Wunsch abgeräumt")
	# 4) Nie doppelt feiern.
	var danach := SoulService.decide_enter(state, slice, defs, _ctx(17), 0.99)
	assert_ne(str(danach.get("kind", "")), "wunsch_erfuellt", "keine Doppel-Feier")


func test_text_pool_stufen_varianten() -> void:
	var def := {
		"id": "gruss_morgen",
		"text_keys": ["k.a", "k.b"],
		"text_keys_stufe": {"beste_freunde": ["k.beste"]},
	}
	assert_eq(SoulService.text_pool(def).size(), 2, "ohne Stufe nur Basis")
	assert_eq(SoulService.text_pool(def, "neu").size(), 2, "unbekannte Stufe → Basis")
	var beste := SoulService.text_pool(def, "beste_freunde")
	assert_eq(beste.size(), 3, "Stufe erweitert den Pool")
	assert_true(beste.has("k.beste"))


func test_gruss_nutzt_beziehungs_stufe() -> void:
	var defs := [
		{
			"id": "gruss_morgen",
			"kind": "gruss",
			"text_keys": [],
			"text_keys_stufe": {"beste_freunde": ["k.beste"]},
		},
	]
	var slice := SoulState.default_slice()
	slice["firstMetAt"] = T0 - 60 * MS_D  # 60 Tage → beste_freunde
	var moment := SoulService.decide_enter({}, slice, defs, _ctx(8), 0.5)
	assert_eq(str(moment.get("text_key", "")), "k.beste", "60 Tage → Stufen-Text")


## T0 = 06:00 — hour verschiebt now_ms mit (Frequenzbremse braucht Abstand).
func _ctx(hour := 12) -> Dictionary:
	return {
		"now_ms": T0 + (hour - 6) * 3_600_000,
		"date": {"year": 2026, "month": 7, "day": 27, "hour": hour},
		"hour": hour,
		"gap_ms": 0,
		"wetter": {"typ": "sonne", "regen": false, "schnee": false},
		"player_name": "Mira",
		"nickname": "Gooby",
	}


func _vorlieben(state: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kandidat in SoulMemories.candidates(state):
		if str(kandidat["id"]).begins_with("vorliebe_"):
			out.append(kandidat)
	return out


func _vorlieben_ids(state: Dictionary) -> Array[String]:
	return _ids(_vorlieben(state))


func _ids(kandidaten: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for kandidat in kandidaten:
		out.append(str(kandidat["id"]))
	return out

extends TestCase
## G8 IDEA-WOCHE — WochenVorhaben: ISO-Wochen-Mathe (injizierter Lokaltag,
## keine OS-Uhr), deterministisches Wochen-Angebot (Golden nach
## roll_today-Muster), sequenzielle Schritt-Trigger über Baseline-Deltas,
## Feiern-Idempotenz (kein Doppel-Payout), Bogen-Wechsel am Wochenanfang
## und Katalog-/String-Validierung (DE+EN paritätisch).

const WOCHE_A := "2026-W31"
const WOCHE_B := "2026-W32"
const WOCHE_C := "2026-W33"
## Zähler, die im Spiel BEWIESEN gebumpt werden (Tagesquest-Pool nutzt
## exakt dieselben) — Katalog-Wache gegen tote Trigger.
const BEKANNTE_COUNTER := [
	"feeds", "washes", "tickles", "teeth_brushed", "plantings", "waterings", "harvests"
]
const BEKANNTE_TYPEN := [
	"counter",
	"spiele_gesamt",
	"spiele_verschieden",
	"spiel_runden",
	"spiel_punkte",
	"muenzen_verdient",
	"muenzen_ausgegeben",
]


func _state() -> Dictionary:
	return {
		"achievements":
		{
			"counters":
			{
				"feeds": 0,
				"washes": 0,
				"tickles": 0,
				"teeth_brushed": 0,
				"plantings": 0,
				"waterings": 0,
				"harvests": 0,
			}
		},
		"minigames": {"plays": {}, "legacy": {"best": {}, "bestByDiff": {}, "endlessBest": {}}},
		"economy": {"coins": 100, "coinsEarned": 0, "coinsSpent": 0},
		"progression": {"level": 1, "xp": 0},
		"quests": {"completedTotal": 0},
	}


func _ctx() -> Dictionary:
	return {"level": 1, "minigames": [], "garden": true}


## Mini-Katalog für die Logik-Tests: feeds taucht in s0 UND s2 auf — die
## Baseline des dritten Schritts muss beim WECHSEL frisch einfrieren.
func _pool_simple() -> Array:
	return [
		{
			"id": "bogen_a",
			"schritte":
			[
				{"messung": {"typ": "counter", "key": "feeds"}, "ziel": 2},
				{"messung": {"typ": "counter", "key": "washes"}, "ziel": 1},
				{"messung": {"typ": "counter", "key": "feeds"}, "ziel": 1},
			],
			"muenzen": 40,
			"xp": 20,
		},
		{
			"id": "bogen_b",
			"schritte":
			[
				{"messung": {"typ": "counter", "key": "tickles"}, "ziel": 1},
				{"messung": {"typ": "counter", "key": "waterings"}, "ziel": 2},
				{"messung": {"typ": "counter", "key": "harvests"}, "ziel": 1},
			],
			"muenzen": 35,
			"xp": 15,
		},
	]


func test_wochen_string_iso8601() -> void:
	assert_eq(WochenVorhaben.woche_von("2026-08-02"), "2026-W31", "Sonntag gehört zu W31")
	assert_eq(WochenVorhaben.woche_von("2026-08-03"), "2026-W32", "Montag startet W32")
	assert_eq(WochenVorhaben.woche_von("2026-07-27"), "2026-W31", "Montag W31")
	assert_eq(WochenVorhaben.woche_von("2026-01-01"), "2026-W01", "Jahresstart")
	assert_eq(WochenVorhaben.woche_von("2025-12-29"), "2026-W01", "Jahreswechsel vorwärts (Mo)")
	assert_eq(WochenVorhaben.woche_von("2027-01-01"), "2026-W53", "Jahreswechsel rückwärts (Fr)")
	assert_eq(WochenVorhaben.woche_von("2026-12-31"), "2026-W53", "W53-Jahr")
	assert_eq(WochenVorhaben.woche_von("kaputt"), "", "kaputter Tag → leer")


## Gleiche Woche == gleicher Bogen (alle Spieler mit gleicher Historie);
## Golden-Werte gegen den echten eingebauten Katalog eingefroren.
func test_angebot_deterministisch_mit_golden_werten() -> void:
	var pool := WochenVorhabenKatalog.builtin_pool()
	assert_true(pool.size() >= 6, "Startkatalog hat mindestens 6 Bögen")
	var quests_a := {"completedTotal": 0}
	var quests_b := {"completedTotal": 0}
	assert_true(
		WochenVorhaben.ensure_aktiv(quests_a, WOCHE_A, pool, _ctx(), _state()), "Roll startet"
	)
	assert_true(WochenVorhaben.ensure_aktiv(quests_b, WOCHE_A, pool, _ctx(), _state()))
	var v_a: Dictionary = quests_a["vorhaben"]
	var v_b: Dictionary = quests_b["vorhaben"]
	assert_eq(str(v_a["id"]), str(v_b["id"]), "gleiche Woche == gleicher Bogen")
	assert_eq(str(v_a["id"]), "arcadetour", "Golden: Angebot W31")
	assert_eq(str(v_a["woche"]), WOCHE_A, "Roll-Woche steht im Slice")
	assert_eq(int(v_a["schritt"]), 0, "Bogen startet bei Schritt 0")
	assert_false(
		WochenVorhaben.ensure_aktiv(quests_a, WOCHE_A, pool, _ctx(), _state()),
		"No-op solange ein Bogen läuft"
	)
	var quests_c := {"completedTotal": 0}
	WochenVorhaben.ensure_aktiv(quests_c, WOCHE_B, pool, _ctx(), _state())
	assert_eq(str((quests_c["vorhaben"] as Dictionary)["id"]), "wellness", "Golden: Angebot W32")
	var quests_d := {"completedTotal": 0}
	WochenVorhaben.ensure_aktiv(quests_d, WOCHE_C, pool, _ctx(), _state())
	assert_eq(str((quests_d["vorhaben"] as Dictionary)["id"]), "funkelputz", "Golden: Angebot W33")


## Schritte zählen NUR über Baseline-Deltas der bestehenden Zähler und
## laufen strikt sequenziell — alte Überschüsse zählen nie für spätere
## Schritte (Re-Freeze beim Schrittwechsel).
func test_schritt_trigger_via_baseline_deltas() -> void:
	var state := _state()
	state["achievements"]["counters"]["feeds"] = 5
	var quests := {"completedTotal": 0}
	var def: Dictionary = _pool_simple()[0]
	assert_true(WochenVorhaben.starte_bogen(quests, def, WOCHE_A, state))
	var v: Dictionary = quests["vorhaben"]
	assert_eq(WochenVorhaben.schritt_fortschritt(v, def, state), 0, "Baseline eingefroren")
	state["achievements"]["counters"]["feeds"] = 6
	assert_eq(WochenVorhaben.fortschreiben(quests, def, state), 0, "1/2 reicht nicht")
	assert_eq(WochenVorhaben.schritt_fortschritt(v, def, state), 1, "Delta seit Start")
	# Überschuss (3 statt 2 Feeds) — s0 fertig, s2 darf davon NICHTS erben.
	state["achievements"]["counters"]["feeds"] = 8
	assert_eq(WochenVorhaben.fortschreiben(quests, def, state), 1, "Schritt 1 geschafft")
	assert_eq(int(v["schritt"]), 1, "Sequenz steht auf Schritt 2")
	state["achievements"]["counters"]["washes"] = 1
	assert_eq(WochenVorhaben.fortschreiben(quests, def, state), 1, "Schritt 2 geschafft")
	assert_eq(int(v["schritt"]), 2)
	assert_eq(
		WochenVorhaben.schritt_fortschritt(v, def, state),
		0,
		"feeds-Baseline wurde beim Wechsel FRISCH eingefroren (kein Alt-Überschuss)"
	)
	assert_false(WochenVorhaben.erfuellbar(v, def), "noch nicht erfüllbar")
	state["achievements"]["counters"]["feeds"] = 9
	assert_eq(WochenVorhaben.fortschreiben(quests, def, state), 1, "Finale-Schritt geschafft")
	assert_true(WochenVorhaben.erfuellbar(v, def), "alle Schritte durch → erfüllbar")


## Feiern zahlt genau EINMAL (Engine leert den aktiv-Slot) und erst, wenn
## wirklich alle Schritte durch sind.
func test_feiern_idempotent_kein_doppel_payout() -> void:
	var state := _state()
	var quests := {"completedTotal": 0}
	var def: Dictionary = _pool_simple()[0]
	WochenVorhaben.starte_bogen(quests, def, WOCHE_A, state)
	assert_false(bool(WochenVorhaben.feiern(quests, def, WOCHE_A)["ok"]), "unfertig != feierbar")
	# Sequenziell wie im Spiel: erst nach JEDEM Schrittwechsel weiterspielen
	# (die Baseline des Folgeschritts friert beim Wechsel ein — Buchungen
	# davor zählen bewusst nicht, s. test_schritt_trigger_via_baseline_deltas).
	state["achievements"]["counters"]["feeds"] = 2
	assert_eq(WochenVorhaben.fortschreiben(quests, def, state), 1, "Schritt 1 durch")
	state["achievements"]["counters"]["washes"] = 1
	assert_eq(WochenVorhaben.fortschreiben(quests, def, state), 1, "Schritt 2 durch")
	state["achievements"]["counters"]["feeds"] = 3
	assert_eq(WochenVorhaben.fortschreiben(quests, def, state), 1, "Finale-Schritt durch")
	var res := WochenVorhaben.feiern(quests, def, WOCHE_A)
	assert_true(bool(res["ok"]), "fertig → feierbar")
	assert_eq(int(res["muenzen"]), 40, "Münzen aus dem Def")
	assert_eq(int(res["xp"]), 20, "XP aus dem Def")
	var v: Dictionary = quests["vorhaben"]
	assert_eq(str(v["id"]), "", "aktiv-Slot geleert")
	assert_eq(str(v["letzteId"]), "bogen_a", "Historie gemerkt")
	assert_eq(str(v["fertigWoche"]), WOCHE_A, "Feier-Woche gebucht")
	assert_true((v["fertigIds"] as Array).has("bogen_a"))
	var zweite := WochenVorhaben.feiern(quests, def, WOCHE_A)
	assert_false(bool(zweite["ok"]), "KEIN Doppel-Payout")
	assert_eq(int(zweite["muenzen"]), 0)
	assert_true(WochenVorhaben.fertig_diese_woche(v, WOCHE_A), "Feier-Zustand der Woche")


## Kein Deadline-Druck: ein unfertiger Bogen überlebt den Wochenwechsel;
## nach dem Feiern kommt der nächste Bogen erst am nächsten Wochenanfang
## und wiederholt nie direkt den letzten.
func test_bogen_wechsel_am_wochenanfang() -> void:
	var state := _state()
	var pool := _pool_simple()
	var quests := {"completedTotal": 0}
	assert_true(WochenVorhaben.ensure_aktiv(quests, WOCHE_A, pool, _ctx(), state))
	var v: Dictionary = quests["vorhaben"]
	var erste_id := str(v["id"])
	assert_false(
		WochenVorhaben.ensure_aktiv(quests, WOCHE_B, pool, _ctx(), state),
		"unfertiger Bogen läuft über den Wochenwechsel einfach weiter"
	)
	assert_eq(str(v["id"]), erste_id, "kein Verfall, kein Austausch")
	# Fertig spielen + in Woche B feiern.
	var def: Dictionary = pool[0] if erste_id == "bogen_a" else pool[1]
	for schritt: Dictionary in WochenVorhaben.schritte_von(def):
		var messung: Dictionary = schritt["messung"]
		var key := str(messung["key"])
		var counters: Dictionary = state["achievements"]["counters"]
		counters[key] = int(counters.get(key, 0)) + int(schritt["ziel"])
		WochenVorhaben.fortschreiben(quests, def, state)
	assert_true(bool(WochenVorhaben.feiern(quests, def, WOCHE_B)["ok"]))
	assert_false(
		WochenVorhaben.ensure_aktiv(quests, WOCHE_B, pool, _ctx(), state),
		"diese Woche schon gefeiert → Rest der Woche ist Feier-Zustand"
	)
	assert_true(
		WochenVorhaben.ensure_aktiv(quests, WOCHE_C, pool, _ctx(), state),
		"neuer Wochenanfang → neuer Bogen"
	)
	assert_ne(str(v["id"]), erste_id, "der letzte Bogen wiederholt sich nicht direkt")
	assert_eq(int(v["schritt"]), 0, "frischer Bogen startet bei Schritt 0")


## Katalog-Wache: 6+ Bögen, je 3–5 Schritte, nur bewiesene Messungen/Zähler,
## Belohnung im Ökonomie-Korridor, Strings DE+EN paritätisch vorhanden.
func test_katalog_validierung_und_string_paritaet() -> void:
	var pool := WochenVorhabenKatalog.builtin_pool()
	assert_true(pool.size() >= 6, "Startkatalog: mindestens 6 Bögen (ist %d)" % pool.size())
	var de: Dictionary = I18nService.table("de")
	var en: Dictionary = I18nService.table("en")
	var seen := {}
	for def: Variant in pool:
		assert_true(WochenVorhaben.def_gueltig(def), "Def ist gültig (3–5 Schritte)")
		var id := str((def as Dictionary).get("id", ""))
		assert_false(seen.has(id), "id '%s' ist eindeutig" % id)
		seen[id] = true
		var muenzen := int((def as Dictionary).get("muenzen", 0))
		var xp := int((def as Dictionary).get("xp", 0))
		assert_true(
			muenzen >= 20 and muenzen <= 80,
			"%s: Finale-Münzen im Korridor (kein Münz-Regen): %d" % [id, muenzen]
		)
		assert_true(xp >= 10 and xp <= 40, "%s: XP im Korridor: %d" % [id, xp])
		var schritte := WochenVorhaben.schritte_von(def)
		for i in schritte.size():
			var messung: Dictionary = (schritte[i] as Dictionary).get("messung", {})
			var typ := str(messung.get("typ", ""))
			assert_true(BEKANNTE_TYPEN.has(typ), "%s s%d: Messungstyp '%s'" % [id, i, typ])
			if typ == "counter":
				assert_true(
					BEKANNTE_COUNTER.has(str(messung.get("key", ""))),
					"%s s%d: Zähler '%s' wird im Spiel gebumpt" % [id, i, messung.get("key")]
				)
			for tabelle: Dictionary in [de, en]:
				var sprache := "DE" if tabelle == de else "EN"
				var text_key := WochenVorhabenKatalog.schritt_text_key(def, i)
				var zw_key := WochenVorhabenKatalog.schritt_zwischen_key(def, i)
				assert_true(tabelle.has(text_key), "%s: %s fehlt (%s)" % [id, text_key, sprache])
				assert_true(tabelle.has(zw_key), "%s: %s fehlt (%s)" % [id, zw_key, sprache])
		for tabelle: Dictionary in [de, en]:
			var sprache := "DE" if tabelle == de else "EN"
			var titel_key := WochenVorhabenKatalog.title_key(def)
			var finale_key := WochenVorhabenKatalog.finale_key(def)
			assert_true(tabelle.has(titel_key), "%s: Titel fehlt (%s)" % [id, sprache])
			assert_true(tabelle.has(finale_key), "%s: Finale fehlt (%s)" % [id, sprache])
	for key: String in [
		"vorhaben.titel",
		"vorhaben.laeuft_weiter",
		"vorhaben.feiern",
		"vorhaben.geschafft",
		"vorhaben.naechste_woche",
		"vorhaben.claim_toast",
		"vorhaben.belohnung",
		"vorhaben.fortschritt",
	]:
		assert_true(de.has(key) and en.has(key), "Grundgerüst-Key %s DE+EN" % key)


## Angebots-Rotation: schon erlebte Bögen werden übersprungen, solange es
## unerlebte gibt; sind alle durch, sind Wiederholungen erlaubt (nur nie
## der direkt letzte).
func test_angebot_rotation_ueber_die_historie() -> void:
	var pool := _pool_simple()
	var fertig: Array = ["bogen_a"]
	var def := WochenVorhaben.angebot_fuer(WOCHE_A, pool, _ctx(), fertig, "bogen_a")
	assert_eq(str(def.get("id", "")), "bogen_b", "erlebter Bogen wird übersprungen")
	var alle: Array = ["bogen_a", "bogen_b"]
	var wieder := WochenVorhaben.angebot_fuer(WOCHE_A, pool, _ctx(), alle, "bogen_b")
	assert_eq(str(wieder.get("id", "")), "bogen_a", "alles erlebt → Wiederholung, nie der letzte")

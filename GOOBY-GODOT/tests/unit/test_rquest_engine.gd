extends TestCase
## RW-3 — Quest-Zustandsmaschine (RQuestEngine): Status-Ableitung,
## Voraussetzungen (Quests/Herzen/Kapitel), ALLE 7 Ziel-Typen sequenziell,
## Warte-Quests über Zeitsprünge (tick), Tagesaufgaben-Reset und Abgabe.

const MIN := RQuestEngine.MS_PRO_MIN

## Fixture-Quest mit allen 7 Ziel-Typen in Reihe.
const ALLES_DEF := {
	"id": "fx_alles",
	"typ": "neben",
	"geber": "rosi",
	"ziele":
	[
		{"typ": "gehe_zu", "ort": "stall"},
		{"typ": "sprich_mit", "npc": "rosi"},
		{"typ": "sammle", "item": "apfel", "n": 2},
		{"typ": "pflege", "aktion": "striegeln", "n": 1},
		{"typ": "reite_strecke", "strecke": "hof_runde"},
		{"typ": "warte_bis", "dauerMin": 30},
		{"typ": "gewinne_wettbewerb", "disziplin": "parcours", "platz": 2},
	],
	"belohnung": {"muenzen": 10, "freischalten": ["fx_deko"]},
}


func test_status_ableitung() -> void:
	var def := {
		"id": "fx", "typ": "neben", "geber": "rosi", "ziele": [{"typ": "gehe_zu", "ort": "stall"}]
	}
	var quests := RQuestSlices.default_quests()
	assert_eq(RQuestEngine.status_von(quests, def), RQuestEngine.STATUS_VERFUEGBAR)
	quests = RQuestEngine.annehmen(quests, def, 1000)
	assert_eq(RQuestEngine.status_von(quests, def), RQuestEngine.STATUS_AKTIV)
	quests["erledigt"] = ["fx"]
	quests["aktiv"] = {}
	assert_eq(RQuestEngine.status_von(quests, def), RQuestEngine.STATUS_ERLEDIGT)


func test_voraussetzungen() -> void:
	var quests := RQuestSlices.default_quests()
	var def := {
		"id": "fx_gate",
		"typ": "neben",
		"geber": "rosi",
		"voraussetzungen": {"quests": ["fx_vorher"], "herzen": {"rosi": 2}},
		"ziele": [{"typ": "gehe_zu", "ort": "stall"}],
	}
	assert_eq(RQuestEngine.status_von(quests, def, {"rosi": 5}), RQuestEngine.STATUS_GESPERRT)
	quests["erledigt"] = ["fx_vorher"]
	assert_eq(
		RQuestEngine.status_von(quests, def, {"rosi": 1}),
		RQuestEngine.STATUS_GESPERRT,
		"Herz-Gate haelt"
	)
	assert_eq(RQuestEngine.status_von(quests, def, {"rosi": 2}), RQuestEngine.STATUS_VERFUEGBAR)


func test_kapitel_gate_und_zaehlung() -> void:
	var reihe := [
		{"id": "h1", "typ": "haupt", "kapitel": 1},
		{"id": "h2", "typ": "haupt", "kapitel": 2},
	]
	var quests := RQuestSlices.default_quests()
	assert_eq(RQuestEngine.kapitel(quests, reihe), 1)
	quests["erledigt"] = ["h1"]
	assert_eq(RQuestEngine.kapitel(quests, reihe), 2)
	quests["erledigt"] = ["h1", "h2"]
	assert_eq(RQuestEngine.kapitel(quests, reihe), 3, "Reihe durch = letztes Kapitel + 1")


func test_alle_ziel_typen_sequenziell() -> void:
	var now := 100 * MIN
	var quests := RQuestEngine.annehmen(RQuestSlices.default_quests(), ALLES_DEF, now)
	var schritte: Array = [
		{"typ": "gehe_zu", "ort": "stall"},
		{"typ": "sprich_mit", "npc": "rosi"},
		{"typ": "sammle", "item": "apfel"},
		{"typ": "sammle", "item": "apfel"},
		{"typ": "pflege", "aktion": "striegeln"},
		{"typ": "reite_strecke", "strecke": "hof_runde"},
	]
	# Falsches Ereignis zaehlt nicht (Ziel 0 ist gehe_zu stall).
	var falsch := RQuestEngine.ereignis(quests, ALLES_DEF, {"typ": "gehe_zu", "ort": "teich"}, now)
	assert_false(falsch["geaendert"], "falscher Ort zaehlt nicht")
	for schritt: Dictionary in schritte:
		var ergebnis := RQuestEngine.ereignis(quests, ALLES_DEF, schritt, now)
		assert_true(ergebnis["geaendert"], "Schritt %s bucht" % schritt)
		quests = ergebnis["quests"]
	var lauf: Dictionary = quests["aktiv"]["fx_alles"]
	assert_eq(lauf["status"], RQuestEngine.STATUS_WARTEND, "warte_bis-Ziel schaltet auf wartend")
	assert_eq(int(lauf["bereitAt"]), now + 30 * MIN)
	# Ereignisse waehrend des Wartens werden ignoriert (auch das naechste Ziel).
	var zu_frueh := RQuestEngine.ereignis(
		quests, ALLES_DEF, {"typ": "gewinne_wettbewerb", "disziplin": "parcours", "platz": 1}, now
	)
	assert_false(zu_frueh["geaendert"], "wartende Laeufe ignorieren Ereignisse")
	# Zeitsprung: tick VOR Ablauf tut nichts, NACH Ablauf loest das Warten.
	var tick_frueh := RQuestEngine.tick(quests, now + 29 * MIN, [ALLES_DEF])
	assert_eq(tick_frueh["fertig"], [], "tick vor bereitAt loest nichts")
	var tick_spaet := RQuestEngine.tick(quests, now + 31 * MIN, [ALLES_DEF])
	assert_eq(tick_spaet["fertig"], ["fx_alles"])
	quests = tick_spaet["quests"]
	assert_eq(quests["aktiv"]["fx_alles"]["status"], RQuestEngine.STATUS_AKTIV)
	# Wettbewerb: Platz 3 reicht NICHT (Ziel: platz <= 2), Platz 1 schon.
	var vierter := RQuestEngine.ereignis(
		quests, ALLES_DEF, {"typ": "gewinne_wettbewerb", "disziplin": "parcours", "platz": 3}, now
	)
	assert_false(vierter["geaendert"], "Platz 3 verfehlt das Top-2-Ziel")
	var sieg := RQuestEngine.ereignis(
		quests, ALLES_DEF, {"typ": "gewinne_wettbewerb", "disziplin": "parcours", "platz": 1}, now
	)
	quests = sieg["quests"]
	assert_eq(
		quests["aktiv"]["fx_alles"]["status"],
		RQuestEngine.STATUS_ERFUELLBAR,
		"nach letztem Ziel erfuellbar"
	)


func test_fuehrendes_warte_ziel_startet_sofort() -> void:
	var def := {
		"id": "fx_warte",
		"typ": "neben",
		"geber": "rosi",
		"ziele": [{"typ": "warte_bis", "dauerMin": 10}],
	}
	var quests := RQuestEngine.annehmen(RQuestSlices.default_quests(), def, 0)
	assert_eq(quests["aktiv"]["fx_warte"]["status"], RQuestEngine.STATUS_WARTEND)
	var danach := RQuestEngine.tick(quests, 10 * MIN, [def])
	assert_eq(danach["fertig"], ["fx_warte"])
	assert_eq(
		danach["quests"]["aktiv"]["fx_warte"]["status"],
		RQuestEngine.STATUS_ERFUELLBAR,
		"einziges Ziel fertig = erfuellbar"
	)


func test_abgeben_und_belohnung() -> void:
	var def := {
		"id": "fx_fertig",
		"typ": "neben",
		"geber": "rosi",
		"ziele": [{"typ": "gehe_zu", "ort": "stall"}],
		"belohnung": {"muenzen": 50, "freischalten": ["fx_deko"]},
	}
	var quests := RQuestEngine.annehmen(RQuestSlices.default_quests(), def, 0)
	var zu_frueh := RQuestEngine.abgeben(quests, def, "2026-07-26")
	assert_false(zu_frueh["ok"], "aktive Quest laesst sich nicht abgeben")
	quests = RQuestEngine.ereignis(quests, def, {"typ": "gehe_zu", "ort": "stall"}, 0)["quests"]
	var abgabe := RQuestEngine.abgeben(quests, def, "2026-07-26")
	assert_true(abgabe["ok"])
	assert_eq(abgabe["belohnung"]["muenzen"], 50)
	quests = abgabe["quests"]
	assert_true((quests["erledigt"] as Array).has("fx_fertig"))
	assert_true((quests["freigeschaltet"] as Array).has("fx_deko"))
	assert_false((quests["aktiv"] as Dictionary).has("fx_fertig"))


func test_tagesaufgaben_reset_ueber_tage() -> void:
	var def := {
		"id": "fx_tages",
		"typ": "taeglich",
		"geber": "rosi",
		"ziele": [{"typ": "pflege", "aktion": "ausmisten", "n": 1}],
	}
	var quests := RQuestEngine.annehmen(RQuestSlices.default_quests(), def, 0)
	quests = (
		RQuestEngine.ereignis(quests, def, {"typ": "pflege", "aktion": "ausmisten"}, 0)["quests"]
	)
	quests = RQuestEngine.abgeben(quests, def, "2026-07-26")["quests"]
	assert_false((quests["erledigt"] as Array).has("fx_tages"), "Tages landet NICHT in erledigt")
	assert_eq(
		RQuestEngine.status_von(quests, def, {}, "2026-07-26"),
		RQuestEngine.STATUS_ERLEDIGT,
		"heute erledigt"
	)
	assert_eq(
		RQuestEngine.status_von(quests, def, {}, "2026-07-27"),
		RQuestEngine.STATUS_VERFUEGBAR,
		"morgen wieder verfuegbar"
	)


func test_mengen_ziel_zaehlt_n() -> void:
	var def := {
		"id": "fx_menge",
		"typ": "neben",
		"geber": "rosi",
		"ziele": [{"typ": "sammle", "item": "beere", "n": 5}],
	}
	var quests := RQuestEngine.annehmen(RQuestSlices.default_quests(), def, 0)
	quests = (
		RQuestEngine.ereignis(quests, def, {"typ": "sammle", "item": "beere", "n": 3}, 0)["quests"]
	)
	assert_eq(quests["aktiv"]["fx_menge"]["zaehler"], 3, "Ereignis-n wird aufaddiert")
	quests = (
		RQuestEngine.ereignis(quests, def, {"typ": "sammle", "item": "beere", "n": 2}, 0)["quests"]
	)
	assert_eq(quests["aktiv"]["fx_menge"]["status"], RQuestEngine.STATUS_ERFUELLBAR)

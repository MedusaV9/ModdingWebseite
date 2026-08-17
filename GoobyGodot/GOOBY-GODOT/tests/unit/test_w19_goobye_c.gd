extends TestCase
## W19 Welle C „Goo und Bye“ (Doc §7.1 + §4.2) — Wächter für:
##   (a) GoobyeLevel: Laden-Level 1–5 als reine ZUSTANDS-Prüfung (kein
##       Grind-Zähler, kein eigener Save-Wert) über umsatz.tage/gesamt,
##       plus der transaktionale Lieferwagen-Kauf (Level-5-Gate, atomar),
##   (b) Laden-Szene: Lieferwagen-Zeile im Bestell-Sheet (ehrlicher
##       Gate-Hinweis unter Level 5, Kauf-Knopf ab Level 5), der
##       Übergabe-Story-Beat (Karte + Van-Vorfahrt) und das Kisten-Drag-
##       Ritual beim Ausladen (Chips + Sackkarre, echte Input-Events,
##       LETZTER Drop = atomares Ausladen, Fehlwurf federt zurück),
##   (c) REHWEI-Rampe: Rolltor-Ecke steht immer, Lieferwagen + Kisten sind
##       GENAU dann sichtbar, wenn eine Großmarkt-Fahrt läuft (reine
##       Funktion des Save-Stands — Betreten während der Fahrt zeigt sie).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const LadenSzene := preload("res://scripts/dlc/goobye/laden_scene.tscn")
const RehweiSzene := preload("res://scenes/city/orte/rehwei.tscn")

## Gepinnte Test-Uhr (fixe Epoche — Determinismus-Regel AGENTS.md).
const T0 := 1_750_000_000_000

var _dir_seq := 0


## Umsatz-Zettel, der GENAU Level 5 erreicht (Schwellen aus GoobyeLevel).
## ACHTUNG: als const wäre das Dictionary READ-ONLY — in den Save gestagt
## bricht dann das Self-Heal (normalize_goobye) mit „read-only state“ ab.
## Darum liefert der Helfer immer eine frische, mutierbare Kopie.
static func _umsatz_level5() -> Dictionary:
	return {"tage": 14, "gestern": 0, "gesamt": 800}


func _fresh_gs(level: int, coins: int) -> Node:
	GoobyeState.register_slice()
	_dir_seq += 1
	var dir := "user://goobye_c_tests/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.clock.pin(T0)
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(GoobyeState.SLICE_ID)
	GoobyeState.reset_for_tests()
	GoobyeKatalog.registry_override = null
	GoobyeKatalog.reset_cache()


## ------------------------------------------------------ (a) Level PURE


func test_level_zustandspruefung() -> void:
	# Level ist eine reine Funktion des Umsatz-Zettels — kein Zähler.
	assert_eq(GoobyeLevel.level_von({}), 1, "leerer Zettel = Marktstand")
	assert_eq(GoobyeLevel.level_von({"tage": 1, "gesamt": 9999}), 1, "eine Schwelle reicht nicht")
	assert_eq(GoobyeLevel.level_von({"tage": 9999, "gesamt": 0}), 1, "andere Schwelle auch nicht")
	# Jede Stufe kippt GENAU an ihren beiden Schwellen (Kanten-Probe).
	for stufe: Dictionary in GoobyeLevel.STUFEN:
		var tage := int(stufe["tage"])
		var gesamt := int(stufe["gesamt"])
		assert_eq(
			GoobyeLevel.level_von({"tage": tage, "gesamt": gesamt}),
			int(stufe["level"]),
			"Stufe %d kippt an tage=%d/gesamt=%d" % [int(stufe["level"]), tage, gesamt]
		)
		assert_true(
			GoobyeLevel.level_von({"tage": tage - 1, "gesamt": gesamt}) < int(stufe["level"]),
			"ein Markttag zu wenig bleibt darunter"
		)
	assert_eq(GoobyeLevel.level_von({"tage": 999, "gesamt": 99999}), 5, "Deckel bei Level 5")
	assert_eq(GoobyeLevel.level_von({"tage": -3, "gesamt": -50}), 1, "Müll heilt zu Level 1")
	# Namens-Keys je Stufe (§7.1: Marktstand … Goo und Bye XXL).
	assert_eq(GoobyeLevel.name_key(1), "dlc_goobye.level.marktstand")
	assert_eq(GoobyeLevel.name_key(5), "dlc_goobye.level.xxl")
	assert_eq(GoobyeLevel.name_key(99), "dlc_goobye.level.xxl", "geclamped statt leer")
	# Save-Lesung: frischer Save = Level 1, gestagter Umsatz = Level 5.
	var gs := _fresh_gs(12, 0)
	assert_eq(GoobyeLevel.level_fuer(gs), 1, "frischer Save startet als Marktstand")
	gs.set_value("dlc.goobye.umsatz", _umsatz_level5())
	assert_eq(GoobyeLevel.level_fuer(gs), 5, "Level liest den Umsatz-Zettel")
	assert_eq(GoobyeLevel.level_fuer(null), 1, "ohne GameState defensiv Level 1")
	_teardown_gs(gs)


func test_lieferwagen_kauf_gate_und_atomik() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 5000)
	# Unter Level 5 blockt das Gate — und bucht NICHTS ab.
	assert_eq(
		GoobyeTransport.kaufe_lieferwagen(gs),
		GoobyeTransport.RESULT_GESPERRT,
		"Level 1 darf den Firmenwagen nicht kaufen"
	)
	assert_eq(int(gs.get_value("economy.coins")), 5000, "Gate-Versuch kostet nichts")
	assert_false(GoobyeTransport.lieferwagen_frei(gs), "Schalter bleibt aus")
	# Level 5 erreicht, aber zu wenig Münzen: atomar NICHTS passiert.
	gs.set_value("dlc.goobye.umsatz", _umsatz_level5())
	gs.set_value("economy.coins", GoobyeTransport.LIEFERWAGEN_PREIS - 1)
	assert_eq(GoobyeTransport.kaufe_lieferwagen(gs), GoobyeTransport.RESULT_BROKE)
	assert_eq(
		int(gs.get_value("economy.coins")),
		GoobyeTransport.LIEFERWAGEN_PREIS - 1,
		"Pleite-Versuch bucht nichts ab"
	)
	assert_false(GoobyeTransport.lieferwagen_frei(gs), "Schalter bleibt aus (broke)")
	# Erfolgsfall: GENAU der Preis geht weg, Kapazität springt auf 48.
	gs.set_value("economy.coins", GoobyeTransport.LIEFERWAGEN_PREIS + 250)
	assert_eq(GoobyeTransport.kaufe_lieferwagen(gs), GoobyeTransport.RESULT_OK)
	assert_eq(int(gs.get_value("economy.coins")), 250, "genau der Preis wurde abgebucht")
	assert_true(GoobyeTransport.lieferwagen_frei(gs), "Schalter im Save")
	assert_eq(GoobyeTransport.kapazitaet_fuer(gs), 48, "Kofferraum = 48 Kisten")
	# Doppelkauf blockt ehrlich (Doppel-Tap-Rennen) — wieder ohne Kosten.
	assert_eq(GoobyeTransport.kaufe_lieferwagen(gs), GoobyeTransport.RESULT_SCHON_DA)
	assert_eq(int(gs.get_value("economy.coins")), 250, "Doppelkauf kostet nichts")
	_teardown_gs(gs)


## ------------------------------------------------------ (b) Laden-Szene


func test_szene_lieferwagen_gate_zeile() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 500)
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	var knopf: Button = szene.find_child("Grossmarkt", true, false)
	knopf.pressed.emit()
	await wait_frames(2)
	# Level 1: ehrlicher Gate-Hinweis MIT aktuellem Level, kein Kauf-Knopf.
	var gate: Label = szene.find_child("LieferwagenGate", true, false)
	assert_ne(gate, null, "unter Level 5 steht der Gate-Hinweis")
	assert_true(gate.text.contains("1"), "Hinweis nennt das aktuelle Laden-Level")
	assert_eq(
		szene.find_child("LieferwagenKaufen", true, false), null, "kein Kauf-Knopf unter Level 5"
	)
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)


func test_szene_lieferwagen_kauf_und_uebergabe() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, GoobyeTransport.LIEFERWAGEN_PREIS + 300)
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	gs.set_value("dlc.goobye.umsatz", _umsatz_level5())
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	var knopf: Button = szene.find_child("Grossmarkt", true, false)
	knopf.pressed.emit()
	await wait_frames(2)
	var kaufen: Button = szene.find_child("LieferwagenKaufen", true, false)
	assert_ne(kaufen, null, "ab Level 5 steht der Kauf-Knopf im Bestell-Sheet")
	kaufen.pressed.emit()
	await wait_frames(2)
	# Kauf: atomar im Save, Sheet zu, Übergabe-Karte + Van-Vorfahrt laufen.
	assert_true(GoobyeTransport.lieferwagen_frei(gs), "Kauf liegt im Save")
	assert_eq(int(gs.get_value("economy.coins")), 300, "genau der Preis wurde abgebucht")
	assert_eq(szene.grossmarkt.sheet, null, "Bestell-Sheet macht der Übergabe Platz")
	assert_ne(szene.grossmarkt.uebergabe_overlay, null, "Übergabe-Karte steht")
	assert_ne(szene.find_child("GoobyeLieferwagen", true, false), null, "der Firmenwagen fährt vor")
	var weiter: Button = szene.find_child("UebergabeWeiter", true, false)
	assert_ne(weiter, null, "Danke-Knopf auf der Karte")
	weiter.pressed.emit()
	await wait_frames(2)
	assert_eq(szene.grossmarkt.uebergabe_overlay, null, "Karte räumt sich weg")
	# Sheet erneut öffnen: Zeile ist weg, der Kofferraum zählt jetzt 48.
	knopf.pressed.emit()
	await wait_frames(2)
	assert_eq(szene.find_child("LieferwagenZeile", true, false), null, "gekauft = keine Zeile mehr")
	var kofferraum: Label = szene.find_child("KofferraumZeile", true, false)
	assert_true(kofferraum.text.contains("48"), "Kofferraum-Zeile zeigt 48 Kisten")
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)


func test_szene_kisten_ritual_drag() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 500)
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	# Fahrt mit ZWEI Waren stagen und hinter die Ankunft spulen.
	assert_eq(GoobyeTransport.bestelle(gs, {"apple": 2, "carrot": 1}), GoobyeTransport.RESULT_OK)
	gs.clock.advance(GoobyeTransport.fahrzeit_ms(3) + 1_000)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	szene.grossmarkt.aktualisiere()
	await wait_frames(1)
	# Ankunft: Kisten-Chips (eine je Ware) + Sackkarre stehen ADDITIV im UI.
	assert_eq(szene.grossmarkt.ritual_chips.size(), 2, "eine Kiste je Ware")
	var karre: Control = szene.find_child("Sackkarre", true, false)
	assert_ne(karre, null, "Sackkarre steht bereit")
	var apfel_vorher := int(gs.get_value("dlc.goobye.lager.apple", 0))
	var moehre_vorher := int(gs.get_value("dlc.goobye.lager.carrot", 0))
	# Kiste 1 mit ECHTEN Input-Events ziehen (drücken → ziehen → loslassen).
	var apfel_kiste: Control = szene.find_child("Kiste_apple", true, false)
	assert_ne(apfel_kiste, null, "Apfel-Kiste hängt im UI")
	_ziehe_auf(apfel_kiste, karre)
	await wait_frames(2)
	assert_eq(szene.grossmarkt.ritual_chips.size(), 1, "erste Kiste ist gelandet")
	assert_eq(
		int(gs.get_value("dlc.goobye.lager.apple", 0)),
		apfel_vorher,
		"Save bleibt unangetastet, solange Kisten übrig sind (atomar am Ende)"
	)
	# Daneben abgelegt: Kiste federt zurück, nichts geht verloren.
	var moehren_kiste: Control = szene.find_child("Kiste_carrot", true, false)
	_ziehe_daneben(moehren_kiste)
	await wait_frames(20)
	assert_eq(szene.grossmarkt.ritual_chips.size(), 1, "Fehlwurf lässt die Kiste im Spiel")
	assert_false(GoobyeTransport.unterwegs_von(gs).is_empty(), "Fahrt liegt weiter im Save")
	# Letzte Kiste landet → ATOMARES Ausladen + Ritual räumt sich weg.
	_ziehe_auf(moehren_kiste, karre)
	await wait_frames(2)
	assert_true(GoobyeTransport.unterwegs_von(gs).is_empty(), "Fahrt abgeräumt")
	assert_eq(int(gs.get_value("dlc.goobye.lager.apple", 0)), apfel_vorher + 2, "+2 Äpfel")
	assert_eq(int(gs.get_value("dlc.goobye.lager.carrot", 0)), moehre_vorher + 1, "+1 Möhre")
	assert_eq(szene.grossmarkt.ritual_chips.size(), 0, "alle Kisten verräumt")
	await wait_frames(2)
	assert_eq(szene.find_child("Sackkarre", true, false), null, "Sackkarre räumt sich weg")
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)


## Drag-Geste als echte Events auf dem Chip-Handler: drücken, Bewegung
## exakt auf die Ziel-Mitte, loslassen (derselbe Code-Pfad wie ein Finger).
func _ziehe_auf(chip: Control, ziel: Control) -> void:
	_druecke(chip, true)
	var bewegung := InputEventMouseMotion.new()
	bewegung.relative = ziel.get_global_rect().get_center() - chip.get_global_rect().get_center()
	chip._gui_input(bewegung)
	_druecke(chip, false)


## Fehlwurf: weit weg vom Ziel loslassen (Rück-Feder-Pfad).
func _ziehe_daneben(chip: Control) -> void:
	_druecke(chip, true)
	var bewegung := InputEventMouseMotion.new()
	bewegung.relative = Vector2(4000.0, 4000.0)
	chip._gui_input(bewegung)
	_druecke(chip, false)


func _druecke(chip: Control, gedrueckt: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = gedrueckt
	chip._gui_input(ev)


## ------------------------------------------------------ (c) REHWEI-Rampe


func test_rehwei_rampe_zeigt_laufende_fahrt() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 100)
	var ort: OrtRehwei = RehweiSzene.instantiate()
	ort.game_state_override = gs
	ort.leben_seed_override = 4711
	ort.leben_stumm_override = true
	tree.root.add_child(ort)
	await wait_frames(3)
	# Bauliche Anker stehen immer: Rolltor + Fahrt-Container mit Van.
	assert_ne(ort.find_child("RampenTor", true, false), null, "Rolltor-Ecke steht immer")
	assert_ne(ort.rampen_fahrt, null, "Fahrt-Container hängt im Baum")
	assert_ne(
		ort.find_child("GoobyeLieferwagen", true, false), null, "Lieferwagen-Requisite gebaut"
	)
	assert_false(ort.rampen_fahrt.visible, "ohne Fahrt bleibt die Rampe leer")
	# Fahrt läuft → Betreten (bzw. der Puls) zeigt Van + Kisten.
	assert_eq(GoobyeTransport.bestelle(gs, {"apple": 2}), GoobyeTransport.RESULT_OK)
	ort.rampe_aktualisieren()
	assert_true(ort.rampen_fahrt.visible, "laufende Fahrt zeigt Van + Kisten")
	# Ausladen räumt die Fahrt — die Rampe wird wieder still.
	gs.clock.advance(GoobyeTransport.fahrzeit_ms(2) + 1_000)
	assert_true(bool(GoobyeTransport.ausladen(gs)["ok"]), "Ankunft + Ausladen")
	ort.rampe_aktualisieren()
	assert_false(ort.rampen_fahrt.visible, "nach dem Ausladen wieder leer")
	ort.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)

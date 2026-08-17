extends TestCase
## W15/GAMESQA2 — Politur-Logik der Gruppe-2-Runde (nur Präsentation/Input):
## (1) purblePlace: needed_station() sagt die nächste Bau-Station der ältesten
##     Form an (Gold-Highlight im Dock) — Spiegel der Bot-Reihung, PURE.
## (2) ranchHerde: treib_ziel()-Forgiveness — ein Tipp auf ein freies Schaf
##     springt auf den Treibpunkt HINTER dem Schaf (Tor-Politik), inkl.
##     Tor-Korridor-Schutz; Sim (herde_logic.gd) bleibt unangetastet.
## (3) rocketRescue: cam_target() — Blickvorsprung in Flugrichtung, geklemmt
##     auf die sichtbaren Weltränder (Kamera-Framing, Sim zertifiziert).
## (4) Level-Menü-Charme gvz+gobnom: Sterne-Stempel-Text, Blätter-Staffelung
##     und AC-Karten-StyleBox (Schatten-Zustände) — beide Selects zahlengleich.

const Purble := preload("res://scripts/minigames/games/purble_place/purble_place.gd")
const Herde := preload("res://scripts/minigames/games/ranch_herde/herde_game.gd")
const HerdeLogic := preload("res://scripts/minigames/games/ranch_herde/herde_logic.gd")
const Rocket := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue.gd")

## Level {} = herde_logic-Defaults: Pferch (0, −7) 5×3,5, Tor 2,6 → Tormitte
## (0, −5,25); Korridor-Schutzlinie z ≥ −4,65.
const LVL := {}


func _pan(
	id: int, sponge: Variant, bake: Variant, icing: Variant, topping: Variant, candles: int
) -> Dictionary:
	return {
		"id": id,
		"sponge": sponge,
		"bake": bake,
		"icing": icing,
		"topping": topping,
		"candles": candles,
	}


func _spec(sponge: String, icing: String, topping: String, candles: int) -> Dictionary:
	return {"sponge": sponge, "icing": icing, "topping": topping, "candles": candles}


func test_purble_needed_station_folgt_der_bau_reihenfolge() -> void:
	var spec := _spec("vanilla", "pink", "cherry", 2)
	var ticket := {"spec": spec}
	var kein_pan := {"tickets": [ticket], "pans": []}
	assert_eq(Purble.needed_station(kein_pan), "spawn", "ohne Form: erst aufs Band")
	assert_eq(Purble.needed_station({"tickets": [], "pans": []}), "", "ohne Wunsch: nichts")
	var roh := {"tickets": [ticket], "pans": [_pan(1, null, null, null, null, 0)]}
	assert_eq(Purble.needed_station(roh), "teig.vanilla", "leere Form: Teig zuerst")
	var im_ofen := {"tickets": [ticket], "pans": [_pan(1, "vanilla", null, null, null, 0)]}
	assert_eq(Purble.needed_station(im_ofen), "", "Ofenphase: nichts hervorheben")
	var gebacken := {"tickets": [ticket], "pans": [_pan(1, "vanilla", "golden", null, null, 0)]}
	assert_eq(Purble.needed_station(gebacken), "guss.pink", "gebacken: Guss dran")
	var mit_guss := {"tickets": [ticket], "pans": [_pan(1, "vanilla", "golden", "pink", null, 0)]}
	assert_eq(Purble.needed_station(mit_guss), "deko.cherry", "Guss drauf: Deko dran")
	var mit_deko := {
		"tickets": [ticket], "pans": [_pan(1, "vanilla", "golden", "pink", "cherry", 0)]
	}
	assert_eq(Purble.needed_station(mit_deko), "kerzen", "Deko drauf: Kerzen fehlen")
	var fertig := {"tickets": [ticket], "pans": [_pan(1, "vanilla", "golden", "pink", "cherry", 2)]}
	assert_eq(Purble.needed_station(fertig), "ship", "alles drauf: Versand")


func test_purble_needed_station_ohne_guss_und_aelteste_form() -> void:
	var schlicht := {"spec": _spec("chocolate", "none", "none", 1)}
	var ohne_extras := {
		"tickets": [schlicht], "pans": [_pan(3, "chocolate", "golden", null, null, 0)]
	}
	assert_eq(Purble.needed_station(ohne_extras), "kerzen", "none-Stufen werden übersprungen")
	# Zwei Formen: die ÄLTESTE (kleinste id) bestimmt die Ansage.
	var zwei := {
		"tickets": [{"spec": _spec("vanilla", "pink", "none", 0)}],
		"pans": [_pan(7, "vanilla", "golden", "pink", null, 0), _pan(2, null, null, null, null, 0)],
	}
	assert_eq(Purble.needed_station(zwei), "teig.vanilla", "älteste Form zuerst bedienen")


func test_purble_intro_und_touch_konstanten() -> void:
	assert_almost(float(Purble.INTRO_S), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Muster)")
	assert_true(float(Purble.TOUCH_MIN_PT) >= 44.0, "Dock-Touchziele mindestens 44 pt")


func test_herde_treib_ziel_springt_hinter_das_schaf() -> void:
	var schaf := Vector2(3.0, 0.0)
	var herde := [{"x": schaf.x, "z": schaf.y, "drin": false}]
	var tipp := Vector2(3.5, 0.5)
	var ziel: Vector2 = Herde.treib_ziel(tipp, herde, LVL)
	assert_true(ziel.distance_to(tipp) > 0.5, "Tipp nahe am Schaf springt um")
	assert_almost(
		ziel.distance_to(schaf), float(Herde.TREIB_ABSTAND), 1e-4, "Treibpunkt-Abstand fix"
	)
	var vom_tor := (schaf - HerdeLogic.tor_pos(LVL)).normalized()
	var richtung := (ziel - schaf).normalized()
	assert_almost(richtung.x, vom_tor.x, 1e-4, "Treibpunkt liegt HINTER dem Schaf (x)")
	assert_almost(richtung.y, vom_tor.y, 1e-4, "Treibpunkt liegt HINTER dem Schaf (z)")


func test_herde_treib_ziel_ignoriert_ferne_und_eingepferchte() -> void:
	var frei_weit := [{"x": 8.0, "z": 8.0, "drin": false}]
	var tipp := Vector2(1.0, 1.0)
	assert_eq(Herde.treib_ziel(tipp, frei_weit, LVL), tipp, "fern vom Schaf: Tipp unverändert")
	var drin := [{"x": 1.2, "z": 1.2, "drin": true}]
	assert_eq(Herde.treib_ziel(tipp, drin, LVL), tipp, "eingepferchte Schafe zählen nicht")
	assert_eq(Herde.treib_ziel(tipp, [], LVL), tipp, "leere Herde: Tipp unverändert")


func test_herde_treib_ziel_korridor_schutz() -> void:
	# Schaf NÖRDLICH der Torlinie im Tor-Korridor: der naive Treibpunkt läge
	# noch tiefer im Pferch — der Schutz klemmt ihn auf die Korridor-Linie,
	# sonst drückt der Reiter das Schaf wieder heraus.
	var herde := [{"x": 0.0, "z": -6.5, "drin": false}]
	var ziel: Vector2 = Herde.treib_ziel(Vector2(0.2, -6.3), herde, LVL)
	var p := HerdeLogic.pferch_rect(LVL)
	var linie := float(p["z"]) + float(p["t"]) * 0.5 + 0.6
	assert_true(ziel.y >= linie - 1e-4, "Treibpunkt nie nördlich der Tor-Schutzlinie")


func test_rocket_cam_target_blickvorsprung_und_klemme() -> void:
	assert_almost(float(Rocket.cam_target(0.0, 0.0, 5.0)), 0.0, 1e-6, "ruhend: mittig")
	var lookahead := float(Rocket.CAM_LOOKAHEAD_S)
	assert_almost(
		float(Rocket.cam_target(1.0, 2.0, 5.0)),
		1.0 + 2.0 * lookahead,
		1e-6,
		"Blickvorsprung = x + vx·Vorlauf"
	)
	assert_almost(float(Rocket.cam_target(4.9, 3.0, 5.0)), 5.0, 1e-6, "rechts geklemmt")
	assert_almost(float(Rocket.cam_target(-4.9, -3.0, 5.0)), -5.0, 1e-6, "links geklemmt")


func test_level_select_stempel_text_beide_selects_zahlengleich() -> void:
	for select: Variant in [GvzLevelSelect, GobnomLevelSelect]:
		assert_eq(select.stamp_text(0, true), "· · ·", "gesperrt: Punkte statt Schloss-Emoji")
		assert_eq(select.stamp_text(0, false), "☆☆☆", "offen ohne Sterne: leere Sterne")
		assert_eq(select.stamp_text(2, false), "★★☆", "2 Sterne")
		assert_eq(select.stamp_text(3, false), "★★★", "3 Sterne voll")
		assert_eq(select.stamp_text(9, false), "★★★", "über 3 wird geklemmt")


func test_level_select_blaetter_staffelung_gedeckelt() -> void:
	for select: Variant in [GvzLevelSelect, GobnomLevelSelect]:
		assert_almost(float(select.page_turn_delay(0)), 0.0, 1e-6, "erste Kachel sofort")
		assert_almost(
			float(select.page_turn_delay(1)),
			float(select.PAGE_TURN_STAGGER_S),
			1e-6,
			"Kachel 2 um eine Staffel später"
		)
		assert_almost(
			float(select.page_turn_delay(50)),
			float(select.PAGE_TURN_MAX_DELAY_S),
			1e-6,
			"lange Listen blättern gedeckelt"
		)
		assert_almost(float(select.page_turn_delay(-3)), 0.0, 1e-6, "negativer Index ist 0")


func test_level_select_card_style_schatten_zustaende() -> void:
	var fill := Color("#FFF6E3")
	var border := Color("#4A3B36")
	for select: Variant in [GvzLevelSelect, GobnomLevelSelect]:
		var normal: StyleBoxFlat = select.card_style("normal", fill, border, 3, false)
		var hover: StyleBoxFlat = select.card_style("hover", fill, border, 3, false)
		var pressed: StyleBoxFlat = select.card_style("pressed", fill, border, 3, false)
		var locked: StyleBoxFlat = select.card_style("normal", fill, border, 2, true)
		assert_true(normal.shadow_size > 0, "offene Karte wirft Schatten")
		assert_true(hover.shadow_size > normal.shadow_size, "Hover hebt die Karte an")
		assert_eq(pressed.shadow_size, 0, "Druck senkt die Karte (kein Schatten)")
		assert_true(pressed.bg_color.v < normal.bg_color.v, "Druck dunkelt die Fläche ab")
		assert_eq(locked.shadow_size, 0, "gesperrte Karte liegt flach")
		assert_eq(locked.border_color, border, "Rahmenfarbe bleibt wie übergeben")
		assert_eq(normal.corner_radius_top_left, 16, "AC-Rundung 16 px")

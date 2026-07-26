extends TestCase
## HAUS-CUSTOM — home.style-Slice: Kauf/Besitz (atomar über Economy.spend),
## Setter-Validierung, Zufall/Reset, Speichern/Laden über einen echten
## GameState und die Migration alter Stände (fehlende Werte = Standard).

const GameStateScript := preload("res://scripts/state/game_state.gd")

var _dir_seq := 0
var _letzter_pfad := ""


func _fresh_gs(coins := 1000) -> Node:
	HomeState.register_slice()
	_dir_seq += 1
	var dir := "user://hauscustom_tests/gs_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	_letzter_pfad = dir + "/save_v5.json"
	gs.initialize(_letzter_pfad)
	gs.update(func(state: Dictionary) -> void: state["economy"]["coins"] = coins)
	return gs


func test_kauf_pfade() -> void:
	var gs := _fresh_gs(200)
	assert_eq(HouseStyleState.kaufen(gs, "wand", "gibtsnicht"), HouseStyleState.RESULT_UNKNOWN)
	assert_eq(HouseStyleState.kaufen(gs, "wand", "uni"), HouseStyleState.RESULT_OWNED, "Preis 0")
	assert_eq(
		HouseStyleState.kaufen(gs, "wand", "rauten"), HouseStyleState.RESULT_BROKE, "260 > 200"
	)
	assert_eq(int(gs.get_value("economy.coins")), 200, "Fehlkauf bucht nichts ab")
	assert_false(HouseStyleState.ist_gekauft(gs, "wand", "gebluemt"), "vorher nicht im Besitz")
	assert_eq(HouseStyleState.kaufen(gs, "wand", "gebluemt"), HouseStyleState.RESULT_OK)
	assert_eq(int(gs.get_value("economy.coins")), 20, "180 Münzen abgebucht")
	assert_true(HouseStyleState.ist_gekauft(gs, "wand", "gebluemt"), "jetzt im Besitz")
	assert_eq(
		HouseStyleState.kaufen(gs, "wand", "gebluemt"),
		HouseStyleState.RESULT_OWNED,
		"kein Doppelkauf"
	)
	assert_eq(int(gs.get_value("economy.coins")), 20, "Doppelkauf kostet nichts")
	gs.free()


func test_set_raum_flaeche_validierung_und_besitz() -> void:
	var gs := _fresh_gs()
	assert_false(
		HouseStyleState.set_raum_flaeche(gs, "living", "wand", "gibtsnicht", "rose"),
		"unbekannte Option"
	)
	assert_false(
		HouseStyleState.set_raum_flaeche(gs, "living", "wand", "uni", "neongruen"),
		"unbekannte Farbe"
	)
	assert_false(
		HouseStyleState.set_raum_flaeche(gs, "living", "wand", "gebluemt", "rose"),
		"nicht gekauft = abgelehnt"
	)
	assert_eq(
		str(HouseStyleState.raum_style(gs, "living")["wand"]), "uni", "nichts hat sich geändert"
	)
	HouseStyleState.kaufen(gs, "wand", "gebluemt")
	assert_true(HouseStyleState.set_raum_flaeche(gs, "living", "wand", "gebluemt", "rose"))
	var raum := HouseStyleState.raum_style(gs, "living")
	assert_eq(str(raum["wand"]), "gebluemt")
	assert_eq(str(raum["wandFarbe"]), "rose")
	assert_eq(str(raum["boden"]), "dielen_hell", "Boden bleibt Default")
	assert_true(
		HouseStyleState.set_raum_flaeche(gs, "kitchen", "boden", "fliesen_gross", "mint"),
		"Default-Option ist auch mit Preis > 0 im Besitz"
	)
	gs.free()


func test_set_haus_und_grundstueck() -> void:
	var gs := _fresh_gs()
	assert_true(HouseStyleState.set_haus(gs, "fassade", "rose"), "freie Farbwahl")
	assert_false(HouseStyleState.set_haus(gs, "fassade", "neonpink"), "nur Palette")
	assert_false(HouseStyleState.set_haus(gs, "dachForm", "walm"), "Dachform erst kaufen")
	HouseStyleState.kaufen(gs, "dachForm", "walm")
	assert_true(HouseStyleState.set_haus(gs, "dachForm", "walm"))
	assert_true(HouseStyleState.set_haus(gs, "hausnummerZahl", 250), "Zahl wird geklemmt")
	var haus: Dictionary = HouseStyleState.style(gs)["haus"]
	assert_eq(str(haus["fassade"]), "rose")
	assert_eq(str(haus["dachForm"]), "walm")
	assert_eq(int(haus["hausnummerZahl"]), HouseStyleState.NUMMER_MAX)
	assert_true(
		HouseStyleState.set_haus(gs, "briefkastenFarbe", "teal"), "erlaubte Briefkasten-Farbe"
	)
	assert_false(
		HouseStyleState.set_haus(gs, "briefkastenFarbe", "walnuss"),
		"Farbe muss zur aktuellen Variante passen"
	)
	assert_true(HouseStyleState.set_grundstueck(gs, "bodenFarbe", "salbei"))
	assert_false(HouseStyleState.set_grundstueck(gs, "boden", "wildblumen"), "erst kaufen")
	HouseStyleState.kaufen(gs, "grundBoden", "wildblumen")
	assert_true(HouseStyleState.set_grundstueck(gs, "boden", "wildblumen"))
	var grund: Dictionary = HouseStyleState.style(gs)["grundstueck"]
	assert_eq(str(grund["boden"]), "wildblumen")
	gs.free()


func test_speichern_und_laden() -> void:
	var gs := _fresh_gs()
	var pfad := _letzter_pfad
	HouseStyleState.kaufen(gs, "wand", "punkte")
	HouseStyleState.set_raum_flaeche(gs, "living", "wand", "punkte", "mint")
	HouseStyleState.set_haus(gs, "fassade", "himmel")
	HouseStyleState.set_grundstueck(gs, "zaunFarbe", "weiss")
	assert_true(gs.save_now(), "Speichern klappt")
	var neu: Node = GameStateScript.new()
	neu.initialize(pfad)
	assert_true(HouseStyleState.ist_gekauft(neu, "wand", "punkte"), "Besitz überlebt Laden")
	assert_eq(str(HouseStyleState.raum_style(neu, "living")["wandFarbe"]), "mint")
	assert_eq(str(HouseStyleState.style(neu)["haus"]["fassade"]), "himmel")
	assert_eq(str(HouseStyleState.style(neu)["grundstueck"]["zaunFarbe"]), "weiss")
	gs.free()
	neu.free()


func test_migration_alter_staende() -> void:
	# Alt-Stände kennen home.style gar nicht → komplette Defaults.
	var leer := HouseStyleState.normalize(null)
	assert_eq(leer["haus"], CustomizeCatalog.default_haus(), "fehlt = Standard-Haus")
	assert_eq(leer["grundstueck"], CustomizeCatalog.default_grundstueck(), "fehlt = Standard-Grund")
	assert_eq(leer["raeume"], {}, "keine Raum-Einträge erfunden")
	# Kaputte/halbe Stände: gültige Werte bleiben VERBATIM, Müll wird geheilt.
	var krumm := (
		HouseStyleState
		. normalize(
			{
				"gekauft": {"wand": ["gebluemt", "gibtsnicht", "gebluemt"], "boden": "quatsch"},
				"raeume":
				{"living": {"wand": "kaputt", "boden": "teppich", "bodenFarbe": "falsch"}},
				"haus": {"fassade": "rose", "dachForm": "ufo", "hausnummerZahl": -3},
				"grundstueck": {"boden": "kies", "bodenFarbe": "grau"},
			}
		)
	)
	assert_eq(krumm["gekauft"]["wand"], ["gebluemt"], "Duplikate + Unbekanntes raus")
	assert_eq(krumm["gekauft"]["boden"], [], "kaputte Liste = leer")
	var living: Dictionary = krumm["raeume"]["living"]
	assert_eq(str(living["wand"]), "uni", "unbekannte Wand → Raum-Default")
	assert_eq(str(living["boden"]), "teppich", "gültiger Boden bleibt")
	assert_eq(str(living["bodenFarbe"]), "creme", "falsche Farbe → erste erlaubte")
	assert_eq(str(krumm["haus"]["fassade"]), "rose", "gültige Fassade bleibt")
	assert_eq(str(krumm["haus"]["dachForm"]), "sattel", "unbekanntes Dach → Standard")
	assert_eq(int(krumm["haus"]["hausnummerZahl"]), HouseStyleState.NUMMER_MIN, "Zahl geklemmt")
	assert_eq(str(krumm["grundstueck"]["boden"]), "kies", "gültiger Belag bleibt")
	assert_eq(str(krumm["grundstueck"]["bodenFarbe"]), "grau", "gültige Farbe bleibt")


func test_zufall_nur_aus_besitz_und_reset() -> void:
	var gs := _fresh_gs(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for _i in 12:
		HouseStyleState.zufall_raum(gs, "living", rng)
		var raum := HouseStyleState.raum_style(gs, "living")
		assert_true(
			HouseStyleState.ist_gekauft(gs, "wand", str(raum["wand"])), "Zufall nur aus Besitz"
		)
		assert_true(
			CustomizeCatalog.farben("wand", str(raum["wand"])).has(str(raum["wandFarbe"])),
			"Zufallsfarbe erlaubt"
		)
	HouseStyleState.zufall_haus(gs, rng)
	HouseStyleState.zufall_grundstueck(gs, rng)
	var haus: Dictionary = HouseStyleState.style(gs)["haus"]
	assert_true(CustomizeCatalog.farb_wahl("fassade").has(str(haus["fassade"])))
	HouseStyleState.reset_raum(gs, "living")
	HouseStyleState.reset_haus(gs)
	HouseStyleState.reset_grundstueck(gs)
	assert_eq(HouseStyleState.raum_style(gs, "living"), CustomizeCatalog.raum_default("living"))
	assert_eq(HouseStyleState.style(gs)["haus"], CustomizeCatalog.default_haus())
	assert_eq(HouseStyleState.style(gs)["grundstueck"], CustomizeCatalog.default_grundstueck())
	gs.free()


func test_style_liefert_kopie() -> void:
	var gs := _fresh_gs()
	var kopie := HouseStyleState.style(gs)
	kopie["haus"]["fassade"] = "anthrazit"
	assert_eq(
		str(HouseStyleState.style(gs)["haus"]["fassade"]),
		str(CustomizeCatalog.default_haus()["fassade"]),
		"Mutation der Kopie erreicht den Save nicht"
	)
	gs.free()

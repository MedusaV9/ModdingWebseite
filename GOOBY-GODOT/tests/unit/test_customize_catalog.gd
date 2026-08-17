extends TestCase
## HAUS-CUSTOM — Katalog-Integrität des Gestalten-Modus: beide JSON-Kataloge
## laden, jede Option hat gültige IDs/Preise/Namen/Muster/Palette-Farben,
## die Farb-Bereiche sind gefüllt und ALLE Defaults (Haus, Grundstück,
## Räume) verweisen auf existierende Optionen mit erlaubten Farben.

## Mindest-Optionszahlen je Art (User-Wunsch „viele Optionen").
const MINDEST_ANZAHL := {
	"wand": 10,
	"boden": 8,
	"dachForm": 3,
	"hausnummer": 3,
	"briefkasten": 4,
	"vordach": 4,
	"grundBoden": 7,
	"weg": 5,
	"zaun": 5,
}


func test_kataloge_geladen_und_gross_genug() -> void:
	CustomizeCatalog.reset_cache()
	for art: String in CustomizeCatalog.OPTION_ARTEN:
		var anzahl := CustomizeCatalog.optionen(art).size()
		assert_true(
			anzahl >= int(MINDEST_ANZAHL[art]),
			"%s: %d Optionen (mind. %d)" % [art, anzahl, int(MINDEST_ANZAHL[art])]
		)


func test_option_integritaet() -> void:
	for art: String in CustomizeCatalog.OPTION_ARTEN:
		var gesehen: Array = []
		for option: Dictionary in CustomizeCatalog.optionen(art):
			var id := str(option.get("id", ""))
			assert_ne(id, "", "%s: Option ohne id" % art)
			assert_false(gesehen.has(id), "%s/%s: doppelte id" % [art, id])
			gesehen.append(id)
			assert_true(int(option.get("preis", -1)) >= 0, "%s/%s: Preis >= 0" % [art, id])
			assert_ne(str(option.get("name_de", "")), "", "%s/%s: name_de" % [art, id])
			assert_ne(str(option.get("name_en", "")), "", "%s/%s: name_en" % [art, id])
			for farbe: Variant in CustomizeCatalog.farben(art, id):
				assert_true(
					CustomizeMaterials.ist_farbe(str(farbe)),
					"%s/%s: Farbe %s in Palette" % [art, id, farbe]
				)
			var muster := str(option.get("muster", ""))
			if muster != "":
				assert_true(
					CustomizeMaterials.hat_muster(muster),
					"%s/%s: Muster %s hat Generator" % [art, id, muster]
				)


func test_flaechen_optionen_haben_muster_und_farben() -> void:
	for art: String in ["wand", "boden", "grundBoden"]:
		for option: Dictionary in CustomizeCatalog.optionen(art):
			var id := str(option.get("id", ""))
			assert_ne(str(option.get("muster", "")), "", "%s/%s braucht Muster" % [art, id])
			assert_true(
				CustomizeCatalog.farben(art, id).size() >= 2,
				"%s/%s: mind. 2 Farbvarianten" % [art, id]
			)


func test_farb_bereiche_gefuellt() -> void:
	for bereich: String in CustomizeCatalog.FARB_BEREICHE:
		var farben := CustomizeCatalog.farb_wahl(bereich)
		assert_true(farben.size() >= 6, "%s: mind. 6 Farben (%d)" % [bereich, farben.size()])
		for farbe: Variant in farben:
			assert_true(
				CustomizeMaterials.ist_farbe(str(farbe)), "%s: %s in Palette" % [bereich, farbe]
			)


func test_defaults_haus_valide() -> void:
	var haus := CustomizeCatalog.default_haus()
	assert_true(CustomizeCatalog.farb_wahl("fassade").has(str(haus["fassade"])), "fassade")
	assert_true(CustomizeCatalog.farb_wahl("dach").has(str(haus["dachFarbe"])), "dachFarbe")
	assert_true(CustomizeCatalog.farb_wahl("tuer").has(str(haus["tuerFarbe"])), "tuerFarbe")
	assert_true(CustomizeCatalog.farb_wahl("fenster").has(str(haus["fensterFarbe"])), "fenster")
	assert_false(CustomizeCatalog.def("dachForm", str(haus["dachForm"])).is_empty(), "dachForm")
	assert_false(CustomizeCatalog.def("hausnummer", str(haus["hausnummer"])).is_empty(), "nummer")
	assert_false(
		CustomizeCatalog.def("briefkasten", str(haus["briefkasten"])).is_empty(), "briefkasten"
	)
	assert_false(CustomizeCatalog.def("vordach", str(haus["vordach"])).is_empty(), "vordach")
	assert_true(
		CustomizeCatalog.farben("briefkasten", str(haus["briefkasten"])).has(
			str(haus["briefkastenFarbe"])
		),
		"briefkastenFarbe erlaubt"
	)


func test_defaults_grundstueck_und_raeume_valide() -> void:
	var grund := CustomizeCatalog.default_grundstueck()
	assert_false(CustomizeCatalog.def("grundBoden", str(grund["boden"])).is_empty(), "boden")
	assert_false(CustomizeCatalog.def("weg", str(grund["weg"])).is_empty(), "weg")
	assert_false(CustomizeCatalog.def("zaun", str(grund["zaun"])).is_empty(), "zaun")
	assert_true(
		CustomizeCatalog.farben("grundBoden", str(grund["boden"])).has(str(grund["bodenFarbe"])),
		"bodenFarbe erlaubt"
	)
	for room_id: Variant in RoomDefs.ids():
		if bool(RoomDefs.room(str(room_id)).get("outdoor", false)):
			continue
		var raum := CustomizeCatalog.raum_default(str(room_id))
		for art: String in ["wand", "boden"]:
			var id := str(raum.get(art, ""))
			assert_false(CustomizeCatalog.def(art, id).is_empty(), "%s: %s" % [room_id, art])
			assert_true(
				CustomizeCatalog.farben(art, id).has(str(raum.get("%sFarbe" % art, ""))),
				"%s: %sFarbe erlaubt" % [room_id, art]
			)


func test_defaults_gelten_als_besitz() -> void:
	# Der Start-Look muss OHNE Münzen wieder herstellbar sein — auch wenn die
	# Option regulär Geld kostet (Küchen-Fliesen, dunkle Schlafzimmer-Dielen).
	assert_true(CustomizeCatalog.ist_default("boden", "fliesen_gross"), "Küchen-Default")
	assert_true(CustomizeCatalog.ist_default("boden", "dielen_dunkel"), "Schlafzimmer-Default")
	assert_true(CustomizeCatalog.ist_default("zaun", "latten"), "Zaun-Default")
	assert_false(CustomizeCatalog.ist_default("wand", "gebluemt"), "Kauf-Tapete kein Default")
	assert_false(CustomizeCatalog.ist_default("boden", "gibtsnicht"), "unbekannt nie Default")


func test_def_und_display_name() -> void:
	var def := CustomizeCatalog.def("wand", "gebluemt")
	assert_eq(str(def.get("muster", "")), "blumen", "def liefert die Option")
	assert_eq(CustomizeCatalog.def("wand", "gibtsnicht"), {}, "unbekannt = leer, kein Crash")
	assert_eq(CustomizeCatalog.display_name(def, "de"), "Blümchen-Tapete")
	assert_eq(CustomizeCatalog.display_name(def, "en"), "Floral Wallpaper")
	assert_eq(CustomizeCatalog.preis("wand", "gebluemt"), 180, "Preis aus den Daten")
	assert_eq(CustomizeCatalog.preis("wand", "gibtsnicht"), 0, "unbekannt = 0")

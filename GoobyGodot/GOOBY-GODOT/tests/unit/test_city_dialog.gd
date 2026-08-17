extends TestCase
## W3a — OrtDialogRunner: purer Dialogbaum-Runner (Doc E §2.4) über den echten
## JSON-Bäumen (Arzt/GOOBYTHEKE/REHWEI) — cond-Filter, Effekte, Auto-Weiter.

const GOUHBUS := "res://scripts/city/data/dialoge/gouhbus.json"
const GOOBYTHEKE := "res://scripts/city/data/dialoge/goobytheke.json"
const REHWEI := "res://scripts/city/data/dialoge/rehwei.json"


func test_baeume_laden_und_starten() -> void:
	for pfad in [GOUHBUS, GOOBYTHEKE, REHWEI]:
		var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(pfad))
		assert_true(runner.ist_geladen(), "Baum lädt: %s" % pfad)
		assert_true(runner.text().size() >= 1, "Startknoten hat Text")
		assert_ne(runner.sprecher(), "", "Startknoten hat Sprecher")


func test_cond_ok() -> void:
	assert_true(OrtDialogRunner.cond_ok("", {}), "leer = immer wahr")
	assert_true(OrtDialogRunner.cond_ok("flag:x", {"x": true}))
	assert_false(OrtDialogRunner.cond_ok("flag:x", {}))
	assert_false(OrtDialogRunner.cond_ok("!flag:x", {"x": true}))
	assert_true(OrtDialogRunner.cond_ok("!flag:x", {}))


func test_effekt_parsen() -> void:
	assert_eq(
		OrtDialogRunner.effekt_parsen("flag:rezept_tropfen"),
		{"typ": "flag", "name": "rezept_tropfen", "wert": true}
	)
	assert_eq(
		OrtDialogRunner.effekt_parsen("flag_weg:rezept_tropfen"),
		{"typ": "flag", "name": "rezept_tropfen", "wert": false}
	)
	assert_eq(
		OrtDialogRunner.effekt_parsen("item:medicine"),
		{"typ": "item", "name": "medicine", "wert": true}
	)
	assert_eq(OrtDialogRunner.effekt_parsen("laden")["typ"], "laden")


func test_arzt_stellt_rezept_aus() -> void:
	var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(GOUHBUS))
	var sichtbar := runner.optionen()
	assert_eq(sichtbar.size(), 3, "ohne Rezept-Flag: krank/titel/checkup")
	assert_eq(sichtbar[0]["next"], "diagnose")
	assert_true(runner.waehlen(0), "→ diagnose")
	assert_true(runner.waehlen(0), "→ nutella (EIN Glas? Respekt.)")
	assert_false(runner.ist_ende(), "nutella hat Auto-Weiter")
	assert_eq(runner.auto_next(), "rezept")
	assert_true(runner.weiter(), "Auto-Weiter → rezept")
	assert_true(runner.ist_ende(), "Rezept-Knoten beendet den Dialog")
	assert_true(runner.flags.get("rezept_tropfen", false), "Flag-Effekt gespiegelt")
	assert_eq(runner.effekte()[0], {"typ": "flag", "name": "rezept_tropfen", "wert": true})


func test_arzt_mit_rezept_zweigt_ab() -> void:
	var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(GOUHBUS), {"rezept_tropfen": true})
	var sichtbar := runner.optionen()
	assert_eq(sichtbar.size(), 3)
	assert_eq(sichtbar[0]["next"], "rezept_schon", "cond wählt den Schon-Zweig")


func test_titel_schleife_zurueck_zu_hallo() -> void:
	var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(GOUHBUS))
	assert_true(runner.waehlen(1), "→ titel (im Aufzug gefunden)")
	assert_true(runner.weiter(), "titel → hallo")
	assert_eq(runner.aktuell, "hallo")


func test_goobytheke_rezept_einloesen() -> void:
	var runner := OrtDialogRunner.new(
		OrtDialogRunner.baum_laden(GOOBYTHEKE), {"rezept_tropfen": true}
	)
	assert_eq(runner.optionen().size(), 3, "mit Rezept: einlösen sichtbar")
	assert_true(runner.waehlen(0), "→ rezept_einloesen")
	var effekte := runner.effekte()
	assert_eq(effekte.size(), 2, "Rezept weg + Medizin ins Inventar")
	assert_eq(effekte[0], {"typ": "flag", "name": "rezept_tropfen", "wert": false})
	assert_eq(effekte[1]["typ"], "item")
	assert_false(runner.flags.has("rezept_tropfen"), "flag_weg löscht die Kopie")


func test_goobytheke_ohne_rezept_versteckt_option() -> void:
	var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(GOOBYTHEKE))
	for option in runner.optionen():
		assert_ne(option["next"], "rezept_einloesen", "einlösen braucht Flag")
	assert_eq(runner.optionen().size(), 2)


func test_rehwei_laden_effekt() -> void:
	var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(REHWEI))
	assert_true(runner.waehlen(0), "→ laden")
	assert_true(runner.ist_ende())
	assert_eq(runner.effekte()[0]["typ"], "laden", "öffnet das Händler-Sheet")


func test_text_string_wird_zeile() -> void:
	var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(REHWEI))
	assert_eq(runner.text().size(), 1, "String-text → 1 Zeile")


func test_ungueltige_wahl_und_kaputter_baum() -> void:
	var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(REHWEI))
	assert_false(runner.waehlen(99), "Index außerhalb")
	assert_false(runner.waehlen(-1))
	var kaputt := OrtDialogRunner.new({})
	assert_false(kaputt.ist_geladen())
	assert_true(kaputt.ist_ende(), "leerer Baum terminiert sofort")

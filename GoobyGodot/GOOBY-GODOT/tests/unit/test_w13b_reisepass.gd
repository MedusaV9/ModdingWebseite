extends TestCase
## W13B/REISEPASS — Reisepass 2.0 (Doc H §2.2) + Abflugtafel/Boarding-Pass
## (Doc H §2.4): Flip-Zustandsmaschine, Passfoto-Persistenz (setzen →
## speichern → laden über den echten GameState/SaveSchema-Pfad), MRZ-Gag
## (deterministisch, nur A–Z/<), Stempel-Ableitung EXAKT aus
## vacation.visited (+ "5.0 UMZUG" aus meta.importedFrom), runde Foto-Maske,
## Flap-Sequenz (pur, deterministisch, injizierte Zeit), Boarding-Pass-Daten
## und der unveränderte Buchungs-Flow der Reise-App.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW := 1768478400000

var _seq := 0


## GameState-Double: dotted get/set + update(mutator) wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}
	var slices_notified: Array[String] = []
	var clock := FakeClock.new()

	func _init() -> void:
		s = SaveSchema.default_state(1768478400000)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


class FakeClock:
	extends RefCounted
	var ms := 1768478400000

	func now_ms() -> int:
		return ms


## ------------------------------------------------------ MRZ-Gag (pur)


func test_mrz_deterministisch_und_zeichensatz() -> void:
	var a: Array = MrzGag.zeilen("Anna-Lena Bauer", "Flauschi")
	var b: Array = MrzGag.zeilen("Anna-Lena Bauer", "Flauschi")
	assert_eq(a, b, "gleiche Namen ⇒ byte-gleiche MRZ (deterministisch)")
	assert_eq(a.size(), 2, "genau zwei MRZ-Zeilen")
	for zeile: String in a:
		assert_eq(zeile.length(), MrzGag.LINE_LEN, "Zeile exakt %d Zeichen" % MrzGag.LINE_LEN)
		for i in zeile.length():
			var c := zeile.unicode_at(i)
			assert_true((c >= 65 and c <= 90) or c == 60, "nur A–Z/< erlaubt, fand '%s'" % zeile[i])
	assert_true(str(a[0]).contains("FLAUSCHI"), "Zeile 1 nennt den Spitznamen")
	assert_true(str(a[0]).contains("ANNA<LENA"), "Bindestrich wird zu <")


func test_mrz_umlaut_transliteration_und_fallbacks() -> void:
	assert_eq(MrzGag.sanitize("Bär Höß Müde"), "BAER<HOESS<MUEDE", "Umlaute amtlich AE/OE/UE/SS")
	assert_eq(MrzGag.sanitize("123 !?"), "<", "Ziffern/Sonderzeichen fliegen raus")
	var leer: Array = MrzGag.zeilen("", "")
	assert_true(str(leer[0]).contains("GOOBY"), "leerer Spitzname → GOOBY-Fallback")
	assert_true(str(leer[0]).contains("FLAUSCHFREUND"), "leerer Name → Quatsch-Fallback")
	var anders: Array = MrzGag.zeilen("Anna", "Mampfred")
	assert_ne(anders[0], MrzGag.zeilen("Anna", "Flauschi")[0], "anderer Spitzname ⇒ andere Zeile")


func test_mrz_zeile_2_aus_quatsch_pool() -> void:
	var zeile := MrzGag.zeile_2("Anna", "Flauschi")
	var woerter := zeile.replace("<", " ").strip_edges().split(" ", false)
	assert_true(woerter.size() >= 2, "mindestens 2 Quatsch-Wörter sichtbar")
	for wort in woerter:
		var im_pool := false
		for kandidat: String in MrzGag.QUATSCH:
			if kandidat.begins_with(wort) or wort == kandidat:
				im_pool = true
				break
		assert_true(im_pool, "Wort '%s' stammt aus dem Quatsch-Pool" % wort)


## ------------------------------------------------------ Flip-Karte


func test_flip_zustandsmaschine_pur() -> void:
	assert_eq(PassportCard.naechste_seite(PassportCard.SEITE_VORNE), PassportCard.SEITE_HINTEN)
	assert_eq(PassportCard.naechste_seite(PassportCard.SEITE_HINTEN), PassportCard.SEITE_VORNE)
	assert_eq(PassportCard.naechste_seite("quatsch"), PassportCard.SEITE_VORNE, "Junk heilt")


func test_flip_karte_reduced_motion_harter_wechsel() -> void:
	var gs := FakeGameState.new()
	var karte := PassportCard.new()
	karte.gs = gs
	karte.reduziert_override = true
	tree.root.add_child(karte)
	await wait_frames(1)
	var vorn: Control = karte.find_child("Vorderseite", true, false)
	var hinten: Control = karte.find_child("Rueckseite", true, false)
	assert_true(vorn != null and vorn.visible, "Start: Vorderseite sichtbar")
	assert_true(hinten != null and not hinten.visible, "Start: Rückseite versteckt")
	var seiten: Array = []
	karte.seite_gewechselt.connect(func(seite: String) -> void: seiten.append(seite))
	karte.flip()
	assert_eq(karte.seite, PassportCard.SEITE_HINTEN, "Flip 1 → hinten")
	assert_true(hinten.visible and not vorn.visible, "Reduced Motion = sofortiger Wechsel")
	karte.flip()
	assert_eq(karte.seite, PassportCard.SEITE_VORNE, "Flip 2 → wieder vorn")
	assert_true(vorn.visible and not hinten.visible, "Vorderseite zurück")
	assert_eq(seiten, ["hinten", "vorne"], "Signal je Flip")
	tree.root.remove_child(karte)
	karte.free()


func test_flip_karte_animiert_ueber_tween() -> void:
	var gs := FakeGameState.new()
	var karte := PassportCard.new()
	karte.gs = gs
	karte.reduziert_override = false
	tree.root.add_child(karte)
	await wait_frames(1)
	karte.flip()
	assert_eq(karte.seite, PassportCard.SEITE_HINTEN, "Zustand wechselt sofort")
	var hinten: Control = karte.find_child("Rueckseite", true, false)
	var fertig := await wait_until(func() -> bool: return hinten.visible, 3000)
	assert_true(fertig, "Tween tauscht die Seite in der Flip-Mitte")
	fertig = await wait_until(func() -> bool: return absf(karte.scale.x - 1.0) < 0.001, 3000)
	assert_true(fertig, "Karte dreht auf Scale 1 zurück")
	tree.root.remove_child(karte)
	karte.free()


## ------------------------------------------------------ Passfoto


func test_passfoto_setzen_speichern_laden() -> void:
	# ECHTER GameState-Roundtrip: setzen → save_now → frisch laden.
	_seq += 1
	var dir := "user://w13b_tests/pass_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW)
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	assert_eq(PassportCard.passfoto_von(gs.state()), "", "frischer Save: kein Passfoto")
	PassportCard.setze_passfoto(gs, "user://fotos/foto_123.png")
	assert_true(gs.save_now(), "Save schreibt")
	tree.root.remove_child(gs)
	gs.free()
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(NOW + 1000)
	gs2.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs2)
	assert_eq(
		PassportCard.passfoto_von(gs2.state()),
		"user://fotos/foto_123.png",
		"Passfoto überlebt speichern → laden (additiver profile-Key)"
	)
	tree.root.remove_child(gs2)
	gs2.free()


func test_passfoto_slot_und_picker() -> void:
	# Echte PNG anlegen, damit Slot + Picker wirklich Texturen laden.
	var dir := "user://w13b_tests/fotos_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var pfad := dir + "/knips_1.png"
	var bild := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	bild.fill(Color(0.9, 0.5, 0.3))
	assert_eq(bild.save_png(pfad), OK, "Test-PNG geschrieben")
	var gs := FakeGameState.new()
	gs.set_value("city.fotos", [{"pfad": pfad, "at": NOW, "ort": "stadt"}])
	var karte := PassportCard.new()
	karte.gs = gs
	karte.reduziert_override = true
	tree.root.add_child(karte)
	await wait_frames(1)
	assert_true(
		karte.find_child("PassPortrait", true, false) is GoobyPreview,
		"ohne Passfoto: echtes 3D-Porträt im Slot"
	)
	var btn: Button = karte.find_child("FotoAendernBtn", true, false)
	assert_true(btn != null, "„Foto ändern“-Knopf da")
	btn.pressed.emit()
	await wait_frames(1)
	var picker := tree.root.get_node_or_null("PassFotoPicker")
	assert_true(picker != null, "Galerie-Picker öffnet")
	var wahl: Button = picker.find_child("FotoWahl_knips_1", true, false)
	assert_true(wahl != null, "Galerie-Foto als Kachel (GalerieLogic-API)")
	wahl.pressed.emit()
	await wait_frames(1)
	assert_eq(PassportCard.passfoto_von(gs.state()), pfad, "Wahl persistiert im profile-Slice")
	assert_true(gs.slices_notified.has("profile"), "Slice-Signal gefeuert")
	var foto: TextureRect = karte.find_child("PassFoto", true, false)
	assert_true(foto != null, "gewähltes Foto ersetzt das Porträt")
	if foto != null:
		assert_almost(foto.rotation_degrees, -2.0, 0.001, "bürokratisch schief (−2°)")
	assert_true(karte.find_child("PassPortrait", true, false) == null, "3D-Porträt raus, Foto rein")
	assert_true(not is_instance_valid(picker) or picker.is_queued_for_deletion(), "Picker schließt")
	# Zurück zum Standard-Porträt.
	btn.pressed.emit()
	await wait_frames(1)
	var picker2 := tree.root.get_node_or_null("PassFotoPicker")
	var standard: Button = picker2.find_child("PickerStandard", true, false)
	assert_true(standard != null, "Standard-Knopf, sobald ein Foto klebt")
	standard.pressed.emit()
	await wait_frames(1)
	assert_eq(PassportCard.passfoto_von(gs.state()), "", "Standard leert den Save-Wert")
	assert_true(karte.find_child("PassPortrait", true, false) is GoobyPreview, "3D-Porträt zurück")
	tree.root.remove_child(karte)
	karte.free()
	await wait_frames(1)


func test_runde_maske_schneidet_kreis() -> void:
	var bild := Image.create(40, 24, false, Image.FORMAT_RGBA8)
	bild.fill(Color(0.2, 0.4, 0.8, 1.0))
	var maske := PassportCard.runde_maske(bild)
	assert_eq(maske.get_width(), 24, "quadratischer Center-Crop (kurze Kante)")
	assert_eq(maske.get_height(), 24, "quadratisch")
	assert_almost(maske.get_pixel(0, 0).a, 0.0, 0.001, "Ecke transparent")
	assert_almost(maske.get_pixel(23, 23).a, 0.0, 0.001, "Gegenecke transparent")
	assert_almost(maske.get_pixel(12, 12).a, 1.0, 0.001, "Mitte deckend")


## ------------------------------------------------------ Stempelseite


func test_stempel_ableitung_aus_visited_exakt() -> void:
	var state := SaveSchema.default_state(NOW)
	assert_eq(PassportCard.stempel_von(state).size(), 0, "frischer Save: keine Stempel")
	state["vacation"]["visited"] = {"space": true, "beach": true, "mond": true, "harbor": "ja"}
	state["vacation"]["archive"] = [
		{"destId": "beach", "dayIndex": 1, "variant": 0, "atMs": NOW - 1000},
		{"destId": "beach", "dayIndex": 2, "variant": 1, "atMs": NOW + 500},
		{"destId": "space", "dayIndex": 1, "variant": 0, "atMs": "junk"},
	]
	var stempel := PassportCard.stempel_von(state)
	assert_eq(stempel.size(), 2, "NUR echte visited=true-Katalogziele stempeln")
	assert_eq(str(stempel[0]["id"]), "beach", "UI-Reihenfolge (ReiseLogic.ZIELE)")
	assert_eq(str(stempel[1]["id"]), "space", "space nach beach")
	assert_eq(int(stempel[0]["at_ms"]), NOW + 500, "Datum = jüngste Archiv-Karte des Ziels")
	assert_eq(int(stempel[1]["at_ms"]), 0, "ohne (brauchbares) Archiv kein Datum")
	assert_eq(str(stempel[0]["glyph"]), "⛱", "Ziel-Glyph aus der Tabelle")
	for eintrag: Dictionary in stempel:
		var drehung := float(eintrag["drehung"])
		assert_true(drehung >= -6.0 and drehung <= 6.0, "Stempel-Drehung in ±6°")
	assert_eq(
		PassportCard.stempel_drehung("beach"),
		PassportCard.stempel_drehung("beach"),
		"Drehung deterministisch"
	)


func test_stempel_umzug_aus_migrations_flag() -> void:
	var state := SaveSchema.default_state(NOW)
	state["meta"]["importedFrom"] = "web-v4"
	state["meta"]["importedAt"] = NOW - 5000
	state["vacation"]["visited"] = {"beach": true}
	var stempel := PassportCard.stempel_von(state)
	assert_eq(stempel.size(), 2, "Reise-Stempel + Umzugs-Stempel")
	var umzug: Dictionary = stempel[1]
	assert_eq(str(umzug["id"]), "umzug", "Sonderstempel zuletzt")
	assert_eq(str(umzug["name_key"]), "reisepass.stempel_umzug", "„5.0 UMZUG“-Key")
	assert_eq(int(umzug["at_ms"]), NOW - 5000, "Datum = Import-Zeitpunkt")
	assert_eq(I18nService.t("reisepass.stempel_umzug"), "5.0 UMZUG", "DE-Text sitzt")


func test_stempelseite_und_mrz_im_baum() -> void:
	var gs := FakeGameState.new()
	gs.s["vacation"]["visited"] = {"beach": true, "space": true}
	gs.s["meta"]["importedFrom"] = "web-v4"
	gs.s["meta"]["playerName"] = "Anna"
	var karte := PassportCard.new()
	karte.gs = gs
	karte.reduziert_override = true
	tree.root.add_child(karte)
	await wait_frames(1)
	assert_true(karte.find_child("Stempel_beach", true, false) != null, "Strand-Stempel")
	assert_true(karte.find_child("Stempel_space", true, false) != null, "Weltraum-Stempel")
	assert_true(karte.find_child("Stempel_umzug", true, false) != null, "5.0-UMZUG-Stempel")
	var mrz1: Label = karte.find_child("MrzZeile1", true, false)
	var mrz2: Label = karte.find_child("MrzZeile2", true, false)
	assert_true(mrz1 != null and mrz2 != null, "zwei MRZ-Zeilen")
	if mrz1 != null:
		assert_eq(mrz1.text, MrzGag.zeile_1("Anna", "Gooby"), "MRZ aus Name/Spitzname")
	tree.root.remove_child(karte)
	karte.free()


## ------------------------------------------------------ Flap-Board (pur)


func test_flap_zeichen_schritt() -> void:
	assert_eq(FlapBoard.zeichen_schritt("A", "A"), "A", "am Ziel bleibt stehen")
	assert_eq(FlapBoard.zeichen_schritt("A", "C"), "B", "einen Schritt weiter")
	assert_eq(FlapBoard.zeichen_schritt("Z", "A"), "0", "läuft zyklisch durchs Alphabet")
	assert_eq(FlapBoard.zeichen_schritt("-", "B"), " ", "Alphabet-Ende wickelt zum Anfang")
	assert_eq(FlapBoard.zeichen_schritt("ᴳ", "X"), "X", "Fremdzeichen schnappt sofort")


func test_flap_sequenz_deterministisch() -> void:
	var a := FlapBoard.flap_sequenz("AB", "CA")
	var b := FlapBoard.flap_sequenz("AB", "CA")
	assert_eq(a, b, "gleiche Ein-/Ausgabe ⇒ identische Sequenz")
	assert_true(a.size() > 0, "es flappt überhaupt")
	assert_eq(str(a[a.size() - 1]), "CA", "letzter Frame = Zieltext")
	for frame: String in a:
		assert_eq(frame.length(), 2, "alle Frames gleich breit")
	assert_eq(str(a[0]), "BC", "Frame 1: beide Stellen je ein Flap weiter")
	var leer := FlapBoard.flap_sequenz("GLEICH", "GLEICH")
	assert_eq(leer.size(), 0, "ohne Änderung keine Frames")
	var kurz := FlapBoard.flap_sequenz("A", "ABC")
	assert_eq(str(kurz[kurz.size() - 1]), "ABC", "kürzerer Start wird aufgefüllt")


func test_flap_board_zeilen_und_injizierte_zeit() -> void:
	var board := FlapBoard.new()
	board.reduziert_override = false
	tree.root.add_child(board)
	board.set_process(false)  # Zeit kommt NUR über advance() (injiziert)
	await wait_frames(1)
	var zeilen := [{"ziel": "Glitzermeer", "abflug": "3 TAGE", "status": "BOARDING"}]
	board.set_zeilen(zeilen)
	assert_false(board.fertig(), "Animation steht aus")
	var ziel_text := FlapBoard.zeile_text_von(zeilen[0])
	assert_ne(board.zeile_text(0), ziel_text, "vor advance() noch nicht am Ziel")
	board.advance(10.0)
	assert_true(board.fertig(), "genug injizierte Zeit ⇒ fertig")
	assert_eq(board.zeile_text(0), ziel_text, "Zeile zeigt Ziel|Abflug|Status")
	assert_true(ziel_text.begins_with("GLITZERMEER"), "Board schreibt GROSS")
	# Zielwechsel flippt erneut; Reduced Motion springt sofort.
	board.reduziert_override = true
	board.set_zeilen([{"ziel": "Weltraum", "abflug": "4 TAGE", "status": "ZU TEUER"}])
	assert_true(board.fertig(), "Reduced Motion: sofort fertig")
	assert_true(board.zeile_text(0).begins_with("WELTRAUM"), "harter Wechsel")
	tree.root.remove_child(board)
	board.free()


func test_flap_status_deterministisch() -> void:
	assert_eq(
		FlapBoard.status_key("beach", false),
		"reisepass.tafel.status_zu_teuer",
		"pleite schlägt jeden Gag"
	)
	var key := FlapBoard.status_key("beach", true)
	assert_eq(key, FlapBoard.status_key("beach", true), "Status je Ziel stabil")
	assert_true(key.begins_with("reisepass.tafel.status_"), "Key aus dem Gag-Pool")
	assert_true(I18nService.has_key(key), "Status-String existiert")


## ------------------------------------------------------ Boarding-Pass


func test_boarding_pass_daten_korrekt() -> void:
	var paket := BoardingPass.daten("beach", NOW)
	assert_eq(str(paket["ziel_id"]), "beach")
	assert_eq(str(paket["name_key"]), "travel.ziel.beach", "Zielname über den Reise-Key")
	assert_eq(int(paket["tage"]), 3, "Katalogdauer verbatim")
	assert_eq(int(paket["datum_ms"]), NOW, "injizierte Zeit landet im Paket")
	assert_true(BoardingPass.daten("mond", NOW).is_empty(), "unbekanntes Ziel ⇒ {}")
	var code := str(paket["barcode"])
	assert_eq(code, BoardingPass.barcode("beach"), "Barcode deterministisch je Ziel")
	assert_eq(code.length(), BoardingPass.BARCODE_LAENGE, "Barcode-Länge fix")
	assert_ne(code, BoardingPass.barcode("space"), "anderes Ziel ⇒ anderer Barcode")
	for i in code.length():
		assert_true(BoardingPass.BARCODE_ZEICHEN.has(code[i]), "nur Strich-Glyphen")
	assert_eq(I18nService.t("reisepass.pass.gate_wert"), "3¾", "Gate-Gag 3¾")


func test_boarding_pass_ui_und_gute_reise() -> void:
	var gerufen: Array = []
	var layer := BoardingPass.oeffne(tree.root, "beach", NOW, func() -> void: gerufen.append(true))
	await wait_frames(1)
	assert_true(layer.find_child("Barcode", true, false) != null, "Barcode-Label da")
	var ziel: Label = layer.find_child("PassWertZiel", true, false)
	assert_true(ziel != null, "Ziel-Feld da")
	if ziel != null:
		assert_eq(ziel.text, I18nService.t("travel.ziel.beach"), "Zielname aufgedruckt")
	var knopf: Button = layer.find_child("GuteReiseBtn", true, false)
	assert_true(knopf != null, "„Gute Reise!“-Knopf da")
	knopf.pressed.emit()
	assert_eq(gerufen.size(), 1, "Knopf ruft den Cutscene-Callback")
	assert_true(layer.is_queued_for_deletion(), "Karte räumt sich weg")
	await wait_frames(1)


## ------------------------------------------------------ Reise-App-Flow


func test_reise_app_tafel_und_buchen_unveraendert() -> void:
	var gs := FakeGameState.new()
	gs.set_value("economy.coins", 500)
	var app := ReiseApp.new()
	app.gs = gs
	tree.root.add_child(app)
	await wait_frames(1)
	assert_true(app.find_child("Abflugtafel", true, false) is FlapBoard, "Tafel überm Board")
	var knoepfe := 0
	for kind in app.get_children():
		if kind is Button:
			knoepfe += 1
	assert_eq(knoepfe, ReiseLogic.ZIELE.size(), "alle 9 Ziele buchbar wie zuvor")
	# Buchen: Geldabzug + Taxi-Ruf laufen unverändert über TaxiLogic/Economy.
	app._on_buchen("beach")
	var taxi := CityState.taxi_slice(gs)
	assert_eq(str(taxi["state"]), TaxiLogic.STATE_GERUFEN, "Taxi gerufen")
	assert_eq(str(taxi["zielId"]), "beach", "Ziel gebucht")
	assert_eq(int(gs.get_value("economy.coins", 0)), 500 - 180 - 10, "Preis + Taxi abgebucht")
	tree.root.remove_child(app)
	app.free()
	await wait_frames(1)


func test_reise_app_einsteigen_zeigt_boarding_pass() -> void:
	var gs := FakeGameState.new()
	gs.set_value("economy.coins", 500)
	var app := ReiseApp.new()
	app.gs = gs
	var geoeffnet: Array = []
	app.boarding_oeffner = func(ziel_id: String, _weiter: Callable) -> void:
		geoeffnet.append(ziel_id)
	tree.root.add_child(app)
	await wait_frames(1)
	app._on_buchen("beach")
	# Taxi ist da: Uhr hinter die Ankunft drehen (60-s-Fenster läuft).
	var taxi := CityState.taxi_slice(gs)
	var res := TaxiLogic.tick(taxi, int(taxi["ankunftAt"]) + 1000)
	CityState.save_taxi_slice(gs, res["slice"])
	gs.clock.ms = int(taxi["ankunftAt"]) + 1000
	app._on_einsteigen()
	assert_eq(geoeffnet, ["beach"], "Einsteigen öffnet den Boarding-Pass fürs Ziel")
	assert_eq(
		str(CityState.taxi_slice(gs)["state"]),
		TaxiLogic.STATE_FAHRT,
		"Taxi-Zustand wie zuvor (Flow unverändert)"
	)
	tree.root.remove_child(app)
	app.free()
	await wait_frames(1)

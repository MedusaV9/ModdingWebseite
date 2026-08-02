extends TestCase
## W14/DLCHUB — DLC-Hub in den Settings: dlcs.json schema-valide + Cover
## vorhanden, Status-Ableitung (Ranch gekauft / nicht gekauft / Level < 15),
## Routen-/Aktions-Mapping, DE↔EN-Parität der Pack-Texte und Screen-Smoke
## (3 Cover-Karten + Detail-Sheets). G5/P24+P25: alle drei Einträge sind
## spielbar (goo_und_bye → Angebot, mcgooby → freie Probeschicht; das
## Kauf-Gate G6/MCGOOBY-B sitzt DAHINTER: Angebot nach der Demo-Schicht) —
## der Kommt-bald-Pfad wird über einen synthetischen Eintrag bzw. eine
## Registry-Attrappe abgedeckt; Status-/Kauf-Ableitung der DLCs selbst
## testen test_dlc_goobye.gd / test_dlc_mcgooby.gd /
## test_dlc_mcgooby_welle_b.gd.

const PACK_DATEI := "res://content/dlc/data/dlcs.json"
const ERWARTETE_IDS: Array[String] = ["ranch", "goo_und_bye", "mcgooby"]


## GameState-Double: dotted get_value/set_value wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

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


func _gs(level: int, gekauft: bool) -> FakeGameState:
	var gs := FakeGameState.new()
	gs.set_value("progression.level", level)
	gs.set_value("ranch.gekauft", gekauft)
	return gs


func _items() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_DATEI))
	if not (parsed is Dictionary):
		return []
	var items: Variant = (parsed as Dictionary).get("items", [])
	return items if items is Array else []


## ------------------------------------------------------------ Pack-Schema


func test_dlcs_json_schema_valide() -> void:
	assert_true(FileAccess.file_exists(PACK_DATEI), "dlcs.json existiert")
	var items := _items()
	assert_eq(items.size(), 3, "genau 3 DLC-Einträge")
	for i in items.size():
		var dlc: Dictionary = items[i]
		assert_eq(str(dlc.get("id", "")), ERWARTETE_IDS[i], "Reihenfolge ranch/goo_und_bye/mcgooby")
		for feld: String in [
			"name", "status", "cover", "teaser_de", "teaser_en", "unlock_de", "unlock_en"
		]:
			assert_true(
				dlc.get(feld) is String and not str(dlc[feld]).is_empty(),
				"%s: Pflichtfeld %s gefüllt" % [dlc.get("id"), feld]
			)
		assert_true(
			str(dlc["status"]) in ["verfuegbar", "kommt_bald"],
			"%s: status verfuegbar|kommt_bald" % dlc.get("id")
		)
		assert_true(dlc.get("route") is String, "%s: route ist String" % dlc.get("id"))
	assert_eq(str((items[0] as Dictionary)["status"]), "verfuegbar", "Ranch ist verfügbar")
	assert_ne(str((items[0] as Dictionary)["route"]), "", "Ranch-Route gesetzt")
	# G5/P24: „Goo und Bye“ ist per Pack-Update-Mechanismus verfügbar.
	assert_eq(str((items[1] as Dictionary)["status"]), "verfuegbar", "Goo und Bye verfügbar")
	assert_eq(str((items[1] as Dictionary)["route"]), "goobye_angebot", "Goobye-Route gesetzt")
	# G5/P25: McGooby Welle A — Probeschicht direkt spielbar.
	assert_eq(str((items[2] as Dictionary)["status"]), "verfuegbar", "mcgooby verfügbar")
	assert_eq(str((items[2] as Dictionary)["route"]), "mcgooby_schicht", "McGooby-Route gesetzt")
	# pack.json deklariert die Domain (Pack-updatebar, Ranch-Blaupause).
	var meta: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/dlc/pack.json")
	)
	assert_true(meta is Dictionary and str((meta as Dictionary).get("id", "")) == "dlc")
	assert_true(
		(
			(meta as Dictionary).get("domains") is Array
			and ((meta as Dictionary)["domains"] as Array).has("dlcs")
		),
		"pack.json deklariert Domain dlcs"
	)


func test_cover_dateien_existieren() -> void:
	for dlc: Dictionary in _items():
		var cover := str(dlc.get("cover", ""))
		assert_true(cover.begins_with("res://assets/dlc/"), "Cover liegt unter assets/dlc/")
		assert_true(
			FileAccess.file_exists(cover), "%s: Cover-Datei fehlt (%s)" % [dlc.get("id"), cover]
		)


func test_de_en_paritaet_der_pack_texte() -> void:
	for dlc: Dictionary in _items():
		var id := str(dlc.get("id", ""))
		for feld: String in ["teaser", "unlock"]:
			assert_true(not str(dlc.get(feld + "_de", "")).is_empty(), "%s: %s_de" % [id, feld])
			assert_true(not str(dlc.get(feld + "_en", "")).is_empty(), "%s: %s_en" % [id, feld])
		var de: Array = dlc.get("features_de", [])
		var en: Array = dlc.get("features_en", [])
		assert_true(de.size() >= 3 and de.size() <= 4, "%s: 3-4 Stichpunkte (DE)" % id)
		assert_eq(de.size(), en.size(), "%s: Features DE↔EN paritätisch" % id)
		for feature: Variant in de + en:
			assert_true(
				feature is String and not str(feature).is_empty(), "%s: Feature gefüllt" % id
			)


## ------------------------------------------------------ Status & Aktionen


func test_status_ableitung_ranch() -> void:
	DlcKatalog.reset_cache()
	var ranch := DlcKatalog.eintrag("ranch")
	assert_false(ranch.is_empty(), "Ranch-Eintrag über den Katalog lesbar")
	assert_eq(
		DlcKatalog.status_fuer(ranch, _gs(20, true)),
		DlcKatalog.STATUS_INSTALLIERT,
		"gekauft → installiert"
	)
	assert_eq(
		DlcKatalog.status_fuer(ranch, _gs(15, false)),
		DlcKatalog.STATUS_VERFUEGBAR,
		"Level 15, nicht gekauft → verfügbar"
	)
	assert_eq(
		DlcKatalog.status_fuer(ranch, _gs(14, false)),
		DlcKatalog.STATUS_GESPERRT,
		"Level < 15 → gesperrt"
	)
	# Kommt-bald-Zweig über synthetischen Eintrag (im Pack gibt es seit
	# G5/P25 keinen mehr — der Mechanismus bleibt für künftige DLCs).
	var bald := {"id": "zukunft", "status": "kommt_bald"}
	assert_eq(
		DlcKatalog.status_fuer(bald, _gs(99, true)),
		DlcKatalog.STATUS_KOMMT_BALD,
		"kommt_bald bleibt kommt_bald — egal welcher Spielstand"
	)
	# G6/MCGOOBY-B: Kauf-Gate — ungekauft VERFÜGBAR (nie gesperrt, die
	# Probeschicht ist ab Level 1 frei), gekauft INSTALLIERT.
	assert_eq(
		DlcKatalog.status_fuer(DlcKatalog.eintrag("mcgooby"), _gs(1, false)),
		DlcKatalog.STATUS_VERFUEGBAR,
		"mcgooby ungekauft: Probeschicht frei — verfügbar ab Level 1"
	)
	var mc_gekauft := _gs(1, false)
	mc_gekauft.set_value("mcgooby.gekauft", true)
	assert_eq(
		DlcKatalog.status_fuer(DlcKatalog.eintrag("mcgooby"), mc_gekauft),
		DlcKatalog.STATUS_INSTALLIERT,
		"mcgooby gekauft → installiert"
	)


func test_aktions_und_routen_mapping() -> void:
	DlcKatalog.reset_cache()
	var ranch := DlcKatalog.eintrag("ranch")
	assert_eq(str(ranch.get("route", "")), "ranch_angebot", "Ansehen-Ziel: Ranch-Angebots-Flow")
	assert_eq(DlcKatalog.aktion_fuer(ranch, _gs(20, true)), DlcKatalog.AKTION_HOF)
	assert_eq(DlcKatalog.aktion_fuer(ranch, _gs(15, false)), DlcKatalog.AKTION_ANGEBOT)
	assert_eq(DlcKatalog.aktion_fuer(ranch, _gs(10, false)), DlcKatalog.AKTION_GESPERRT)
	# G5/P24: „Goo und Bye“ hängt am Ranch-Muster (Angebot ab Level 12).
	var goobye := DlcKatalog.eintrag("goo_und_bye")
	assert_eq(str(goobye.get("route", "")), "goobye_angebot", "Goobye-Angebots-Route")
	assert_eq(DlcKatalog.aktion_fuer(goobye, _gs(12, false)), DlcKatalog.AKTION_ANGEBOT)
	assert_eq(DlcKatalog.aktion_fuer(goobye, _gs(11, false)), DlcKatalog.AKTION_GESPERRT)
	# G6/MCGOOBY-B: ungekauft → Angebots-Aktion (führt in die FREIE
	# Probeschicht, das Angebot kommt nach der Demo); gekauft → Hof/Schicht.
	var mcgooby := DlcKatalog.eintrag("mcgooby")
	assert_eq(str(mcgooby.get("route", "")), "mcgooby_schicht", "mcgooby: Schicht-Route")
	assert_eq(DlcKatalog.aktion_fuer(mcgooby, _gs(1, false)), DlcKatalog.AKTION_ANGEBOT)
	var mc_gekauft := _gs(1, false)
	mc_gekauft.set_value("mcgooby.gekauft", true)
	assert_eq(DlcKatalog.aktion_fuer(mcgooby, mc_gekauft), DlcKatalog.AKTION_HOF)
	# Kommt-bald-Aktions-Zweig über synthetischen Eintrag.
	var zukunft := {"id": "zukunft", "status": "kommt_bald"}
	assert_eq(DlcKatalog.aktion_fuer(zukunft, _gs(99, false)), DlcKatalog.AKTION_BALD)


func test_unlock_text_ranch_aus_balance_pack() -> void:
	DlcKatalog.reset_cache()
	var text := DlcKatalog.unlock_text(DlcKatalog.eintrag("ranch"))
	assert_true(text.contains(str(RanchKatalog.freischalt_level())), "Level eingesetzt")
	assert_true(text.contains(str(RanchKatalog.preis())), "Preis eingesetzt")
	assert_false(text.contains("{"), "keine offenen Platzhalter")
	# G6/MCGOOBY-B: auch McGooby füllt {level}/{preis} aus dem Menü-Pack.
	var mc_text := DlcKatalog.unlock_text(DlcKatalog.eintrag("mcgooby"))
	assert_true(mc_text.contains(str(McGoobyKatalog.freischalt_level())), "McGooby-Level drin")
	assert_true(mc_text.contains(str(McGoobyKatalog.preis())), "McGooby-Preis drin")
	assert_false(mc_text.contains("{"), "keine offenen Platzhalter (mcgooby)")


## ------------------------------------------------------------ Screen-Smoke


func test_screen_smoke_drei_karten_und_details() -> void:
	DlcKatalog.reset_cache()
	var screen := DlcScreen.new()
	screen.gs_override = _gs(20, false)
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	var karten := screen.karten()
	assert_eq(karten.size(), 3, "3 Cover-Karten")
	for i in karten.size():
		assert_eq(String(karten[i].name), "DlcKarte_" + ERWARTETE_IDS[i])
		var cover: TextureRect = karten[i].find_child("Cover", true, false)
		assert_true(cover != null and cover.texture != null, "Cover-Textur geladen")
		var ribbon: Label = karten[i].find_child("Ribbon", true, false)
		assert_true(ribbon != null and not ribbon.text.is_empty(), "Status-Ribbon sitzt")
	# Ranch verfügbar → Detail mit „Zur Ranch“-Knopf (Angebots-Flow).
	var detail := screen.oeffne_detail("ranch")
	assert_true(detail != null, "Detail-Sheet öffnet")
	var knopf: Button = detail.get_meta(DlcScreen.META_AKTION, null)
	assert_true(knopf != null and not knopf.disabled, "Aktions-Knopf aktiv")
	assert_eq(knopf.text, I18nService.t("dlc.knopf.zur_ranch"))
	detail.queue_free()
	# G6/MCGOOBY-B: ungekauft → Angebots-Aktion, deren Knopf in die FREIE
	# Probeschicht führt (das Kauf-Angebot kommt nach der Demo-Schicht).
	var schicht := screen.oeffne_detail("mcgooby")
	var schicht_knopf: Button = schicht.get_meta(DlcScreen.META_AKTION, null)
	assert_true(schicht_knopf != null and not schicht_knopf.disabled, "Schicht-Knopf aktiv")
	assert_eq(schicht_knopf.text, I18nService.t("dlc_mcgooby.knopf.schicht"))
	schicht.queue_free()
	screen.queue_free()
	await wait_frames(1)


## Kommt-bald-Sheet (Hammer-Gag statt Knopf) über eine Registry-Attrappe —
## seit G5/P25 trägt kein echter Pack-Eintrag mehr diesen Status.
class FakeRegistry:
	extends RefCounted
	var items: Array = []

	func get_items(_domain: String) -> Array:
		return items


func test_screen_kommt_bald_zeigt_hammer_hinweis() -> void:
	var registry := FakeRegistry.new()
	registry.items = [
		{
			"id": "zukunft",
			"name": "Zukunft",
			"status": "kommt_bald",
			"cover": "res://assets/dlc/mcgooby.png",
			"teaser_de": "Bald.",
			"teaser_en": "Soon.",
			"unlock_de": "In Arbeit",
			"unlock_en": "In the works",
			"features_de": ["Eins", "Zwei", "Drei"],
			"features_en": ["One", "Two", "Three"],
			"route": ""
		}
	]
	DlcKatalog.registry_override = registry
	DlcKatalog.reset_cache()
	var screen := DlcScreen.new()
	screen.gs_override = _gs(20, false)
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	var bald := screen.oeffne_detail("zukunft")
	var hinweis: Label = bald.get_meta(DlcScreen.META_BALD, null)
	assert_true(hinweis != null, "Kommt-bald-Hinweis sitzt")
	if hinweis != null:
		assert_true(hinweis.text.contains("🔨"), "Hammer-Gag im Hinweis")
	assert_false(bald.has_meta(DlcScreen.META_AKTION), "kein Aktions-Knopf bei kommt_bald")
	bald.queue_free()
	screen.queue_free()
	DlcKatalog.registry_override = null
	DlcKatalog.reset_cache()
	await wait_frames(1)


func test_settings_sektion_baut_karte_und_knopf() -> void:
	DlcKatalog.reset_cache()
	var host := Control.new()
	tree.root.add_child(host)
	var sections := VBoxContainer.new()
	host.add_child(sections)
	DlcSektion.baue(host, sections, 1.0, 1.0)
	await wait_frames(1)
	var card: PanelContainer = sections.get_node_or_null("SectionDlc")
	assert_true(card != null, "SectionDlc-Karte hängt in der Sektionsliste")
	var knopf: Button = card.find_child("DlcButton", true, false)
	assert_true(knopf != null, "Bibliothek-Knopf existiert")
	assert_eq(knopf.text, I18nService.t("dlc.settings_knopf"))
	var info: Label = card.find_child("DlcInfo", true, false)
	assert_true(info != null, "Info-Zeile existiert")
	# G5/P24+P25: alle drei Einträge spielbar, nichts mehr in Arbeit.
	assert_eq(
		info.text,
		I18nService.t("dlc.settings_info", {"spielbar": 3, "bald": 0}),
		"Zähler: 3 spielbar · 0 in Arbeit"
	)
	host.queue_free()
	await wait_frames(1)


func test_screen_ranch_gekauft_zeigt_installiert_und_losreiten() -> void:
	DlcKatalog.reset_cache()
	var screen := DlcScreen.new()
	screen.gs_override = _gs(20, true)
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	var ribbon: Label = screen.karten()[0].find_child("Ribbon", true, false)
	assert_eq(ribbon.text, I18nService.t("dlc.ribbon.installiert"), "INSTALLIERT-Ribbon")
	var detail := screen.oeffne_detail("ranch")
	var knopf: Button = detail.get_meta(DlcScreen.META_AKTION, null)
	assert_true(knopf != null, "Losreiten-Knopf existiert")
	assert_eq(knopf.text, I18nService.t("dlc.knopf.losreiten"), "„Losreiten!“ nach dem Kauf")
	detail.queue_free()
	screen.queue_free()
	await wait_frames(1)

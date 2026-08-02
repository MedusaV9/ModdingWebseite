extends TestCase
## G6/DLC-LOAD — Datengetriebene DLC-Ladekarten: Zuordnung Ort → Karte
## (Betreten schlaegt Rueckweg), Fallback auf die Standard-Karte, Assets
## vorhanden, Tipp-Pools (6+ je DLC, DE/EN paritaetisch, Moehren-Gag) und
## die Veil-Integration — DLC-Cover/-Motiv/-Farbstimmung/-Texte auf der
## BESTEHENDEN Karte, Ranch-Vollbildschirm + Minigame-Hint behalten
## Vorrang, W1a-Contract (cover/reveal awaitbar) bleibt unangetastet.

const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")


func test_dlc_fuer_ziel_zuordnung() -> void:
	assert_eq(DlcLoadingKarten.dlc_fuer_ziel(&"ranch/hof"), "ranch")
	assert_eq(DlcLoadingKarten.dlc_fuer_ziel(&"ranch/welt"), "ranch")
	assert_eq(DlcLoadingKarten.dlc_fuer_ziel(&"dlc/goobye_laden"), "goobye")
	assert_eq(DlcLoadingKarten.dlc_fuer_ziel(&"mcgooby_schicht"), "mcgooby")
	assert_eq(
		DlcLoadingKarten.dlc_fuer_ziel(GoobyeRouten.ROUTE_LADEN),
		"goobye",
		"Die ECHTE Laden-Route bleibt gemappt (Wache gegen Routen-Umzug)."
	)
	assert_eq(
		DlcLoadingKarten.dlc_fuer_ziel(McGoobyRouten.ROUTE_SCHICHT),
		"mcgooby",
		"Die ECHTE Schicht-Route bleibt gemappt (Wache gegen Routen-Umzug)."
	)
	assert_eq(DlcLoadingKarten.dlc_fuer_ziel(&"home/living"), "", "Haus ist kein DLC.")
	assert_eq(DlcLoadingKarten.dlc_fuer_ziel(&"city"), "", "Stadt ist kein DLC.")
	assert_eq(DlcLoadingKarten.dlc_fuer_ziel(&"dlc"), "", "Der DLC-Hub ist kein DLC-Ort.")
	assert_eq(DlcLoadingKarten.dlc_fuer_ziel(StringName()), "", "Leer → keine Karte.")


func test_karten_id_betreten_schlaegt_rueckweg() -> void:
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"dlc/goobye_laden", &"home/living"),
		"goobye",
		"Betreten: Ziel-DLC gewinnt."
	)
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"home/living", &"dlc/goobye_laden"),
		"goobye",
		"Rueckweg: Herkunfts-DLC traegt die Karte."
	)
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"mcgooby_schicht", &"ranch/hof"),
		"mcgooby",
		"DLC → DLC: das Ziel gewinnt."
	)
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"city", &"home/living"), "", "Ohne DLC keine DLC-Karte."
	)
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"home/living", StringName()),
		"",
		"Boot ohne Herkunft → Standard-Karte."
	)
	assert_true(DlcLoadingKarten.ist_betreten(&"ranch/hof"))
	assert_false(DlcLoadingKarten.ist_betreten(&"home/living"))


func test_unbekannte_id_faellt_auf_standard() -> void:
	assert_eq(DlcLoadingKarten.cover_pfad("gibtsnicht"), "", "Unbekannt → kein Cover-Pfad.")
	assert_eq(DlcLoadingKarten.motiv_pfad("gibtsnicht"), "", "Unbekannt → kein Motiv-Pfad.")
	assert_eq(
		DlcLoadingKarten.fallback_farben("gibtsnicht"),
		[] as Array[Color],
		"Unbekannt → Standard-Verlauf."
	)
	assert_eq(DlcLoadingKarten.karten_id_fuer(&"gibtsnicht", &"auchnicht"), "")


func test_alle_profil_assets_existieren() -> void:
	for id: String in DlcLoadingKarten.PROFILE:
		var cover := DlcLoadingKarten.cover_pfad(id)
		var motiv := DlcLoadingKarten.motiv_pfad(id)
		assert_true(ResourceLoader.exists(cover), "Cover fehlt: %s (%s)" % [id, cover])
		assert_true(ResourceLoader.exists(motiv), "Motiv fehlt: %s (%s)" % [id, motiv])
		assert_eq(DlcLoadingKarten.fallback_farben(id).size(), 3, "Farbstimmung = 3 Stops: %s" % id)


func test_tipp_pools_6_plus_de_en_paritaetisch() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for id: String in DlcLoadingKarten.PROFILE:
		var key := DlcLoadingKarten.tips_key(id)
		var de_tips: Array = de.get(key, [])
		var en_tips: Array = en.get(key, [])
		assert_true(de_tips.size() >= 6, "6+ DE-Tipps fuer %s (sind %d)." % [id, de_tips.size()])
		assert_eq(en_tips.size(), de_tips.size(), "DE/EN gleich viele Tipps: %s" % id)
		for tip: Variant in de_tips + en_tips:
			assert_true(str(tip).length() > 20, "Tipp ist ein echter Satz: %s" % str(tip))
		for feld: String in ["titel", "titel_zurueck", "bereit", "bereit_zurueck"]:
			var feld_key := "veil.dlc.%s.%s" % [id, feld]
			assert_true(str(de.get(feld_key, "")).length() > 3, "DE fehlt %s" % feld_key)
			assert_true(str(en.get(feld_key, "")).length() > 3, "EN fehlt %s" % feld_key)


## Der Moehren-Gag ist Teil der Goobye-Identitaet (Paket-Anforderung).
func test_goobye_traegt_den_moehren_gag() -> void:
	I18nService.reset_cache()
	var de_text := _pool_text(I18nService.table("de"), DlcLoadingKarten.tips_key("goobye"))
	var en_text := _pool_text(I18nService.table("en"), DlcLoadingKarten.tips_key("goobye"))
	assert_true(de_text.contains("Möhre"), "Moehren-Gag im DE-Pool.")
	assert_true(en_text.to_lower().contains("carrot"), "Carrot-Gag im EN-Pool.")


func test_veil_zeigt_goobye_karte_beim_betreten() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"home/living")
	veil.prepare_for_travel(&"dlc/goobye_laden")
	assert_true((veil.get_node("%Card") as Control).visible, "Karte sichtbar (kein Vollbild).")
	assert_eq(
		(veil.get_node("%Title") as Label).text,
		I18nService.t("veil.dlc.goobye.titel"),
		"Goobye-Titel beim Betreten."
	)
	assert_eq(
		(veil.get_node("%Ready") as Label).text,
		I18nService.t("veil.dlc.goobye.bereit"),
		"Goobye-Ready-Zeile beim Betreten."
	)
	var cover := veil.get_node("%Cover") as TextureRect
	assert_true(cover.visible and cover.texture != null, "DLC-Cover gesetzt.")
	assert_eq(
		cover.texture.resource_path,
		DlcLoadingKarten.cover_pfad("goobye"),
		"Cover = bestehendes Hub-Coverart (Stil-Konsistenz)."
	)
	_cleanup(veil)


func test_veil_rueckweg_karte_und_standard_fallback() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"dlc/goobye_laden")
	veil.prepare_for_travel(&"dlc")
	var titel := veil.get_node("%Title") as Label
	assert_eq(
		titel.text,
		I18nService.t("veil.dlc.goobye.titel_zurueck"),
		"Rueckweg zum Hub traegt die Goobye-Identitaet."
	)
	veil.prepare_for_travel(&"city")
	assert_eq(titel.text, I18nService.t("veil.trip.titel"), "Danach Standard-Trip-Karte.")
	var cover := veil.get_node("%Cover") as TextureRect
	assert_eq(cover.texture.resource_path, LoadingVeil.COVER_HOME_PFAD, "Heim-Cover wieder da.")
	_cleanup(veil)


func test_ranch_vollbildschirm_behaelt_vorrang_dann_heu_karte() -> void:
	var veil := _fresh_veil()
	veil.stunde_override = 12.0
	veil.prepare_for_travel(&"home/living")
	veil.prepare_for_travel(&"ranch/hof")
	var screen: Control = veil.get_node_or_null("Root/RanchScreen")
	assert_true(screen != null and screen.visible, "Lange Reise: Vollbildschirm bleibt.")
	assert_false((veil.get_node("%Card") as Control).visible, "Karte dahinter versteckt.")
	veil.prepare_for_travel(&"home/living")
	assert_true(screen == null or not screen.visible, "Rueckweg: Vollbildschirm weg.")
	assert_true((veil.get_node("%Card") as Control).visible, "Karte wieder da.")
	assert_eq(
		(veil.get_node("%Title") as Label).text,
		I18nService.t("veil.dlc.ranch.titel_zurueck"),
		"Heu/Koppel-Identitaet auf dem Heimweg."
	)
	var motiv := veil.get_node("%Gooby") as LoadingVeilSticker
	assert_true(motiv.visible, "Motiv-Sticker aktiv.")
	_cleanup(veil)


func test_minigame_hint_schlaegt_dlc_karte() -> void:
	var veil := _fresh_veil()
	LoadingVeil.set_travel_hint(
		{"game_id": "x", "title": "Spielprobe", "targets": [&"dlc/goobye_laden"]}
	)
	veil.prepare_for_travel(&"dlc/goobye_laden")
	assert_eq((veil.get_node("%Title") as Label).text, "Spielprobe", "Hint-Titel gewinnt.")
	_cleanup(veil)


func test_dlc_tipps_pool_speist_die_karte() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"mcgooby_schicht")
	var tips := I18nService.items(DlcLoadingKarten.tips_key("mcgooby"))
	assert_true(tips.size() >= 6, "McGooby-Pool gefuellt.")
	assert_true(
		tips.has((veil.get_node("%Tip") as Label).text), "Karten-Tipp stammt aus dem McGooby-Pool."
	)
	_cleanup(veil)


func test_farbstimmung_wechselt_und_kehrt_zurueck() -> void:
	var veil := _fresh_veil()
	var karte := veil.get_node("%Card") as LoadingVeilKarte
	var fallback := karte.get_node("Clip/CardBox/CoverZone/Fallback") as TextureRect
	veil.prepare_for_travel(&"mcgooby_schicht")
	var dlc_verlauf := fallback.texture as GradientTexture2D
	assert_eq(
		dlc_verlauf.gradient.colors[0],
		DlcLoadingKarten.fallback_farben("mcgooby")[0],
		"McGooby-Farbstimmung im Fallback-Verlauf."
	)
	veil.prepare_for_travel(&"city")
	veil.prepare_for_travel(&"city/ort/rehwei")
	var standard_verlauf := fallback.texture as GradientTexture2D
	assert_eq(
		standard_verlauf.gradient.colors[0],
		LoadingVeilKarte.FALLBACK_FARBEN[0],
		"Standard-Reise → Web-Standard-Verlauf zurueck."
	)
	_cleanup(veil)


func test_w1a_contract_mit_dlc_karte() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"dlc/goobye_laden")
	var events: Array = []
	veil.covered.connect(func() -> void: events.append("covered"))
	veil.revealed.connect(func() -> void: events.append("revealed"))
	await veil.cover(true)
	assert_true(veil.visible, "cover() macht sichtbar.")
	await veil.reveal(true)
	assert_false(veil.visible, "reveal() blendet aus.")
	assert_eq(events, ["covered", "revealed"] as Array, "Signal-Reihenfolge bleibt.")
	_cleanup(veil)


func _pool_text(tabelle: Dictionary, key: String) -> String:
	var text := ""
	for tip: Variant in tabelle.get(key, []):
		text += str(tip) + "\n"
	return text


func _fresh_veil() -> LoadingVeil:
	LoadingVeil.clear_travel_hint()
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	return veil


func _cleanup(veil: LoadingVeil) -> void:
	LoadingVeil.clear_travel_hint()
	tree.root.remove_child(veil)
	veil.free()

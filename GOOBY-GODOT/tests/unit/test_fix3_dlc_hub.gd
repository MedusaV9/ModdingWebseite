extends TestCase
## G8/FIX-3 — Regressions-Tests zu den Befunden B1 + B5 aus
## docs/playtest/G8-PT2-stadt-laeden.md:
## - B1 HOCH: Navigations-goto AUS dem Settings-Overlay heraus (DLC-Hub,
##   Codes, Übernahme) liess das Overlay im persistenten UiLayer liegen —
##   der Zielscreen lag unsichtbar darunter und bekam keine Taps. Wurzel-
##   Fix GENERISCH: home_entry._on_travel_started schliesst das Overlay
##   bei JEDEM Reiseantritt (der Veil deckt das ab). End-to-End-Beleg:
##   tests/tools/playtest_flows/flow_fix3_dlc_hub.gd.
## - B5 KLEIN: die Reise ZUM DLC-Hub (Ziel `dlc`) trug die „Trautes
##   Heim“-Karte. Jetzt traegt sie die eigene neutrale Hub-Karte aus
##   DlcLoadingKarten — NACHRANGIG: der Rueckweg Laden → Hub behaelt die
##   Identitaet des Ladens, der Hub bleibt KEIN DLC-Ort (dlc_fuer_ziel "").

const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")
const HOME_ENTRY := preload("res://scripts/home/home_entry.gd")

## --- B1: Reiseantritt schliesst das Settings-Overlay (generisch) ---


func test_reiseantritt_schliesst_settings_overlay() -> void:
	var entry: Node = HOME_ENTRY.new()
	var overlay := Control.new()
	tree.root.add_child(overlay)
	entry.set("_settings", overlay)
	entry.call("_on_travel_started", &"dlc", 0)
	assert_true(
		overlay.is_queued_for_deletion(),
		"B1: der Reiseantritt (goto aus den Einstellungen) schliesst das Overlay."
	)
	assert_true(entry.get("_settings") == null, "Overlay-Referenz ist geraeumt.")
	entry.free()
	await tree.process_frame


func test_reiseantritt_ohne_offenes_overlay_bleibt_harmlos() -> void:
	var entry: Node = HOME_ENTRY.new()
	entry.call("_on_travel_started", &"city", 0)
	assert_true(entry.get("_settings") == null, "Ohne Overlay passiert nichts.")
	entry.free()


## --- B5: Zuordnung Ziel `dlc` → Hub-Karte (nachrangig) ---


func test_hub_karte_fuer_reise_zum_hub() -> void:
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"dlc", &"home/living"),
		DlcLoadingKarten.HUB_ID,
		"B5: Zuhause → Hub traegt die Hub-Karte (nicht mehr „Trautes Heim“)."
	)
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"dlc", StringName()),
		DlcLoadingKarten.HUB_ID,
		"Auch ohne Herkunft traegt das Hub-Ziel die Hub-Karte."
	)
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"city", &"home/living"),
		"",
		"Andere Nicht-DLC-Reisen bleiben auf der Standard-Karte."
	)


func test_hub_karte_ist_nachrangig_zu_dlc_orten() -> void:
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"dlc", &"dlc/goobye_laden"),
		"goobye",
		"Rueckweg Laden → Hub behaelt die Laden-Identitaet (Bestandsregel)."
	)
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"ranch/hof", &"dlc"),
		"ranch",
		"Hub → DLC: der Ziel-DLC gewinnt."
	)
	assert_eq(
		DlcLoadingKarten.karten_id_fuer(&"home/living", &"dlc"),
		"",
		"Hub → Zuhause: die Standard-Heim-Karte uebernimmt (Hub klebt nicht)."
	)
	assert_eq(
		DlcLoadingKarten.dlc_fuer_ziel(&"dlc"),
		"",
		"Der Hub bleibt KEIN DLC-Ort — nur die Karten-Wahl kennt ihn."
	)


func test_hub_profil_vollstaendig() -> void:
	var cover := DlcLoadingKarten.cover_pfad(DlcLoadingKarten.HUB_ID)
	var motiv := DlcLoadingKarten.motiv_pfad(DlcLoadingKarten.HUB_ID)
	assert_true(ResourceLoader.exists(cover), "Hub-Cover existiert: %s" % cover)
	assert_true(ResourceLoader.exists(motiv), "Hub-Motiv existiert: %s" % motiv)
	assert_eq(
		DlcLoadingKarten.fallback_farben(DlcLoadingKarten.HUB_ID).size(),
		3,
		"Hub-Farbstimmung hat 3 Stops."
	)


## --- B5: Hub-Strings (DE/EN, Auftrag: Tipps-Pool 3+ Zeilen) ---


func test_hub_texte_de_en_und_richtungslos_identisch() -> void:
	I18nService.reset_cache()
	for sprache: String in ["de", "en"]:
		var tabelle := I18nService.table(sprache)
		var titel := str(tabelle.get("veil.dlc.hub.titel", ""))
		assert_true(titel.length() > 3, "%s: Hub-Titel vorhanden." % sprache)
		assert_eq(
			str(tabelle.get("veil.dlc.hub.titel_zurueck", "")),
			titel,
			"%s: Hub-Texte sind richtungslos identisch (ist_betreten=false)." % sprache
		)
		assert_eq(
			str(tabelle.get("veil.dlc.hub.bereit_zurueck", "")),
			str(tabelle.get("veil.dlc.hub.bereit", "")),
			"%s: auch die Bereit-Zeile ist richtungslos." % sprache
		)
		assert_ne(
			titel,
			str(tabelle.get("veil.home.titel", "")),
			"%s: Hub-Titel ist NICHT der Heim-Titel (B5-Kern)." % sprache
		)


func test_hub_tipp_pool_mindestens_drei_de_en() -> void:
	I18nService.reset_cache()
	var key := DlcLoadingKarten.tips_key(DlcLoadingKarten.HUB_ID)
	var de_tips: Array = I18nService.table("de").get(key, [])
	var en_tips: Array = I18nService.table("en").get(key, [])
	# Auftrag: 3+ Zeilen DE/EN — den Systemstandard (6+, Parität, echte
	# Sätze) waechst test_dlc_loading_karten über die PROFILE-Schleife mit.
	assert_true(de_tips.size() >= 3, "DE-Tipp-Pool hat 3+ Zeilen (sind %d)." % de_tips.size())
	assert_eq(en_tips.size(), de_tips.size(), "EN-Pool ist DE-paritaetisch.")


## --- B5: Veil-Integration (Hub-Karte statt „Trautes Heim“) ---


func test_veil_zeigt_hub_karte_statt_trautes_heim() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"home/living")
	veil.prepare_for_travel(&"dlc")
	var titel := (veil.get_node("%Title") as Label).text
	assert_eq(
		titel, I18nService.t("veil.dlc.hub.titel"), "Reise zum Hub traegt die Hub-Karte (B5)."
	)
	assert_ne(titel, I18nService.t("veil.home.titel"), "…nicht mehr „Trautes Heim“.")
	assert_eq(
		(veil.get_node("%Ready") as Label).text,
		I18nService.t("veil.dlc.hub.bereit"),
		"Hub-Ready-Zeile in der Cover-Zone."
	)
	var cover := veil.get_node("%Cover") as TextureRect
	assert_true(cover.visible and cover.texture != null, "Hub-Cover gesetzt.")
	assert_eq(
		cover.texture.resource_path,
		DlcLoadingKarten.cover_pfad(DlcLoadingKarten.HUB_ID),
		"Cover = das Regal-Artwork des Hubs."
	)
	veil.prepare_for_travel(&"home/living")
	assert_eq(
		(veil.get_node("%Title") as Label).text,
		I18nService.t("veil.home.titel"),
		"Hub → Zuhause: die Heim-Karte ist wieder da (Hub klebt nicht)."
	)
	_cleanup(veil)


func test_veil_hub_tipps_aus_dem_hub_pool() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"dlc")
	var tips := I18nService.items(DlcLoadingKarten.tips_key(DlcLoadingKarten.HUB_ID))
	assert_true(tips.size() >= 3, "Hub-Pool gefuellt.")
	assert_true(
		tips.has((veil.get_node("%Tip") as Label).text), "Karten-Tipp stammt aus dem Hub-Pool."
	)
	_cleanup(veil)


func _fresh_veil() -> LoadingVeil:
	LoadingVeil.clear_travel_hint()
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	return veil


func _cleanup(veil: LoadingVeil) -> void:
	LoadingVeil.clear_travel_hint()
	tree.root.remove_child(veil)
	veil.free()

extends TestCase
## W20 Top-10 #2 — Wächter der Ziel→Karten-Registry des Reise-Veils
## (loading_veil_ziele.gd, verifizierter Playtest-Fund + G6-Paket seit W17):
## Vor W20 kannte die Ziel-Wahl (LoadingVeil.modus_fuer_ziel) nur `ikea` und
## `city*` als Trip-Ziele — JEDES andere Ziel (auch die DLC-Bibliothek) lud
## unter der „Trautes Heim“-Karte mit Heim-Artwork. Diese Datei pinnt:
## - jede registrierte Route-Familie liefert ihre eigene Karten-Variante
##   (dlc / ranch / arcade / reise), die DLC-Route NICHT mehr die Heim-Karte,
## - unbekannte Ziele bekommen den ehrlichen „Unterwegs…“-Fallback,
## - die neuen `veil.*`-Keys sind DE/EN-paritätisch,
## - die Bestands-Regeln (home/trip wie im Web, `arcade`-Route = Home-Karte,
##   Heim-Cover für home/trip) bleiben exakt erhalten — test_ui_veil.gd
##   bleibt unangetastet und muss weiter komplett grün laufen.

const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")
## Die 5 neuen Karten-Familien der W20-Registry (home/trip/game sind Bestand).
const NEUE_MODI: Array[String] = ["dlc", "ranch", "arcade", "reise", "unterwegs"]


## DER Playtest-Fund: Reise zur DLC-Bibliothek trug die „Trautes Heim“-Karte.
## Rot-vor-grün: Vor der Registry schlug genau dieser Test fehl (Titel war
## I18n „veil.home.titel“, Cover das Heim-Artwork).
func test_dlc_route_zeigt_nicht_die_heim_karte() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"dlc")
	var titel := (veil.get_node("%Title") as Label).text
	assert_ne(
		titel,
		I18nService.t("veil.home.titel"),
		"DLC-Reise trägt NICHT „Trautes Heim“ (Playtest-Fund W20)."
	)
	assert_eq(titel, I18nService.t("veil.dlc.titel"), "DLC-Reise trägt die DLC-Bibliothek-Karte.")
	assert_eq(
		(veil.get_node("%Ready") as Label).text,
		I18nService.t("veil.dlc.bereit"),
		"Ready-Zeile der DLC-Karte."
	)
	var cover := veil.get_node("%Cover") as TextureRect
	assert_true(cover.visible and cover.texture != null, "DLC-Karte hat ein Cover.")
	assert_ne(
		cover.texture,
		load(LoadingVeil.COVER_HOME_PFAD),
		"…und zwar die Regal-Stimmung, NICHT das Heim-Artwork."
	)
	_cleanup(veil)


## Jede registrierte Route-Familie liefert ihre Karten-Variante.
func test_registry_liefert_karten_familien() -> void:
	# DLC-Familie: Bibliothek, Goobye-Laden, McGooby-Schicht.
	assert_eq(LoadingVeil.modus_fuer_ziel(&"dlc"), "dlc", "DLC-Bibliothek = dlc.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"dlc/goobye_laden"), "dlc", "Goobye-Laden = dlc.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"mcgooby_schicht"), "dlc", "McGooby-Schicht = dlc.")
	# Ranch-Familie (Sicherheitsnetz — lange Reisen zeigen den Vollbild-Schirm).
	assert_eq(LoadingVeil.modus_fuer_ziel(&"ranch/hof"), "ranch", "Ranch-Hof = ranch.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"ranch/welt"), "ranch", "Ranch-Welt = ranch.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"ranch/karte"), "ranch", "Entdecker-Karte = ranch.")
	# Minigame-Durchgangsstationen OHNE Travel-Hint: Arcade-Karte statt Heim.
	assert_eq(LoadingVeil.modus_fuer_ziel(&"mg_pregame"), "arcade", "Pregame ohne Hint = arcade.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"mg_host"), "arcade", "Host ohne Hint = arcade.")
	# Flughafen/Reise-Familie (spezifischer als das generische city-Präfix).
	assert_eq(LoadingVeil.modus_fuer_ziel(&"city/ort/flughafen"), "reise", "Flughafen = reise.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"city/ort/raumstation"), "reise", "Shuttle = reise.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"city/urlaub/strand"), "reise", "Urlaub = reise.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"city/urlaub/berge"), "reise", "Urlaub Berge = reise.")


## Minigame-Reise ohne gesetzten Travel-Hint: die Arcade-Karte greift auch
## auf UI-Ebene (mit Hint gewinnt weiter der game-Modus — test_ui_veil pinnt).
func test_mg_route_ohne_hint_traegt_arcade_karte() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"mg_pregame")
	assert_eq(
		(veil.get_node("%Title") as Label).text,
		I18nService.t("veil.arcade.titel"),
		"Pregame ohne Hint trägt die Arcade-Karte."
	)
	_cleanup(veil)


## Ehrlicher Fallback: unbekannte Ziele reisen „Unterwegs…“ statt unter
## der falschen „Trautes Heim“-Karte.
func test_fallback_fuer_unbekannte_ziele() -> void:
	assert_eq(
		LoadingVeil.modus_fuer_ziel(&"voellig/unbekannt"),
		"unterwegs",
		"Unbekanntes Ziel = unterwegs-Fallback."
	)
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"voellig/unbekannt")
	var titel := (veil.get_node("%Title") as Label).text
	assert_eq(titel, I18nService.t("veil.unterwegs.titel"), "Fallback-Karte „Unterwegs…“.")
	assert_ne(titel, I18nService.t("veil.home.titel"), "…und NICHT „Trautes Heim“.")
	_cleanup(veil)


## Bestands-Regeln bleiben exakt (Web-Paritäten, die test_ui_veil.gd pinnt).
func test_bestands_familien_bleiben() -> void:
	assert_eq(LoadingVeil.modus_fuer_ziel(&"ikea"), "trip", "Shop-Reise bleibt trip.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"city"), "trip", "Stadt-Reise bleibt trip.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"city/ort/tierarzt"), "trip", "Klinik bleibt trip.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"home"), "home", "Rückkehr bleibt home.")
	assert_eq(LoadingVeil.modus_fuer_ziel(&"home/kitchen"), "home", "Hausraum bleibt home.")
	# Die Arcade-ROUTE (der Screen selbst) bleibt bewusst auf der Home-Karte —
	# W16-Web-Regel „Sonstige Screens = home“, gepinnt in test_ui_veil.gd Z. 67.
	assert_eq(LoadingVeil.modus_fuer_ziel(&"arcade"), "home", "Arcade-Screen bleibt home.")


## Jede neue Familie hat ein eigenes prozedurales Stimmungs-Cover;
## home/trip behalten das Heim-Artwork (Web-Verhalten).
func test_prozedurale_cover_je_familie() -> void:
	var veil := _fresh_veil()
	var cover := veil.get_node("%Cover") as TextureRect
	veil.prepare_for_travel(&"dlc")
	var dlc_cover := cover.texture
	veil.prepare_for_travel(&"city/ort/flughafen")
	var reise_cover := cover.texture
	assert_true(dlc_cover != null and reise_cover != null, "Beide Familien haben Cover.")
	assert_ne(dlc_cover, reise_cover, "Je Familie ein eigenes Stimmungs-Cover.")
	# Cache-Wächter: dieselbe Familie liefert dieselbe (einmal gemalte) Textur.
	veil.prepare_for_travel(&"dlc")
	assert_eq(cover.texture, dlc_cover, "Cover je Familie wird gecacht (kein Neu-Malen).")
	veil.prepare_for_travel(&"ikea")
	assert_eq(
		cover.texture,
		load(LoadingVeil.COVER_HOME_PFAD),
		"Trip behält das Heim-Artwork (Web-Parität)."
	)
	_cleanup(veil)


## DE/EN-Parität der neuen veil.*-Keys (Titel, Ready-Zeile, 3–8 echte Tipps).
func test_neue_karten_keys_de_en_paritaet() -> void:
	for modus in NEUE_MODI:
		for feld in ["titel", "bereit"]:
			var key := "veil.%s.%s" % [modus, feld]
			var de := str(I18nService.table("de").get(key, ""))
			var en := str(I18nService.table("en").get(key, ""))
			assert_true(de.length() > 2, "DE-Key %s vorhanden." % key)
			assert_true(en.length() > 2, "EN-Key %s vorhanden." % key)
		var tips_de: Array = I18nService.table("de").get("veil.%s.tips" % modus, [])
		var tips_en: Array = I18nService.table("en").get("veil.%s.tips" % modus, [])
		var anzahl := tips_de.size()
		assert_true(anzahl >= 3 and anzahl <= 8, "3–8 Tipps im Modus %s (%d)." % [modus, anzahl])
		assert_eq(tips_en.size(), anzahl, "EN-Tipp-Parität im Modus %s." % modus)
		for tip: Variant in tips_de:
			assert_true(str(tip).length() > 10, "Tipp ist ein echter Satz: %s" % str(tip))


func _fresh_veil() -> LoadingVeil:
	LoadingVeil.clear_travel_hint()
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	return veil


func _cleanup(veil: LoadingVeil) -> void:
	LoadingVeil.clear_travel_hint()
	tree.root.remove_child(veil)
	veil.free()

extends TestCase
## W19 MCGOOBY-B — Wächter für Kauf-Gate + zweite Station (Belegstation):
## - Kauf TRANSAKTIONAL (W18/B1-Muster): check()-Ausgänge, genau-einmal-
##   Buchung, Münzmangel lässt alles unangetastet, Stale-Check-Rennen
##   endet in ehrlichem OWNED, mcgooby steht in der Boot-Registry.
## - Demo-Gate der Probeschicht: genau EINE pro lokalem Tag VOR dem Kauf
##   (Zeit über die gs-Clock gepinnt), nach dem Kauf unbegrenzt.
## - Belegstation deterministisch: Ticket/Leiste/Wisch-Wertung golden,
##   Autoplay-Bot (Station + ganze Schicht) liefert exakte Goldwerte.
## - Hub-Ableitung: Unlock-Text aus dem Balance-Pack, Angebots-Sheet mit
##   B12-Ausgrauung bei Münzmangel, Kauf über den Sheet-Knopf.
## - Szene: Stations-Tabs, Belegen-Phase, Perfekt-Kette, Sperre-Karte.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const SCHICHT_SZENE := "res://scripts/dlc/mcgooby/schicht_scene.tscn"
const GOLD_SEED := 4711


## Pinnbare Uhr-Attrappe (Clock-Duck-Typing: now_ms + local_day).
class FakeClock:
	extends RefCounted
	var ms := 1_770_000_000_000
	var tag := "2026-08-03"

	func now_ms() -> int:
		return ms

	func local_day(_at := -1) -> String:
		return tag


## GameState-Double: dotted get/set + update()-Pfad + notify_slice_changed
## (der Kauf ruft ihn nach RESULT_OK) + gepinnte Clock (Zeit injiziert).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {"economy": {"coins": 0}}
	var clock := FakeClock.new()
	var notified: Array = []
	## Stale-Check-Rennen (W18/B1): get_value meldet gekauft=false, obwohl
	## der State längst gekauft trägt — der In-Block-Check muss das abfangen.
	var stale_gekauft_check := false

	func get_value(path: String, fallback: Variant = null) -> Variant:
		if stale_gekauft_check and path == "mcgooby.gekauft":
			return false
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

	func notify_slice_changed(id: String) -> void:
		notified.append(id)


func _gs(level: int, coins: int) -> FakeGameState:
	var gs := FakeGameState.new()
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _bal() -> Dictionary:
	McGoobyKatalog.reset_cache()
	return McGoobyKatalog.balance()


## ------------------------------------------------------------ Kauf-Gate


func test_kauf_check_alle_ausgaenge() -> void:
	McGoobyKatalog.reset_cache()
	assert_eq(McGoobyKatalog.preis(), 3000, "Preis aus dem Balance-Pack (Doc §6.2)")
	assert_eq(McGoobyKatalog.freischalt_level(), 14, "Level-Gate aus dem Balance-Pack")
	assert_eq(McGoobyKauf.check(null), McGoobyKauf.RESULT_LOCKED, "ohne gs fail-closed")
	assert_eq(
		McGoobyKauf.check(_gs(13, 99_999)),
		McGoobyKauf.RESULT_LOCKED,
		"Level 13 < 14 → gesperrt, egal wie voll das Säckel ist"
	)
	assert_eq(
		McGoobyKauf.check(_gs(14, 2999)), McGoobyKauf.RESULT_BROKE, "2999 < 3000 → Münzmangel"
	)
	assert_eq(McGoobyKauf.check(_gs(14, 3000)), McGoobyKauf.RESULT_OK, "exakt 3000 reicht")
	assert_true(McGoobyKauf.kann_kaufen(_gs(14, 3000)))
	var gekauft := _gs(14, 0)
	gekauft.set_value("mcgooby.gekauft", true)
	assert_eq(McGoobyKauf.check(gekauft), McGoobyKauf.RESULT_OWNED, "gekauft → OWNED")


func test_kauf_transaktional_bucht_genau_einmal() -> void:
	var gs := _gs(14, McGoobyKatalog.preis() + 777)
	assert_eq(McGoobyKauf.kaufe(gs), McGoobyKauf.RESULT_OK, "Kauf klappt")
	assert_eq(int(gs.get_value("economy.coins", -1)), 777, "GENAU der Preis, GENAU einmal weg")
	assert_eq(
		int(gs.get_value("economy.coinsSpent", 0)),
		McGoobyKatalog.preis(),
		"Abbuchung steht im Spent-Buch (Economy.spend)"
	)
	assert_eq(gs.get_value("mcgooby.gekauft"), true, "Kauf ist registriert")
	assert_eq(int(gs.get_value("mcgooby.gekauftAm", 0)), gs.clock.now_ms(), "Zeit aus der gs-Clock")
	assert_eq(gs.get_value("mcgooby.angebotGesehen"), true)
	assert_eq(gs.get_value("mcgooby.angebotVerschoben"), false)
	assert_eq(gs.notified, ["mcgooby"], "genau ein slice_changed")
	# Doppel-Klick: zweiter Kauf ist ehrliches OWNED ohne zweite Abbuchung.
	assert_eq(McGoobyKauf.kaufe(gs), McGoobyKauf.RESULT_OWNED, "Doppelkauf abgefangen")
	assert_eq(int(gs.get_value("economy.coins", -1)), 777, "keine zweite Abbuchung")
	assert_eq(gs.notified.size(), 1, "kein zweites slice_changed")


func test_kauf_muenzmangel_laesst_alles_unangetastet() -> void:
	var gs := _gs(14, McGoobyKatalog.preis() - 1)
	assert_eq(McGoobyKauf.kaufe(gs), McGoobyKauf.RESULT_BROKE, "ehrliches BROKE")
	assert_eq(int(gs.get_value("economy.coins", -1)), McGoobyKatalog.preis() - 1, "Münzen da")
	assert_ne(gs.get_value("mcgooby.gekauft", false), true, "nichts gebucht")
	assert_true(gs.notified.is_empty(), "kein slice_changed ohne Kauf")


func test_kauf_ueberlebt_registrierungs_loch_und_stale_check() -> void:
	# Registrierungs-Loch (W18/B1): der State trägt KEINEN mcgooby-Slice —
	# ensure_mcgooby im update-Block legt ihn an, bevor gebucht wird.
	var gs := _gs(14, McGoobyKatalog.preis())
	gs.update(func(state: Dictionary) -> void: state.erase("mcgooby"))
	assert_eq(McGoobyKauf.kaufe(gs), McGoobyKauf.RESULT_OK, "Kauf ohne Slice-Key klappt")
	assert_eq(gs.get_value("mcgooby.gekauft"), true)
	assert_eq(int(gs.get_value("economy.coins", -1)), 0)
	# Stale-Check-Rennen: check() sieht gekauft=false, der State trägt aber
	# schon gekauft=true — der In-Block-Check verhindert die Doppel-Buchung.
	var stale := _gs(14, 5000)
	stale.set_value("mcgooby.gekauft", true)
	stale.stale_gekauft_check = true
	assert_eq(McGoobyKauf.kaufe(stale), McGoobyKauf.RESULT_OWNED, "ehrliches OWNED statt OK")
	assert_eq(int(stale.get_value("economy.coins", -1)), 5000, "keine Abbuchung im Rennen")
	assert_true(stale.notified.is_empty(), "kein slice_changed ohne echten Kauf")


func test_boot_registry_traegt_mcgooby() -> void:
	# W18/B1-Lehre: der Kauf läuft im Hub, BEVOR je eine McGooby-Szene lädt —
	# der Slice MUSS in der Boot-Registry stehen.
	assert_true(
		GameStateScript.DEFAULT_SLICE_SCRIPTS.has("mcgooby"),
		"mcgooby gehört zur Boot-Registry (DEFAULT_SLICE_SCRIPTS)"
	)
	GameStateScript.register_default_slices()
	assert_true(
		SaveSchema.registered_slice_ids().has(McGoobyState.SLICE_ID),
		"Boot registriert den mcgooby-Slice selbst"
	)


## ------------------------------------------------------------ Demo-Gate


func test_demo_gate_eine_probeschicht_pro_tag() -> void:
	var gs := _gs(1, 0)
	var tag := McGoobyState.heute_tag(gs)
	assert_eq(tag, gs.clock.tag, "heute_tag zählt die injizierte gs-Clock")
	assert_true(McGoobyState.schicht_erlaubt(gs, tag), "frischer Tag: Demo erlaubt")
	McGoobyState.demo_verbuchen(gs, tag)
	assert_false(McGoobyState.schicht_erlaubt(gs, tag), "Demo verbraucht: gesperrt")
	# Der nächste lokale Tag öffnet das Gate wieder.
	gs.clock.tag = "2026-08-04"
	assert_true(McGoobyState.schicht_erlaubt(gs, McGoobyState.heute_tag(gs)), "morgen wieder frei")
	# Ohne GameState (isolierte Screens) bleibt das Gate offen.
	assert_true(McGoobyState.schicht_erlaubt(null, tag), "ohne gs fail-open")


func test_demo_gate_nach_kauf_unbegrenzt() -> void:
	var gs := _gs(14, 0)
	var tag := McGoobyState.heute_tag(gs)
	McGoobyState.demo_verbuchen(gs, tag)
	assert_false(McGoobyState.schicht_erlaubt(gs, tag), "vor dem Kauf gesperrt")
	gs.set_value("mcgooby.gekauft", true)
	assert_true(McGoobyState.schicht_erlaubt(gs, tag), "nach dem Kauf immer erlaubt")
	# demo_verbuchen ist nach dem Kauf ein No-op (kein neuer Stempel).
	gs.set_value("mcgooby.demoTag", "")
	McGoobyState.demo_verbuchen(gs, tag)
	assert_eq(str(gs.get_value("mcgooby.demoTag", "x")), "", "kein Demo-Stempel mehr")


## ----------------------------------------------------------- Belegstation


func test_belegstation_ticket_leiste_und_wertung() -> void:
	McGoobyKatalog.reset_cache()
	var ticket := McGoobyStationBelegen.ticket_von(McGoobyKatalog.rezept("gooby_mac"))
	assert_eq(
		ticket,
		(
			["broetchen", "patty", "gold_sosse", "salat", "patty", "kaese", "broetchen"]
			as Array[String]
		),
		"GoobyMac-Ticket in Turm-Reihenfolge"
	)
	assert_true(
		McGoobyStationBelegen.ticket_von(McGoobyKatalog.rezept("moehren_pommes")).is_empty(),
		"Pommes brauchen keine Belegstation"
	)
	assert_eq(
		McGoobyStationBelegen.leiste(ticket),
		["broetchen", "patty", "gold_sosse", "salat", "kaese"] as Array[String],
		"Leiste: jede Zutat EINMAL, Erst-Auftauch-Reihenfolge"
	)
	assert_eq(McGoobyStationBelegen.naechste_zutat(ticket, 0), "broetchen")
	assert_eq(McGoobyStationBelegen.naechste_zutat(ticket, 4), "patty", "Doppel-Patty zählt")
	assert_eq(McGoobyStationBelegen.naechste_zutat(ticket, 7), "", "fertig = leer")
	assert_false(McGoobyStationBelegen.ist_fertig(ticket, 6))
	assert_true(McGoobyStationBelegen.ist_fertig(ticket, 7))
	var bal := _bal()
	var richtig := McGoobyStationBelegen.bewerte_wisch(ticket, 0, "broetchen", bal)
	assert_eq(str(richtig["wertung"]), "richtig")
	assert_eq(int(richtig["punkte"]), 5, "+5 aus dem Balance-Pack")
	assert_eq(int(richtig["platziert"]), 1, "Turm wächst")
	var falsch := McGoobyStationBelegen.bewerte_wisch(ticket, 0, "kaese", bal)
	assert_eq(str(falsch["wertung"]), "falsch")
	assert_eq(int(falsch["punkte"]), -2, "−2 Malus aus dem Balance-Pack")
	assert_eq(int(falsch["platziert"]), 0, "Turm bleibt stehen")
	# Zahlen kommen WIRKLICH aus dem Pack (überschattbare Balance).
	var eigene := {"belegen_punkte_richtig": 7, "belegen_malus_falsch": 3}
	assert_eq(int(McGoobyStationBelegen.bewerte_wisch(ticket, 0, "broetchen", eigene)["punkte"]), 7)
	assert_eq(int(McGoobyStationBelegen.bewerte_wisch(ticket, 0, "kaese", eigene)["punkte"]), -3)


func test_belegstation_autoplay_golden() -> void:
	var bal := _bal()
	var ticket := McGoobyStationBelegen.ticket_von(McGoobyKatalog.rezept("gooby_mac"))
	var gold := McGoobyStationBelegen.simulate_autoplay(GOLD_SEED, ticket, bal)
	assert_eq(int(gold["zutaten"]), 7)
	assert_eq(int(gold["fehlgriffe"]), 1, "Seed 4711 → genau 1 Fehlgriff")
	assert_eq(int(gold["punkte"]), 33, "7×5 − 2 Malus")
	assert_false(bool(gold["fehlerfrei"]))
	var gold2 := McGoobyStationBelegen.simulate_autoplay(1234, ticket, bal)
	assert_eq(int(gold2["fehlgriffe"]), 0)
	assert_eq(int(gold2["punkte"]), 35, "fehlerfrei: 7×5")
	assert_true(bool(gold2["fehlerfrei"]))
	# Deterministisch: derselbe Seed liefert exakt dasselbe Ergebnis.
	assert_eq(
		McGoobyStationBelegen.simulate_autoplay(GOLD_SEED, ticket, bal),
		gold,
		"Bot-Zertifizierung reproduzierbar (Doc §10.4)"
	)


func test_schicht_autoplay_mit_belegen_golden() -> void:
	McGoobyKatalog.reset_cache()
	var menu := McGoobyKatalog.rezepte_fuer("grill")
	var gold := McGoobySchichtLogic.simulate_autoplay(GOLD_SEED, menu, _bal())
	assert_eq(int(gold["bestellungen"]), 2)
	assert_eq(int(gold["fehlgriffe"]), 1, "Belegen-Fehlgriffe zählen in der Schicht")
	assert_eq(int(gold["punkte"]), 118, "Grill + Belegen + Boni − Malus (Goldwert)")
	assert_eq(int(gold["muenzen"]), 31)


## ------------------------------------------------------------- Hub & Sheet


func test_unlock_text_mcgooby_aus_balance_pack() -> void:
	DlcKatalog.reset_cache()
	var text := DlcKatalog.unlock_text(DlcKatalog.eintrag("mcgooby"))
	assert_true(text.contains(str(McGoobyKatalog.freischalt_level())), "Level eingesetzt")
	assert_true(text.contains(str(McGoobyKatalog.preis())), "Preis eingesetzt")
	assert_false(text.contains("{"), "keine offenen Platzhalter")


func test_angebot_sheet_ausgrauung_bei_muenzmangel() -> void:
	# W18/4 Befund B12: zu wenig Münzen → Kauf-Knopf DISABLED + Klartext.
	McGoobyOffer.auto_navigate = false
	var host := Control.new()
	tree.root.add_child(host)
	var gs := _gs(14, McGoobyKatalog.preis() - 100)
	var sheet := McGoobyOffer.zeige(host, gs)
	assert_true(sheet != null, "Angebot öffnet ab Level 14")
	await wait_frames(1)
	var kaufen: Button = sheet.get_meta(McGoobyOffer.META_KAUFEN, null)
	var hinweis: Label = sheet.get_meta(McGoobyOffer.META_HINWEIS, null)
	assert_true(kaufen != null and kaufen.disabled, "Kauf-Knopf ehrlich ausgegraut")
	assert_eq(
		hinweis.text,
		I18nService.t("dlc_mcgooby.angebot.zu_wenig", {"preis": McGoobyKatalog.preis()}),
		"Hinweiszeile sagt sofort Klartext"
	)
	# Fail-closed: gekauft oder Level zu niedrig → gar kein Sheet.
	assert_true(McGoobyOffer.zeige(host, _gs(13, 99_999)) == null, "Level-Gate hält")
	var gekauft := _gs(14, 0)
	gekauft.set_value("mcgooby.gekauft", true)
	assert_true(McGoobyOffer.zeige(host, gekauft) == null, "gekauft = kein Angebot")
	host.queue_free()
	McGoobyOffer.auto_navigate = true
	await wait_frames(1)


func test_angebot_sheet_kauf_ueber_den_knopf() -> void:
	McGoobyOffer.auto_navigate = false
	var host := Control.new()
	tree.root.add_child(host)
	var gs := _gs(14, McGoobyKatalog.preis() + 500)
	var sheet := McGoobyOffer.zeige(host, gs)
	assert_true(sheet != null, "Angebot öffnet")
	await wait_frames(1)
	var kaufen: Button = sheet.get_meta(McGoobyOffer.META_KAUFEN, null)
	assert_true(kaufen != null and not kaufen.disabled, "genug Münzen = Knopf aktiv")
	kaufen.pressed.emit()
	await wait_frames(1)
	assert_eq(gs.get_value("mcgooby.gekauft"), true, "Kauf über den Sheet-Knopf gebucht")
	assert_eq(int(gs.get_value("economy.coins", -1)), 500, "genau der Preis weg")
	# „Später“ merkt sich den Stand (frisches Sheet auf frischem Stand).
	var gs2 := _gs(14, McGoobyKatalog.preis())
	var sheet2 := McGoobyOffer.zeige(host, gs2)
	await wait_frames(1)
	var spaeter: Button = sheet2.get_meta(McGoobyOffer.META_SPAETER, null)
	spaeter.pressed.emit()
	await wait_frames(1)
	assert_eq(gs2.get_value("mcgooby.angebotVerschoben"), true, "Später = verschoben gemerkt")
	assert_ne(gs2.get_value("mcgooby.gekauft", false), true, "Später kauft nichts")
	host.queue_free()
	McGoobyOffer.auto_navigate = true
	await wait_frames(1)


## ------------------------------------------------------------ Szene Welle B


func test_szene_tabs_belegen_phase_und_kette() -> void:
	McGoobyKatalog.reset_cache()
	var gs := _gs(1, 0)
	gs.set_value("mcgooby.introGesehen", true)
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(szene.ist_am_laufen(), "Testaufbau: Schicht läuft")
	assert_eq(szene.phase_aktuell(), McGoobySchichtScene.PHASE_GRILL, "Start am Grill")
	assert_eq(szene.station_aktiv(), McGoobySchichtScene.PHASE_GRILL)
	# Tab-Wechsel ist reine Ansicht: Belegen-Box zeigt den „Grill ruft“-Tipp.
	var tab_belegen: Button = szene.find_child("Tab_belegen", true, false)
	assert_true(tab_belegen != null, "Belegen-Tab in der Daumen-Zone")
	tab_belegen.pressed.emit()
	await wait_frames(1)
	assert_eq(szene.station_aktiv(), McGoobySchichtScene.PHASE_BELEGEN, "Tab wechselt Ansicht")
	assert_eq(szene.phase_aktuell(), McGoobySchichtScene.PHASE_GRILL, "Phase bleibt Grill")
	var hinweis: Label = szene.find_child("BelegenHinweis", true, false)
	assert_true(hinweis.visible, "ohne Ticket ruft der Grill")
	# Patty perfekt wenden → Bestellung wechselt in die Belegen-Phase.
	var timing := McGoobyKatalog.timing("grill")
	szene.patty_zeit_setzen(float(timing["gar_sec"]) + 0.2)
	szene.patty_knopf().pressed.emit()
	await wait_frames(1)
	assert_eq(szene.phase_aktuell(), McGoobySchichtScene.PHASE_BELEGEN, "nach Grill: Belegen")
	assert_eq(
		szene.belegen_ticket(),
		["broetchen", "kuerbis_patty", "tomate", "salat", "broetchen"] as Array[String],
		"Garten-Gooby-Ticket liegt auf"
	)
	assert_eq(szene.zutaten_knoepfe().size(), 4, "Leiste: 4 einmalige Zutaten")
	var callout: Label = szene.find_child("Callout", true, false)
	# Perfekt-Kette (c): Patty perfekt (=1) + richtige Zutat (=2) → Kette ×2.
	_druecke_zutat(szene, "broetchen")
	await wait_frames(1)
	assert_eq(szene.belegen_platziert(), 1, "richtige Zutat wächst den Turm")
	assert_eq(
		callout.text,
		I18nService.t("dlc_mcgooby.schicht.kette", {"n": 2}),
		"Kette zählt über Stationen hinweg"
	)
	# Falsche Zutat: Malus, Turm steht, Kette reißt.
	var punkte_vor := _punkte_der_szene(szene)
	_druecke_zutat(szene, "salat")
	await wait_frames(1)
	assert_eq(szene.belegen_platziert(), 1, "falsche Zutat: Turm bleibt stehen")
	assert_eq(_punkte_der_szene(szene), punkte_vor - 2, "−2 Malus verbucht")
	assert_eq(callout.text, I18nService.t("dlc_mcgooby.schicht.falsch"), "Kette gerissen")
	# Ticket fertig belegen → Bestellung 2 kommt vom neuen Tresen (Welle C:
	# bestell_folge zieht aus ALLEN Stationen, Bestellung 2 ist garantiert
	# ein Fritteuse-/Shake-Rezept — Seed 4711: Pommes Klassik).
	for zutat_id: String in ["kuerbis_patty", "tomate", "salat", "broetchen"]:
		_druecke_zutat(szene, zutat_id)
		await wait_frames(1)
	assert_eq(
		szene.phase_aktuell(),
		McGoobySchichtScene.PHASE_FRITTEUSE,
		"Bestellung 2 am neuen Tresen (Welle C)"
	)
	assert_eq(str(szene.bestellung_aktuell().get("rezept_id", "")), "pommes_klassik")
	szene.queue_free()
	await wait_frames(1)


func test_szene_sperre_karte_mit_angebots_abzweig() -> void:
	McGoobyKatalog.reset_cache()
	# Demo des Tages verbraucht + Level reicht → Sperre MIT Angebots-Knopf.
	var gs := _gs(14, 0)
	gs.set_value("mcgooby.introGesehen", true)
	gs.set_value("mcgooby.demoTag", gs.clock.tag)
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(szene.ist_sperre_offen(), "Demo verbraucht → Sperre-Karte")
	assert_false(szene.ist_am_laufen(), "keine Schicht hinter der Sperre")
	var angebot: Button = szene.find_child("SperreAngebot", true, false)
	assert_true(angebot != null and angebot.visible, "Angebots-Abzweig ab Level 14")
	szene.queue_free()
	await wait_frames(1)
	# Level zu niedrig: Sperre ohne Angebots-Knopf (Level-Gate, Doc §6.2).
	var gs2 := _gs(1, 0)
	gs2.set_value("mcgooby.introGesehen", true)
	gs2.set_value("mcgooby.demoTag", gs2.clock.tag)
	var szene2: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene2.gs_override = gs2
	szene2.seed_override = GOLD_SEED
	szene2.auto_navigate = false
	tree.root.add_child(szene2)
	await wait_frames(3)
	assert_true(szene2.ist_sperre_offen(), "Sperre auch unter Level 14")
	var angebot2: Button = szene2.find_child("SperreAngebot", true, false)
	assert_false(angebot2.visible, "kein Angebots-Knopf unter dem Level-Gate")
	szene2.queue_free()
	await wait_frames(1)


## Zutaten-Knopf der Belegen-Leiste per id drücken.
func _druecke_zutat(szene: McGoobySchichtScene, zutat_id: String) -> void:
	for knopf in szene.zutaten_knoepfe():
		if String(knopf.name) == "Zutat_" + zutat_id:
			knopf.pressed.emit()
			return


## Aktueller Schicht-Punktestand aus dem Punkte-Label (Anzeige-Wahrheit).
func _punkte_der_szene(szene: McGoobySchichtScene) -> int:
	var label: Label = szene.find_child("Punkte", true, false)
	var ziffern := ""
	for zeichen in label.text:
		if zeichen >= "0" and zeichen <= "9":
			ziffern += zeichen
	return int(ziffern)

extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-DLC-Basis (W18/R3, G8): gemeinsame Bausteine der flow_ptdlc_*-Flows.
## Enthält den Spieler-Weg zum Goobye-Schlüssel (Einstellungen → DLC-Hub →
## Kauf für 2500 ᴳ, Muster flow_pt2_goobye_tag) und die EIGENE
## Nachrechen-Mathe des Playtests: Großmarkt-Preise (EK 60 %, Staffel −5 %
## ab 10, Rampen-Angebot −15 %), Backofen-Selbstkosten und die
## McGooby-Abrechnung (Combo-Trinkgeld + Münz-Tabelle) werden hier bewusst
## MIT DOC-ZAHLEN NACHGEBAUT statt die Spiel-Statics aufzurufen — der Flow
## rechnet wie ein skeptischer Spieler nach. Weicht das Spiel ab, fällt
## der Schritt rot aus und der Report zeigt beide Zahlen.

## Freischalt-Gate + Kaufpreis des Goobye (Doc §7.2, content/dlc/balance).
const GOOBYE_LEVEL := 12
const GOOBYE_BUDGET := 3000
const GOOBYE_PREIS := 2500

## Doc-Konstanten §2.2/§4.1/§4.2/§7.1 für die eigene Nachrechnung.
const EK_FAKTOR := 0.6
const EIGENMARKE_RABATT := 0.2
const BIO_AUFSCHLAG := 0.1
const STAFFEL_AB := 10
const STAFFEL_RABATT := 0.05
const RAMPEN_RABATT := 0.15
const KOFFERRAUM_MAX := 24
const BACKEN_FAKTOR := 0.5
const BROT_JE_CHARGE := 3
const SLOT_DECKEL := 8

## McGooby-Abrechnung (Doc §2.2.5, content mcgooby_menu.json balance).
const MC_TRINKGELD_BASIS := 2
const MC_COMBO_START := 1.0
const MC_COMBO_SCHRITT := 0.1
const MC_COMBO_MAX := 2.0
const MC_COIN_DIVISOR := 4
const MC_COIN_MIN := 6
const MC_COIN_MAX := 30

## ------------------------------------------------------ Goobye-Kauf-Weg


## Frischer Save → Level 12 + 3000 ᴳ → Einstellungen → DLC-Hub → Karte →
## Angebot → Schlüssel übernehmen (−2500 exakt) → Intro-Karte weggetippt.
func goobye_kauf_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{"name": "level_zwoelf", "aktion": "tue", "funktion": gib_level.bind(GOOBYE_LEVEL)},
				{
					"name": "budget_setzen",
					"aktion": "tue",
					"funktion": gib_coins.bind(GOOBYE_BUDGET)
				},
				{
					"name": "einstellungen_oeffnen",
					"aktion": "tipp_name",
					"node": "SettingsButton",
					"erwarte": {"klasse": "SettingsScreen"},
					"timeout_s": 90.0,
				},
				{"name": "zu_dlc_rollen", "aktion": "tue", "funktion": rolle_zu.bind("DlcButton")},
				{
					"name": "alle_dlcs_ansehen",
					"aktion": "tipp_name",
					"node": "DlcButton",
					"erwarte": {"klasse": "DlcScreen"},
					"timeout_s": 90.0,
				},
				# Bekannte Umgehung (G8-PT2, Befund pt2_d1): das Settings-
				# Overlay bleibt über dem DLC-Hub liegen — Zurück legt frei.
				{"name": "reise_ausrollen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "settings_overlay_schliessen",
					"aktion": "tipp_falls_da",
					"node": "BackButton",
					"erwarte": {"weg_klasse": "SettingsScreen"},
					"timeout_s": 30.0,
				},
				{
					"name": "zu_goobye_rollen",
					"aktion": "tue",
					"funktion": rolle_zu.bind("DlcKarte_goo_und_bye"),
				},
				{
					"name": "goobye_ansehen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_in.bind("DlcKarte_goo_und_bye"),
					"timeout_s": 20.0,
				},
				{
					"name": "detail_da",
					"aktion": "warte_bis",
					"text": "Schlüssel ansehen",
					"timeout_s": 20.0,
				},
			]
		)
	)
	liste.append_array(rolle_schritte("Schlüssel ansehen", "aktionknopf"))
	(
		liste
		. append_array(
			[
				{
					"name": "angebot_oeffnen",
					"aktion": "tipp_name",
					"node": "AktionKnopf",
					"erwarte": {"text": "Schlüssel übernehmen!"},
					"timeout_s": 30.0,
				},
				{
					"name": "kauf_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("kauf")
				},
			]
		)
	)
	liste.append_array(rolle_schritte("Schlüssel übernehmen!", "kaufknopf"))
	(
		liste
		. append_array(
			[
				{
					"name": "schluessel_uebernehmen",
					"aktion": "tipp_name",
					"node": "Kaufen",
					"erwarte": {"route": "dlc/goobye_laden"},
					"timeout_s": 120.0,
				},
				{
					"name": "dlc_preis_abgebucht",
					"aktion": "tue",
					"funktion": pruefe_coins_delta.bind("kauf", -GOOBYE_PREIS),
					"erwartung": "Münzen −2500 nach Schlüssel-Kauf",
				},
				{
					"name": "intro_karte_lesen",
					"aktion": "warte_bis",
					"text": "Die Schlüsselübergabe",
					"timeout_s": 30.0,
				},
				{"name": "schluessel_nehmen", "aktion": "tipp_name", "node": "IntroWeiter"},
				{"name": "laden_umsehen", "aktion": "warte", "sekunden": 3.0},
			]
		)
	)
	return liste


## ---------------------------------------------------------- Szenen-Griffe


func laden_szene() -> Node:
	var szene := aktuelle_szene()
	return szene if szene is GoobyeLadenScene else null


func grossmarkt_szene() -> Node:
	var szene := aktuelle_szene()
	return szene if szene is GoobyeGrossmarktScene else null


func schicht_szene() -> Node:
	var szene := aktuelle_szene()
	return szene if szene is McGoobySchichtScene else null


## Tagesumsatz von der Kassensturz-Karte + Kontostand für den Exakt-Check.
func kassensturz_merken() -> bool:
	var szene := laden_szene()
	if szene == null:
		return false
	merke("umsatz", int(szene.get("umsatz_heute")))
	return merke_coins("feierabend")


func umsatz_gebucht() -> bool:
	return pruefe_coins_delta("feierabend", int(zettel.get("umsatz", 0)))


## Sichtbares Label per Node-Name lesen ("" = nicht da) — für Text-Proben.
func label_text(node_name: String) -> String:
	var node := _finde_sichtbares_control(harness.root, node_name)
	if node == null:
		return ""
	return str(node.get("text"))


## ------------------------------------------------- Eigene Nachrechen-Mathe


## Empfohlener Verkaufspreis (Doc §2.2/§4.1): vk, Eigenmarke −20 %, Bio +10 %.
func mein_empf_preis(ware: Dictionary) -> int:
	var basis := maxf(0.0, float(ware.get("vk", 0)))
	if bool(ware.get("eigenmarke", false)):
		basis *= 1.0 - EIGENMARKE_RABATT
	if bool(ware.get("bio", false)):
		basis *= 1.0 + BIO_AUFSCHLAG
	return maxi(1, roundi(basis))


## Großmarkt-Einkaufspreis = 60 % des empfohlenen Preises (Doc §2.2).
func mein_ek_preis(ware: Dictionary) -> int:
	return maxi(1, roundi(float(mein_empf_preis(ware)) * EK_FAKTOR))


## Rampen-Stückpreis: EK, Tagesangebots-Gruppe −15 % (Doc §4.1).
func mein_rampen_preis(ware: Dictionary, angebot_gruppe: String) -> int:
	var preis := float(mein_ek_preis(ware))
	if not angebot_gruppe.is_empty() and str(ware.get("gruppe", "")) == angebot_gruppe:
		preis *= 1.0 - RAMPEN_RABATT
	return maxi(1, roundi(preis))


## Paletten-Zeile: Stückpreis × Menge, ab 10 Stück −5 % auf die Zeile.
func mein_zeilen_preis(ware: Dictionary, menge: int, angebot_gruppe: String) -> int:
	if menge <= 0:
		return 0
	var summe := float(mein_rampen_preis(ware, angebot_gruppe) * menge)
	if menge >= STAFFEL_AB:
		summe *= 1.0 - STAFFEL_RABATT
	return maxi(1, roundi(summe))


## Ganzer Warenkorb {wareId: menge} mit MEINER Mathe.
func mein_korb_preis(korb: Dictionary, angebot_gruppe: String) -> int:
	var summe := 0
	for ware_id: Variant in korb:
		var ware := GoobyeKatalog.ware(str(ware_id))
		if not ware.is_empty():
			summe += mein_zeilen_preis(ware, int(korb[ware_id]), angebot_gruppe)
	return summe


## Verkaufspreis einer Schieber-Stellung (±30 % geklemmt, Doc §2.2).
func mein_verkaufspreis(ware: Dictionary, faktor: float) -> int:
	var f := clampf(faktor, 0.7, 1.3)
	return maxi(1, roundi(float(mein_empf_preis(ware)) * f))


## Backofen-Selbstkosten (Doc §7.1): 50 % EK × 3 Brote je Charge.
func mein_backen_kosten() -> int:
	var brot := GoobyeKatalog.ware("bread")
	var je_stueck := float(mein_ek_preis(brot)) * BACKEN_FAKTOR
	return maxi(1, roundi(je_stueck * float(BROT_JE_CHARGE)))


## McGooby-Kassensturz nachgerechnet (Doc §2.2.5): Combo-Trinkgeld je
## fehlerfreier Bestellung in Folge + Münz-Tabelle + Bühnen-Trinkgeld.
func meine_mc_abrechnung(ergebnisse: Array, buehne_bonus: int) -> Dictionary:
	var punkte := 0
	var trinkgeld := 0
	var streak := 0
	for eintrag: Variant in ergebnisse:
		if not (eintrag is Dictionary):
			continue
		punkte += maxi(0, int((eintrag as Dictionary).get("punkte", 0)))
		if bool((eintrag as Dictionary).get("fehlerfrei", false)):
			streak += 1
			var mult := minf(MC_COMBO_MAX, MC_COMBO_START + MC_COMBO_SCHRITT * float(streak))
			trinkgeld += int(round(float(MC_TRINKGELD_BASIS) * mult))
		else:
			streak = 0
	trinkgeld += maxi(0, buehne_bonus)
	var basis := clampi(
		int(floor(float(maxi(0, punkte)) / float(MC_COIN_DIVISOR))), MC_COIN_MIN, MC_COIN_MAX
	)
	return {"punkte": punkte, "muenzen_basis": basis, "trinkgeld": trinkgeld}


## ------------------------------------------------------------ Slot-Helfer


## Slot-Füllung simulieren, wie ein Spieler sie erwartet: 5 Taps, jeder
## leere Slot nimmt die ERSTE Katalog-Ware mit Lager-Bestand, Deckel 8.
func erwarteter_regal_stand(lager: Dictionary) -> int:
	var rest := lager.duplicate(true)
	var gesamt := 0
	for _slot in GoobyeRegal.SLOTS:
		var ware_id := ""
		for ware: Dictionary in GoobyeKatalog.waren():
			if int(rest.get(str(ware["id"]), 0)) > 0:
				ware_id = str(ware["id"])
				break
		if ware_id.is_empty():
			break
		var zug := mini(SLOT_DECKEL, int(rest.get(ware_id, 0)))
		gesamt += zug
		rest[ware_id] = int(rest.get(ware_id, 0)) - zug
	return gesamt


## Punkt AUF einem benannten HSlider (rel −0.5…0.5 der Breite); rollt den
## Slider vorher in allen Scroll-Ahnen ins Bild (Sheet clippt doppelt).
func schieber_punkt(gruppe_id: String, rel_x: float) -> Vector2:
	var slider := harness.root.find_child("Schieber_" + gruppe_id, true, false)
	if not (slider is HSlider) or not (slider as HSlider).is_visible_in_tree():
		print("[PTDLC] schieber_punkt: Schieber_%s nicht sichtbar" % gruppe_id)
		return Vector2.ZERO
	_rolle_alle_scroller(slider)
	var rect := (slider as HSlider).get_global_rect()
	return rect.get_center() + Vector2(rect.size.x * rel_x, 0.0)


## gs-Lager als geheilte Kopie ({} ohne GameState).
func gs_lager() -> Dictionary:
	var gs := game_state()
	if gs == null:
		return {}
	var raw: Variant = gs.get_value("dlc.goobye.lager", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


## ------------------------------------------------- Laden-Tag-Bausteine
## (privat, damit die 20-Public-Grenze von gdlint hält — Flows erben sie.)


## Phase der Laden-Szene prüfen ("einraeumen"/"offen"/"abschluss").
func _phase_ist(soll: String) -> bool:
	var szene := laden_szene()
	return szene != null and str(szene.get("phase")) == soll


## Stückzahl im Regal (Summe aller Slots); -1 ohne Laden-Szene.
func _regal_stand() -> int:
	var szene := laden_szene()
	if szene == null:
		return -1
	var regal: Dictionary = szene.get("_regal")
	var summe := 0
	for slot: Dictionary in regal.get("slots", []):
		summe += int(slot.get("menge", 0))
	return summe


## Tagesplan der Laden-Szene als geheilte Kopie ({} ohne Plan).
func _plan_kopie() -> Dictionary:
	var szene := laden_szene()
	if szene == null:
		return {}
	var plan: Variant = szene.get("_tagesplan")
	return (plan as Dictionary).duplicate(true) if plan is Dictionary else {}


## Plan in sich stimmig? (Bon-Positionen == Umsatz, Bons == Kundenzahl.)
func _plan_konsistent(plan: Dictionary) -> bool:
	var bons: Array = plan.get("bons", [])
	var summe := 0
	for bon: Dictionary in bons:
		for position: Dictionary in bon.get("positionen", []):
			summe += int(position.get("preis", 0))
	print(
		(
			"[PTDLC] Plan: %d Kunden, Umsatz %d (Bon-Summe %d), verkauft %s, verpasst %d"
			% [
				int(plan.get("kundenzahl", 0)),
				int(plan.get("umsatz", 0)),
				summe,
				str(plan.get("verkauft", {})),
				int(plan.get("verpasst", 0)),
			]
		)
	)
	return summe == int(plan.get("umsatz", 0)) and bons.size() == int(plan.get("kundenzahl", 0))


## Plan gegen Goldwerte halten ({umsatz, kunden, verkauft} aus der
## Seed-Suche flow_ptdlc_seedsuche — dort mit den ECHTEN Statics gerechnet).
func _plan_wie_gold(plan: Dictionary, gold: Dictionary) -> bool:
	var passt := (
		int(plan.get("umsatz", -1)) == int(gold.get("umsatz", -2))
		and int(plan.get("kundenzahl", -1)) == int(gold.get("kunden", -2))
		and (plan.get("verkauft", {}) as Dictionary) == (gold.get("verkauft", {}) as Dictionary)
	)
	if not passt:
		print("[PTDLC] Plan weicht vom Goldwert ab! Gold: %s" % str(gold))
	return passt


## Kassensturz-Karte gegen den Plan: Umsatz, Kunden- und Artikel-Zeile,
## Regal-Rest (Bestand vor Öffnung minus verkaufte Artikel).
func _kassenkarte_stimmt(plan: Dictionary, regal_vorher: int) -> bool:
	var szene := laden_szene()
	if szene == null:
		return false
	var verkauft := 0
	for menge: Variant in (plan.get("verkauft", {}) as Dictionary).values():
		verkauft += int(menge)
	var umsatz := int(szene.get("umsatz_heute"))
	var regal_soll := regal_vorher - verkauft
	print(
		(
			(
				"[PTDLC] Kassensturz: Umsatz %d (Plan %d), Kunden '%s' (Plan %d), "
				+ "Artikel '%s' (Plan %d), Regal %d (soll %d)"
			)
			% [
				umsatz,
				int(plan.get("umsatz", 0)),
				label_text("Wert_kunden"),
				int(plan.get("kundenzahl", 0)),
				label_text("Wert_artikel"),
				verkauft,
				_regal_stand(),
				regal_soll,
			]
		)
	)
	return (
		umsatz == int(plan.get("umsatz", 0))
		and label_text("Wert_kunden") == str(int(plan.get("kundenzahl", 0)))
		and label_text("Wert_artikel") == str(verkauft)
		and _regal_stand() == regal_soll
	)


## Alwin-Stand {streak, best, bedientGesamt} aus dem Save (geheilte Kopie).
func _alwin_stand() -> Dictionary:
	var gs := game_state()
	if gs == null:
		return {}
	var raw: Variant = gs.get_value("dlc.goobye.alwin", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


## Gruppen-Preisfaktor aus dem Save gegen Sollwert (Schieber-Raster 0,05).
func _faktor_ist(gruppe_id: String, soll: float) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var raw: Variant = gs.get_value("dlc.goobye.preise", {})
	var preise := (raw as Dictionary) if raw is Dictionary else {}
	var ist := float(preise.get(gruppe_id, 1.0))
	print("[PTDLC] Preis-Faktor %s = %.3f (soll %.2f)" % [gruppe_id, ist, soll])
	return absf(ist - soll) < 0.011

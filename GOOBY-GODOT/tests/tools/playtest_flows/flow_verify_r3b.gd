extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## VERIFY-PT R3 Kombi-Flow (b) — W18/R3-Nachmessung: Stadt- und DLC-Fixes
## im ZUSAMMENSPIEL, wie ein Spieler-Nachmittag:
##  1. Stadt: DREI Orte (Goobytheke, Post, Tierarzt) betreten — je Ort die
##     OrtLeben-PFLICHT-Sonde (G8-P1 „Jeder Ort lebt“) + Stadtleben (FIX-5),
##  2. DLC-Hub aus den Einstellungen: das Settings-Overlay muss sich beim
##     Reiseantritt VON ALLEIN schließen (FIX-3/B1 — KEIN Zurück-Umweg!),
##  3. Goobye-Tag: Schlüssel für 2500 ᴳ (Geld exakt), Regal-Slots per
##     ECHTEN Taps (B2-Fix: Backen-Pill schluckte früher die Slot-Taps),
##     eine Ofen-Charge backen + Slot-3-Tap NACH dem Backen, Laden öffnen,
##     Kundenstrom, Feierabend bucht EXAKT den Tagesumsatz,
##  4. zurück im Hub (History-Back) → McGooby-Probeschicht: eine Schicht
##     am Grill, dann die ENDKARTE prüfen (Kassensturz konsistent,
##     Angebot-Block sichtbar, Nochmal-/Feierabend-Knöpfe) und über
##     „Feierabend machen“ zurück in den Hub und nach Hause.
## Aufruf: tools/ci/run_playtest.sh flow_verify_r3b

const LEVEL := 15
const BUDGET := 3000
const DLC_PREIS := 2500
## Startlager: apple 6 + carrot 8 + bread 5 landen in Slot 0–2.
const REGAL_SOLL := 19
## … plus EINE Ofen-Charge (3 Brote) via Slot-3-Tap nach dem Backen.
const REGAL_MIT_BROT := REGAL_SOLL + GoobyeBackofen.BROT_JE_CHARGE
## Fester Seed → deterministische Bestell-Folge in der Probeschicht.
const SEED := 20260802
## Großzügig über dem Maximum (4 Bestellungen × 2 Pattys = 8).
const PATTY_RESERVE := 12


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_kapitel_stadt())
	liste.append_array(_kapitel_hub_aus_settings())
	liste.append_array(_kapitel_goobye_kauf())
	liste.append_array(_kapitel_goobye_laden())
	liste.append_array(_kapitel_mcgooby())
	return liste


# ── Kapitel 1: Stadt — drei Orte mit Leben-Sonden ────────────────────────────


func _kapitel_stadt() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{"name": "level_fuenfzehn", "aktion": "tue", "funktion": gib_level.bind(LEVEL)},
		{"name": "budget_setzen", "aktion": "tue", "funktion": gib_coins.bind(BUDGET)},
		{
			"name": "in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "ausparken_ansehen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "stadtleben_pruefen",
			"aktion": "tue",
			"funktion": stadt_lebt,
			"erwartung": "Verkehr UND Fußgänger unterwegs (FIX-5)",
		},
		{
			"name": "proviant",
			"aktion": "tue",
			"funktion": _energie_voll,
			"erwartung": "Energie voll für den Drei-Orte-Rundgang",
		},
	]
	liste.append_array(_ort_kurz("goobytheke", "OrtGoobytheke"))
	liste.append_array(_ort_kurz("post", "OrtPost"))
	liste.append_array(_ort_kurz("tierarzt", "OrtTierarzt"))
	(
		liste
		. append(
			{
				"name": "nach_hause",
				"aktion": "tipp_text",
				"text": "Nach Hause",
				"erwarte": {"route": "home/living"},
				"timeout_s": 120.0,
			}
		)
	)
	liste.append({"name": "wieder_daheim", "aktion": "warte", "sekunden": 2.0})
	return liste


## Kompakter Orts-Besuch: vorfahren → Prompt → betreten → OrtLeben-Sonde
## (PFLICHT, G8-P1) → verlassen. Ohne Energie-Delta (deckt Rundgang ab).
func _ort_kurz(ort_id: String, klasse: String) -> Array[Dictionary]:
	return [
		{
			"name": "vorfahrt_%s" % ort_id,
			"aktion": "tue",
			"funktion": fahre_zu.bind(ort_id),
			"erwartung": "Auto steht am Parkplatz %s" % ort_id,
		},
		{
			"name": "prompt_%s" % ort_id,
			"aktion": "warte_bis",
			"text": "betreten?",
			"timeout_s": 20.0,
		},
		{
			"name": "betreten_%s" % ort_id,
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"klasse": klasse},
			"timeout_s": 120.0,
		},
		{"name": "umsehen_%s" % ort_id, "aktion": "warte", "sekunden": 3.0},
		{
			"name": "leben_%s" % ort_id,
			"aktion": "tue",
			"funktion": ort_lebt,
			"erwartung": "OrtLeben-Besucher im Laden (G8-P1 „Jeder Ort lebt“)",
		},
		{
			"name": "verlassen_%s" % ort_id,
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "wieder_stadt_%s" % ort_id, "aktion": "warte", "sekunden": 2.0},
	]


# ── Kapitel 2: DLC-Hub aus den Einstellungen (FIX-3/B1-Kern) ─────────────────


func _kapitel_hub_aus_settings() -> Array[Dictionary]:
	return [
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
			"erwarte": {"route": "dlc"},
			"timeout_s": 120.0,
		},
		# FIX-3/B1-Kern: KEIN Zurück-Umweg mehr — das Settings-Overlay
		# muss von allein verschwinden, sobald die Reise durch ist.
		{
			"name": "settings_zu_von_allein",
			"aktion": "warte_bis",
			"weg_klasse": "SettingsScreen",
			"timeout_s": 30.0,
		},
		{"name": "hub_ansehen", "aktion": "warte", "sekunden": 2.0},
	]


# ── Kapitel 3: Goobye-Schlüssel übernehmen (Geld exakt) ──────────────────────


func _kapitel_goobye_kauf() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
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
					"funktion": merke_coins.bind("kauf"),
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
					"funktion": pruefe_coins_delta.bind("kauf", -DLC_PREIS),
					"erwartung": "Münzen −2500 nach Schlüssel-Kauf",
				},
			]
		)
	)
	return liste


# ── Kapitel 4: Goobye-Tag — Slots, Backen, Kundenstrom, Kassensturz ──────────


func _kapitel_goobye_laden() -> Array[Dictionary]:
	return [
		{
			"name": "intro_karte_lesen",
			"aktion": "warte_bis",
			"text": "Die Schlüsselübergabe",
			"timeout_s": 30.0,
		},
		{
			"name": "schluessel_nehmen",
			"aktion": "tipp_name",
			"node": "IntroWeiter",
			"timeout_s": 20.0,
		},
		{"name": "laden_umsehen", "aktion": "warte", "sekunden": 3.0},
		# B2-Fix-Beleg: Slots werden per ECHTEN Taps eingeräumt — vorher
		# lag die „Backen“-Pill quer über Slot 0–2 und schluckte die Taps.
		{
			"name": "slot_0_tippen",
			"aktion": "tipp_name",
			"node": "Slot0",
			"erwarte": {"text": "×6"},
			"timeout_s": 20.0,
		},
		{
			"name": "slot_1_tippen",
			"aktion": "tipp_name",
			"node": "Slot1",
			"erwarte": {"text": "×8"},
			"timeout_s": 20.0,
		},
		{
			"name": "slot_2_tippen",
			"aktion": "tipp_name",
			"node": "Slot2",
			"erwarte": {"text": "×5"},
			"timeout_s": 20.0,
		},
		{
			"name": "regal_bestueckt",
			"aktion": "tue",
			"funktion": _regal_stand.bind(REGAL_SOLL),
			"erwartung": "Startlager (19 Stück) liegt im Regal",
		},
		{
			"name": "backen_coins_merken",
			"aktion": "tue",
			"funktion": merke_coins.bind("backofen"),
		},
		{
			"name": "backen_tippen",
			"aktion": "tipp_name",
			"node": "Backen",
			"timeout_s": 20.0,
		},
		{
			"name": "backofen_bezahlt",
			"aktion": "tue",
			"funktion": _backofen_bezahlt,
			"erwartung": "GENAU eine Charge Selbstkosten abgebucht",
		},
		{
			"name": "slot_3_nach_backen",
			"aktion": "tipp_name",
			"node": "Slot3",
			"erwarte": {"text": "×3"},
			"timeout_s": 20.0,
		},
		{
			"name": "regal_nach_backen",
			"aktion": "tue",
			"funktion": _regal_stand.bind(REGAL_MIT_BROT),
			"erwartung": "Ofen-Charge (3 Brote) liegt in Slot 3",
		},
		{"name": "tag_coins_merken", "aktion": "tue", "funktion": merke_coins.bind("tag")},
		{
			"name": "laden_oeffnen",
			"aktion": "tipp_name",
			"node": "LadenOeffnen",
			"timeout_s": 20.0,
		},
		{"name": "alwin_blase_schauen", "aktion": "warte", "sekunden": 3.0},
		{"name": "kunden_schauen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "kassensturz_karte",
			"aktion": "warte_bis",
			"bedingung": control_da.bind("Feierabend"),
			"timeout_s": 240.0,
		},
		{
			"name": "kassensturz_merken",
			"aktion": "tue",
			"funktion": _kassensturz_merken,
			"erwartung": "Tagesumsatz + Kontostand notiert",
		},
		{
			"name": "feierabend_buchen",
			"aktion": "tipp_name",
			"node": "Feierabend",
			"timeout_s": 20.0,
		},
		{"name": "buchung_abwarten", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "umsatz_exakt_gebucht",
			"aktion": "tue",
			"funktion": _umsatz_gebucht,
			"erwartung": "Feierabend bucht EXAKT den Tagesumsatz aufs Konto",
		},
		{
			"name": "laden_verlassen",
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"weg_klasse": "GoobyeLadenScene"},
			"timeout_s": 120.0,
		},
		# History-Back aus dem Laden muss im DLC-Hub landen (Kette
		# Settings → Hub → Laden → zurück — Übergabe an Kapitel 5).
		{
			"name": "zurueck_im_hub",
			"aktion": "warte_bis",
			"klasse": "DlcScreen",
			"timeout_s": 30.0,
		},
		{"name": "hub_wieder_da", "aktion": "warte", "sekunden": 2.0},
	]


# ── Kapitel 5: McGooby-Probeschicht — Endkarte ───────────────────────────────


func _kapitel_mcgooby() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "zu_mcgooby_rollen",
			"aktion": "tue",
			"funktion": rolle_zu.bind("DlcKarte_mcgooby"),
		},
		{
			"name": "mcgooby_ansehen",
			"aktion": "tipp_pos",
			"pos_funktion": knopf_in.bind("DlcKarte_mcgooby"),
			"timeout_s": 20.0,
		},
		{
			"name": "mcgooby_detail_da",
			"aktion": "warte_bis",
			"text": "Probeschicht starten!",
			"timeout_s": 20.0,
		},
	]
	liste.append_array(rolle_schritte("Probeschicht starten!", "mc_aktionknopf"))
	(
		liste
		. append_array(
			[
				{
					"name": "probeschicht_starten",
					"aktion": "tipp_name",
					"node": "AktionKnopf",
					"erwarte": {"klasse": "McGoobySchichtScene"},
					"timeout_s": 120.0,
				},
				{
					"name": "intro_karte",
					"aktion": "warte_bis",
					"text": "Die große Eröffnung",
					"timeout_s": 30.0,
				},
				{
					"name": "seed_pinnen",
					"aktion": "tue",
					"funktion": szene_prop.bind("seed_override", SEED),
				},
				{
					"name": "schicht_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("schicht"),
				},
				{
					"name": "schuerze_umbinden",
					"aktion": "tipp_name",
					"node": "SchuerzeKnopf",
					"erwarte": {"weg_text": "Die große Eröffnung"},
					"timeout_s": 30.0,
				},
				{"name": "schicht_laeuft", "aktion": "tue", "funktion": _schicht_laeuft},
			]
		)
	)
	liste.append_array(_patty_steps("mc", PATTY_RESERVE))
	(
		liste
		. append_array(
			[
				{
					"name": "endkarte_da",
					"aktion": "warte_bis",
					"text": "Feierabend!",
					"timeout_s": 120.0,
				},
				{"name": "endkarte_setzen", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "endkarte_komplett",
					"aktion": "tue",
					"funktion": _endkarte_ok,
					"erwartung": "Endkarte: Angebot-Block + Nochmal + Feierabend sichtbar",
				},
				{
					"name": "kassensturz_konsistent",
					"aktion": "tue",
					"funktion": _kasse_pruefen.bind("schicht"),
					"erwartung": "muenzen == basis + trinkgeld UND exakt gutgeschrieben",
				},
				{
					"name": "schicht_verbucht",
					"aktion": "tue",
					"funktion": _schicht_verbucht,
					"erwartung": "mcgooby.schichten.gespielt == 1",
				},
				{
					"name": "feierabend_machen",
					"aktion": "tipp_name",
					"node": "Feierabend",
					"erwarte": {"weg_klasse": "McGoobySchichtScene"},
					"timeout_s": 120.0,
				},
				{
					"name": "hub_nach_schicht",
					"aktion": "warte_bis",
					"klasse": "DlcScreen",
					"timeout_s": 30.0,
					"pflicht": false,
				},
				{
					"name": "hub_zurueck",
					"aktion": "tipp_name",
					"node": "Zurueck",
					"timeout_s": 30.0,
				},
				{
					"name": "hub_zurueck_nachfassen",
					"aktion": "tipp_falls_da",
					"node": "Zurueck",
					"timeout_s": 10.0,
					"pflicht": false,
				},
				{
					"name": "wieder_zuhause",
					"aktion": "warte_bis",
					"route": "home/living",
					"timeout_s": 120.0,
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


# ── Stadt-Helfer ─────────────────────────────────────────────────────────────


func _energie_voll() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("gooby.stats.energy", 100.0)
	print("[R3B] Energie auf 100 aufgefüllt")
	return true


# ── Goobye-Helfer (Muster flow_pt2_goobye_tag) ───────────────────────────────


func _laden_szene() -> Node:
	var szene := aktuelle_szene()
	return szene if szene is GoobyeLadenScene else null


func _regal_stand(soll: int) -> bool:
	var szene := _laden_szene()
	if szene == null:
		return false
	var bestand := GoobyeRegal.gesamt_bestand(szene.get("_regal"))
	print("[R3B] Regal-Bestand: %d (soll %d)" % [bestand, soll])
	return bestand == soll


func _backofen_bezahlt() -> bool:
	return pruefe_coins_delta("backofen", -GoobyeBackofen.kosten())


func _kassensturz_merken() -> bool:
	var szene := _laden_szene()
	if szene == null:
		return false
	merke("umsatz", int(szene.get("umsatz_heute")))
	return merke_coins("feierabend")


func _umsatz_gebucht() -> bool:
	return pruefe_coins_delta("feierabend", int(zettel.get("umsatz", 0)))


# ── McGooby-Helfer (Muster flow_pt2_mcgooby) ─────────────────────────────────


## Reserve-Schritte: jeder wendet (falls die Schicht noch läuft) EINEN
## Patty deterministisch perfekt — Überzählige melden nur „nichts zu tun“.
func _patty_steps(prefix: String, anzahl: int) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for i in range(anzahl):
		(
			steps
			. append(
				{
					"name": "%s_patty_%02d" % [prefix, i + 1],
					"aktion": "tue",
					"funktion": _patty_perfekt,
					"pflicht": false,
				}
			)
		)
	return steps


func _schicht_szene() -> Node:
	var szene := aktuelle_szene()
	return szene if szene is McGoobySchichtScene else null


func _schicht_laeuft() -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	var folge: Array = szene.get("_folge")
	print("[R3B] Schicht läuft: %d Bestellungen im Plan" % folge.size())
	return bool(szene.call("ist_am_laufen"))


## EIN Patty deterministisch perfekt wenden: Brat-Zeit in die Mitte des
## goldenen Fensters pinnen (Test-API der Szene), dann der Knopfdruck.
func _patty_perfekt() -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	if bool(szene.call("ist_ende_offen")):
		print("[R3B] Schicht vorbei — nichts mehr zu braten")
		return true
	if not bool(szene.call("ist_am_laufen")):
		print("[R3B] Schicht läuft nicht (pausiert?)")
		return false
	var timing: Dictionary = szene.get("_patty_timing")
	var mitte := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.4)) * 0.5
	szene.call("patty_zeit_setzen", mitte)
	var knopf: Button = szene.call("patty_knopf")
	if knopf == null:
		return false
	knopf.pressed.emit()
	print("[R3B] Patty gewendet bei %.2f s → Punkte %d" % [mitte, int(szene.get("_punkte"))])
	return true


## Endkarten-Probe: Angebot-Block (Level 15 ≥ Gate 14, nicht gekauft →
## sichtbar), „Nochmal“- und „Feierabend“-Knopf müssen alle stehen.
func _endkarte_ok() -> bool:
	var angebot := control_da("AngebotBlock")
	var nochmal := control_da("Nochmal")
	var feierabend := control_da("Feierabend")
	print(
		(
			"[R3B] Endkarte: Angebot=%s Nochmal=%s Feierabend=%s"
			% [str(angebot), str(nochmal), str(feierabend)]
		)
	)
	return angebot and nochmal and feierabend


## Kassensturz: Summe stimmig UND Münzen exakt aufs Konto (Delta seit Marke).
func _kasse_pruefen(marke: String) -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	var kasse: Dictionary = szene.call("schicht_ergebnis")
	print("[R3B] Kasse: %s" % str(kasse))
	var basis := int(kasse.get("muenzen_basis", 0))
	var trinkgeld := int(kasse.get("trinkgeld", 0))
	var summe := int(kasse.get("muenzen", 0))
	if summe != basis + trinkgeld:
		print("[R3B] Kassensturz inkonsistent: %d != %d + %d" % [summe, basis, trinkgeld])
		return false
	return pruefe_coins_delta(marke, summe)


func _schicht_verbucht() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var gespielt := int(gs.get_value("mcgooby.schichten.gespielt", 0))
	print("[R3B] Schichten gespielt: %d (soll 1)" % gespielt)
	return gespielt == 1

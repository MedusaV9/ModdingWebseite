extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W18/3-Playtest (Agent 5) — Flow „McGooby-Probeschicht“: über den DLC-Hub
## zur Schicht reisen (McGooby ist Welle A frei), Eröffnungs-Story-Karte
## („Schürze umbinden!“), dann die Bestell-Folge durchspielen: 1 Tap zu
## früh (roh, straffrei), 1 Patty ABSICHTLICH verkohlen (Röstaroma-
## Spezial, halbe Punkte), alle weiteren Aktionen PERFEKT (goldenes Fenster
## via Test-API patty_zeit_setzen — llvmpipe-FPS machen Echtzeit-Fenster
## unspielbar), Kassensturz-Karte mit Trinkgeld-Combo (>×1,0) und exakter
## Münz-Gegenprobe, „Feierabend machen“.
##
## Seit Welle B/C spannt die Probeschicht ALLE Stationen auf: jede Burger-
## Bestellung endet an der Belegstation (Zutaten-Wische in Ticket-Folge),
## Bestellung 2 kommt garantiert vom neuen Tresen (Fritteuse/Shake —
## Timing-Runden wie am Grill, patty_knopf() liefert stets den aktiven
## Stations-Knopf). patty_perfekt spielt deshalb EINE Perfekt-Aktion der
## JEWEILIGEN Phase; der Rest-Block läuft, bis die Ende-Karte steht.
## Aufruf: tools/ci/run_playtest.sh flow_w18_mcgooby_schicht

## Münzstand beim Schichtstart (Kassensturz-Gegenprobe).
var _muenzen_vor_schicht := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(schritte_zur_bibliothek())
	liste.append_array(schritte_detail_oeffnen("mcgooby", "Probeschicht starten"))
	liste.append_array(_schritte_anreise_und_intro())
	liste.append_array(_schritte_pattys())
	liste.append_array(_schritte_kassensturz())
	return liste


func _schritte_anreise_und_intro() -> Array[Dictionary]:
	return [
		{
			"name": "schicht_anreisen",
			"aktion": "tipp_text",
			"text": "Probeschicht starten",
			"erwarte": {"route": "mcgooby_schicht"},
			"timeout_s": 180.0,
		},
		{
			"name": "intro_karte_da",
			"aktion": "warte_bis",
			"text": "Schürze umbinden",
			"timeout_s": 60.0,
		},
		{"name": "intro_lesen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "schicht_muenzen_merken",
			"aktion": "tue",
			"funktion": merke_vor_schicht,
			"erwartung": "Münzstand vor der Schicht notiert",
		},
		{
			"name": "schuerze_umbinden",
			"aktion": "tipp_name",
			"node": "SchuerzeKnopf",
			"erwarte": {"bedingung": schicht_laeuft},
			"timeout_s": 30.0,
		},
		{
			"name": "bestellfolge_pruefen",
			"aktion": "tue",
			"funktion": mindestens_zwei_bestellungen,
			"erwartung": "Tages-Seed liefert >= 2 Bestellungen (Balance 2..4)",
		},
		{"name": "grill_ansehen", "aktion": "warte", "sekunden": 1.5},
	]


## Patty-Dramaturgie: zu früh (straffrei) → verkohlt (Röstaroma) →
## 2 einzelne Perfekt-Wendungen mit Screenshot-Ruhe → Rest im Block.
func _schritte_pattys() -> Array[Dictionary]:
	return [
		{
			"name": "patty_zeit_null",
			"aktion": "tue",
			"funktion": patty_zeit_zuruecksetzen,
			"erwartung": "Brat-Zeit auf 0 gepinnt (roh)",
		},
		{
			"name": "patty_tap_zu_frueh",
			"aktion": "tipp_name",
			"node": "PattyKnopf",
			"pflicht": false,
		},
		# Diagnose (weich): der Früh-Tap hat den Roh-Callout gezeigt. Weich,
		# weil llvmpipe-Frames die Brat-Zeit real weiterticken lassen — kippt
		# der Zustand vorher auf goldbraun, räumt der Fix den Callout schon.
		{
			"name": "roh_callout_da",
			"aktion": "warte_bis",
			"bedingung": roh_callout_sichtbar,
			"timeout_s": 5.0,
			"pflicht": false,
		},
		{"name": "roh_callout_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "patty_verkohlen_lassen",
			"aktion": "tue",
			"funktion": patty_zeit_auf_kohle,
			"erwartung": "Brat-Zeit hinter das goldene Fenster gepinnt (Kohle)",
		},
		# W18/4-Wache (Callout-Fix): „noch roh!“ gilt nur für den ROHEN
		# Patty — nach dem Zustandswechsel auf Kohle ist der Früh-Tap-
		# Hinweis geräumt (vorher stand er als Lügen-Callout darüber).
		{
			"name": "roh_callout_geraeumt",
			"aktion": "tue",
			"funktion": roh_callout_geraeumt,
			"erwartung": "Kein „noch roh!“-Callout mehr über dem Kohle-Patty",
		},
		{
			"name": "patty_kohle_tap",
			"aktion": "tipp_name",
			"node": "PattyKnopf",
			"erwarte": {"text": "Röstaroma"},
			"timeout_s": 20.0,
		},
		{"name": "kohle_callout_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "patty_perfekt_1",
			"aktion": "tue",
			"funktion": patty_perfekt,
			"erwartung": "Perfekt-Aktion (Wendung oder Belegen-Wisch)",
		},
		{"name": "perfekt_callout_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "patty_perfekt_2",
			"aktion": "tue",
			"funktion": patty_perfekt,
			"erwartung": "Zweite Perfekt-Aktion (oder Schicht schon fertig)",
		},
		{"name": "perfekt_2_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "rest_perfekt_wenden",
			"aktion": "tue",
			"funktion": restliche_pattys_perfekt,
			"erwartung": "Alle restlichen Aktionen perfekt, Schicht endet",
		},
	]


func _schritte_kassensturz() -> Array[Dictionary]:
	return [
		{
			"name": "kassensturz_karte",
			"aktion": "warte_bis",
			"text": "Feierabend!",
			"timeout_s": 60.0,
		},
		{"name": "kassensturz_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "trinkgeld_und_muenzen",
			"aktion": "tue",
			"funktion": kassensturz_ok,
			"erwartung": "Trinkgeld > 0, Combo > ×1,0, Münzen exakt gutgeschrieben",
		},
		{
			"name": "feierabend_machen",
			"aktion": "tipp_name",
			"node": "Feierabend",
			"erwarte": {"weg_text": "Feierabend machen"},
			"timeout_s": 90.0,
		},
		{"name": "abschluss_ruhe", "aktion": "warte", "sekunden": 2.0},
	]


func merke_vor_schicht() -> bool:
	_muenzen_vor_schicht = muenzstand()
	return _muenzen_vor_schicht >= 0


func schicht_laeuft() -> bool:
	var szene := aktuelle_szene()
	return szene != null and szene.has_method("ist_am_laufen") and bool(szene.ist_am_laufen())


func mindestens_zwei_bestellungen() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var folge: Variant = szene.get("_folge")
	return folge is Array and (folge as Array).size() >= 2


## Brat-Zeit auf 0 pinnen (sicher roh für den Zu-früh-Tap — echte Frames
## kosten unter llvmpipe je ~0,3-0,5 s, das Fenster wäre sonst Glückssache).
func patty_zeit_zuruecksetzen() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("patty_zeit_setzen"):
		return false
	szene.patty_zeit_setzen(0.0)
	return true


## Text des Grill-Callouts (" " = leer/geräumt).
func _callout_text() -> String:
	var szene := aktuelle_szene()
	if szene == null:
		return ""
	var callout: Variant = szene.get("_callout")
	if not (callout is Label):
		return ""
	return (callout as Label).text


func roh_callout_sichtbar() -> bool:
	return _callout_text() == I18nService.t("dlc_mcgooby.schicht.roh")


## W18/4-Wache: nach dem Verkohlen zeigt der Callout KEIN „noch roh!“ mehr.
func roh_callout_geraeumt() -> bool:
	var text := _callout_text()
	print("[FLOW-DIAG] callout nach kohle='%s'" % text)
	return text != I18nService.t("dlc_mcgooby.schicht.roh")


## Brat-Zeit HINTER das goldene Fenster pinnen — der folgende echte Tap
## trifft garantiert Kohle (Zustand bleibt Kohle, Zeit läuft nur vorwärts).
func patty_zeit_auf_kohle() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("patty_zeit_setzen"):
		return false
	var timing: Variant = szene.get("_patty_timing")
	if not (timing is Dictionary):
		return false
	var t: Dictionary = timing
	szene.patty_zeit_setzen(float(t.get("gar_sec", 4.0)) + float(t.get("fenster_sec", 1.4)) + 0.5)
	return true


## EINE Perfekt-Aktion der AKTUELLEN Phase: Timing-Runden (Grill/Fritteuse/
## Shake-Bar) per Zeit-Pinnen in die Fenster-Mitte + Knopf-Signal im SELBEN
## Frame (deterministisch); die Belegstation (seit Welle B Teil jeder
## Burger-Bestellung) per korrektem Zutaten-Wisch in Ticket-Reihenfolge.
## true auch, wenn die Schicht schon vorbei ist (Bestell-Folge ist
## seed-abhängig 2..4 Bestellungen kurz).
func patty_perfekt() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("patty_zeit_setzen"):
		return false
	if bool(szene.ist_ende_offen()):
		return true
	if str(szene.phase_aktuell()) == "belegen":
		return _zutat_korrekt_wischen(szene)
	if not bool(szene.get("_patty_aktiv")):
		return false
	var timing: Dictionary = szene.get("_patty_timing")
	var mitte := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.4)) * 0.5
	szene.patty_zeit_setzen(mitte)
	(szene.patty_knopf() as Button).pressed.emit()
	return true


## Korrekten Zutaten-Wisch der Belegstation auslösen (Knopf-Signal — die
## barrierefreie Tap-Geste des Spiels, §2.2.7; Knöpfe heißen Zutat_<id>).
func _zutat_korrekt_wischen(szene: Node) -> bool:
	var ticket: Array = szene.belegen_ticket()
	var idx := int(szene.belegen_platziert())
	if idx >= ticket.size():
		return false
	for knopf: Button in szene.zutaten_knoepfe():
		if String(knopf.name) == "Zutat_" + str(ticket[idx]):
			knopf.pressed.emit()
			return true
	return false


## Alle restlichen Aktionen perfekt (Wenden, Belegen-Wische, Fritten-Züge,
## Shake-Stopps — synchron verkettet: jede Aktion startet sofort die
## nächste Runde/Phase); Schleife hart auf 60 begrenzt (4 Bestellungen ×
## wenige Aktionen bleiben weit darunter).
func restliche_pattys_perfekt() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	for _i in 60:
		if bool(szene.ist_ende_offen()):
			return true
		if not patty_perfekt():
			return false
	return bool(szene.ist_ende_offen())


## Kassensturz-Gegenprobe: Trinkgeld-Combo hat gezogen (alle Bestellungen
## nach der Kohle-Bestellung fehlerfrei → Combo > ×1,0, Trinkgeld > 0) und
## GENAU kasse.muenzen kamen aufs Konto.
func kassensturz_ok() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("schicht_ergebnis"):
		return false
	var kasse: Dictionary = szene.schicht_ergebnis()
	if int(kasse.get("trinkgeld", -1)) <= 0:
		return false
	if float(kasse.get("combo_max_mult", 0.0)) <= 1.0:
		return false
	if _muenzen_vor_schicht < 0:
		return false
	return muenzstand() == _muenzen_vor_schicht + int(kasse.get("muenzen", 0))

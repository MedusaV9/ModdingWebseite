extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18/3 Playtest Agent 6 — Flow (a) „Onboarding-Volldurchlauf frischer Save“:
## Boot → Cover → Onboarding (Name → Spitzname → Editor) → Haus. Prüft die
## W18-Fixes im echten Durchlauf: Karten mittig + im Canvas, Weiter/
## Überspringen physisch erreichbar (≥ 44 pt), KEIN Overlay-Stau (Guide-
## Karte duckt sich unter Tagesbonus/Coachmark, OverlayDirigent), Guide-
## Karte höhen-gedeckelt (MAX_HOEHE_ANTEIL 0,42) und duckt sich über den
## Einstellungen; nach „Tour beenden“ settelt die „Was nun?“-Karte klein
## und scharf (E1/W18) statt als Kilometersäule.
## Aufruf: tools/ci/run_playtest.sh flow_w18a6_onboarding

## Toleranz der Mittigkeit als Canvas-Anteil (2 %).
const MITTIG_TOLERANZ := 0.02
## W18-Höhendeckel der Guide-Karte (0,42) + Messluft.
const KARTEN_DECKEL_ANTEIL := 0.45
## Physisches Tippflächen-Minimum in pt (44 minus Messluft).
const TOUCH_MIN_PT := 43.5


func schritte() -> Array[Dictionary]:
	return [
		{
			"name": "boot_bis_onboarding",
			"aktion": "warte_bis",
			"klasse": "OnboardingFlow",
			"timeout_s": 240.0,
		},
		{
			"name": "karte_name_mittig",
			"aktion": "tue",
			"funktion": pruefe_karte_mittig.bind("NameEdit", "WelcomeNext"),
			"erwartung": "Namens-Karte mittig, Weiter-Knopf erreichbar",
			"pflicht": false,
		},
		{"name": "name_eingeben", "aktion": "eingabe", "node": "NameEdit", "text": "Pionier"},
		{"name": "welcome_weiter", "aktion": "tipp_name", "node": "WelcomeNext"},
		{
			"name": "karte_spitzname_mittig",
			"aktion": "tue",
			"funktion": pruefe_karte_mittig.bind("NicknameEdit", "NicknameNext"),
			"erwartung": "Spitznamen-Karte mittig, Weiter-Knopf erreichbar",
			"pflicht": false,
		},
		{
			"name": "spitzname_eingeben",
			"aktion": "eingabe",
			"node": "NicknameEdit",
			"text": "Goobster",
		},
		{"name": "spitzname_weiter", "aktion": "tipp_name", "node": "NicknameNext"},
		{"name": "editor_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "karte_editor_mittig",
			"aktion": "tue",
			"funktion": pruefe_karte_mittig.bind("EditorNext", "EditorNext"),
			"erwartung": "Editor-Karte mittig, Weiter-Knopf erreichbar",
			"pflicht": false,
		},
		{"name": "editor_weiter", "aktion": "tipp_name", "node": "EditorNext"},
		{
			"name": "onboarding_fertig",
			"aktion": "tipp_name",
			"node": "DoneButton",
			"erwarte": {"route": "home/living"},
			"timeout_s": 180.0,
		},
		{"name": "wohnzimmer_ankommen", "aktion": "warte", "sekunden": 2.0},
		# W18/J1: Der Overlay-Dirigent spielt die Willkommens-Overlays
		# NACHEINANDER — Tagesbonus, Coachmark, dann kehrt die Tour zurück.
		{
			"name": "tagesbonus_warten",
			"aktion": "warte_bis",
			"text": "Abholen!",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{
			"name": "kein_stau_unterm_bonus",
			"aktion": "tue",
			"funktion": pruefe_kein_overlay_stau,
			"erwartung": "Guide-Karte duckt sich unter dem Tagesbonus",
			"pflicht": false,
		},
		{
			"name": "tagesbonus_abholen",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{
			"name": "coachmark_warten",
			"aktion": "warte_bis",
			"text": "Alles klar!",
			"timeout_s": 25.0,
			"pflicht": false,
		},
		{
			"name": "kein_stau_unterm_coachmark",
			"aktion": "tue",
			"funktion": pruefe_kein_overlay_stau,
			"erwartung": "Guide-Karte duckt sich unter dem Coachmark",
			"pflicht": false,
		},
		{
			"name": "coachmark_wegtippen",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 8.0,
			"pflicht": false,
		},
		# Befund B1 (Lauf 1): der Tagesbonus kann auf frischen Saves NACH dem
		# Coachmark einreihen (invertierte Dirigent-Reihenfolge) und blockiert
		# dann die Tour-Karte — hier abräumen, damit der Rest messbar bleibt.
		{
			"name": "spaeter_tagesbonus",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 45.0,
			"pflicht": false,
		},
		{
			"name": "guide_karte_zurueck",
			"aktion": "warte_bis",
			"bedingung": guide_karte_sichtbar,
			"timeout_s": 60.0,
		},
		{
			"name": "guide_karte_geometrie",
			"aktion": "tue",
			"funktion": pruefe_guide_karte,
			"erwartung": "Karte gedeckelt + mittig, Knöpfe >= 44 pt",
			"pflicht": false,
		},
		{"name": "guide_los", "aktion": "tipp_name", "node": "GuideWeiter", "timeout_s": 20.0},
		{"name": "schritt2_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "guide_karte_geometrie_s2",
			"aktion": "tue",
			"funktion": pruefe_guide_karte,
			"erwartung": "Karte bleibt gedeckelt + mittig (Schritt 2)",
			"pflicht": false,
		},
		{
			"name": "guide_skip_1",
			"aktion": "tipp_name",
			"node": "GuideUeberspringen",
			"timeout_s": 20.0,
		},
		{"name": "skip_wirkt", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "guide_skip_2",
			"aktion": "tipp_name",
			"node": "GuideUeberspringen",
			"timeout_s": 20.0,
		},
		{"name": "skip2_wirkt", "aktion": "warte", "sekunden": 1.5},
		# W18 Befund 1: über Einstellungen (HUD versteckt OHNE Travel) muss
		# sich die Tour-Karte ducken und danach von selbst zurückkommen.
		{
			"name": "einstellungen_oeffnen",
			"aktion": "tipp_name",
			"node": "SettingsButton",
			"erwarte": {"klasse": "SettingsScreen"},
			"timeout_s": 30.0,
		},
		{
			"name": "guide_duckt_sich",
			"aktion": "tue",
			"funktion": pruefe_guide_geduckt,
			"erwartung": "Guide-Karte über den Einstellungen unsichtbar",
			"pflicht": false,
		},
		{
			"name": "einstellungen_zu",
			"aktion": "tipp_name",
			"node": "BackButton",
			"erwarte": {"weg_klasse": "SettingsScreen"},
			"timeout_s": 20.0,
		},
		{
			"name": "guide_kommt_zurueck",
			"aktion": "warte_bis",
			"bedingung": guide_karte_sichtbar,
			"timeout_s": 20.0,
			"pflicht": false,
		},
		{
			"name": "tour_beenden",
			"aktion": "tipp_name",
			"node": "GuideBeenden",
			"timeout_s": 20.0,
		},
		{
			"name": "wasnun_erscheint",
			"aktion": "warte_bis",
			"bedingung": wasnun_sichtbar,
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{
			"name": "wasnun_settelt",
			"aktion": "tue",
			"funktion": pruefe_wasnun_gesettelt,
			"erwartung": "Was-nun-Karte klein, scharf und im Canvas",
			"pflicht": false,
		},
		{
			"name": "wasnun_schliessen",
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{"name": "frei_spielen", "aktion": "warte", "sekunden": 3.0},
	]


## ------------------------------------------------------------- Werkzeuge


func _control(node_name: String) -> Control:
	var treffer := harness.root.find_child(node_name, true, false)
	return treffer as Control


func _sichtbar(node_name: String) -> bool:
	var ctl := _control(node_name)
	return ctl != null and ctl.is_visible_in_tree()


## Sichtbaren Knopf/Label mit Text finden (fürs Overlay-Stau-Urteil).
func _text_sichtbar(nadel: String) -> bool:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is Button and str((aktuell as Button).text).contains(nadel):
			return true
		if aktuell is Label and (aktuell as Label).text.contains(nadel):
			return true
		for kind in aktuell.get_children():
			stapel.append(kind)
	return false


## ------------------------------------------------------------- Prüfungen


## Onboarding-Karte: Anker-Element sichtbar, Karten-Panel im Canvas und
## horizontal mittig; der Weiter-Knopf komplett im Canvas.
func pruefe_karte_mittig(anker_name: String, knopf_name: String) -> bool:
	var anker := _control(anker_name)
	if anker == null or not anker.is_visible_in_tree():
		print("[A6] Anker %s nicht sichtbar" % anker_name)
		return false
	var karte: Control = anker
	var n: Node = anker
	while n != null:
		if n is PanelContainer:
			karte = n
			break
		n = n.get_parent()
	var sicht := harness.root.get_visible_rect()
	var rect := karte.get_global_rect()
	var dx := absf(rect.get_center().x - sicht.size.x / 2.0)
	var drin := sicht.grow(2.0).encloses(rect)
	var knopf := _control(knopf_name)
	var knopf_drin := (
		knopf != null
		and knopf.is_visible_in_tree()
		and sicht.grow(2.0).encloses(knopf.get_global_rect())
	)
	print(
		(
			"[A6] Karte %s rect=%s dx=%.1f drin=%s knopf_drin=%s"
			% [anker_name, str(rect), dx, drin, knopf_drin]
		)
	)
	return drin and knopf_drin and dx <= sicht.size.x * MITTIG_TOLERANZ


## Overlay-Stau: solange Tagesbonus („Abholen!“) oder Coachmark („Alles
## klar!“) zu sehen ist, darf die Guide-Karte NICHT sichtbar sein.
func pruefe_kein_overlay_stau() -> bool:
	var bonus := _text_sichtbar("Abholen!")
	var coachmark := _text_sichtbar("Alles klar!")
	var guide := _sichtbar("GuideKarte")
	print("[A6] Overlay-Lage: bonus=%s coachmark=%s guide=%s" % [bonus, coachmark, guide])
	if not bonus and not coachmark:
		return true
	return not guide


func guide_karte_sichtbar() -> bool:
	return _sichtbar("GuideKarte")


func pruefe_guide_geduckt() -> bool:
	var geduckt := not _sichtbar("GuideKarte")
	print("[A6] Guide geduckt=%s" % geduckt)
	return geduckt


## W18-Geometrie der Guide-Karte: Höhe <= 45 % Canvas, komplett im Canvas,
## horizontal mittig in der Hint-Lane, Knöpfe physisch >= 44 pt.
func pruefe_guide_karte() -> bool:
	var karte := _control("GuideKarte")
	if karte == null or not karte.is_visible_in_tree():
		print("[A6] GuideKarte fehlt")
		return false
	var sicht := harness.root.get_visible_rect()
	var rect := karte.get_global_rect()
	var ok_hoehe := rect.size.y <= sicht.size.y * KARTEN_DECKEL_ANTEIL
	var ok_drin := sicht.grow(2.0).encloses(rect)
	var px_pro_pt := UiScale.touch_px_per_pt(karte.get_viewport())
	var ok_knoepfe := true
	for knopf_name: String in ["GuideBeenden", "GuideWeiter", "GuideUeberspringen"]:
		var knopf := _control(knopf_name)
		if knopf == null or not knopf.is_visible_in_tree():
			continue
		var kurz := minf(knopf.get_global_rect().size.x, knopf.get_global_rect().size.y)
		var pt := kurz / maxf(px_pro_pt, 0.001)
		print("[A6] Guide-Knopf %s kurzseite=%.1f px = %.1f pt" % [knopf_name, kurz, pt])
		if pt < TOUCH_MIN_PT:
			ok_knoepfe = false
	print(
		(
			"[A6] GuideKarte rect=%s hoehe_ok=%s drin=%s knoepfe_ok=%s"
			% [str(rect), ok_hoehe, ok_drin, ok_knoepfe]
		)
	)
	return ok_hoehe and ok_drin and ok_knoepfe


func wasnun_sichtbar() -> bool:
	return _sichtbar("WasNunKarte")


## E1/W18: gesettelte „Was nun?“-Karte — klein (< 45 % Canvas-Höhe, < 60 %
## Breite), voll deckend (scharfgeschaltet) und komplett im Canvas.
func pruefe_wasnun_gesettelt() -> bool:
	var karte := _control("WasNunKarte")
	if karte == null or not karte.is_visible_in_tree():
		print("[A6] WasNunKarte fehlt")
		return false
	var sicht := harness.root.get_visible_rect()
	var rect := karte.get_global_rect()
	var ok_klein := (
		rect.size.y <= sicht.size.y * KARTEN_DECKEL_ANTEIL and rect.size.x <= sicht.size.x * 0.6
	)
	var ok_drin := sicht.grow(2.0).encloses(rect)
	var ok_scharf := karte.modulate.a >= 0.99
	print(
		(
			"[A6] WasNun rect=%s klein=%s drin=%s scharf=%s (a=%.2f)"
			% [str(rect), ok_klein, ok_drin, ok_scharf, karte.modulate.a]
		)
	)
	return ok_klein and ok_drin and ok_scharf

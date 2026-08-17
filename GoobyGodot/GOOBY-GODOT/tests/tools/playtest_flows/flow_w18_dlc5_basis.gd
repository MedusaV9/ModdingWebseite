extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Basisklasse der W18/3-DLC-Playtest-Flows (Agent 5) — KEIN eigenständig
## startbarer Flow: gemeinsame Bausteine für DLC-Hub-Navigation (Settings →
## „Alle DLCs ansehen“ → Bibliothek → Karten-Detail), Test-Staging
## (Level/Münzen setzen — dokumentierter Griff, Muster flow_garderobe/
## flow_gestalten) und Scroll-Helfer. KEIN Test (kein test_-Präfix),
## reines Playtest-Werkzeug wie flow_mg_basis.gd.


## Test-Staging: Spieler-Level und Münzstand direkt setzen (DLC-Gates
## brauchen Level 12/15 + 2500 ᴳ — erlaubte Test-Absicht laut Auftrag).
func stage_level_muenzen(level: int, muenzen: int) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", muenzen)
	return true


## Aktueller Münzstand (-1 = GameState fehlt).
func muenzstand() -> int:
	var gs := game_state()
	return int(gs.get_value("economy.coins", -1)) if gs != null else -1


## Control per Node-Name in sein ScrollContainer-Sichtfenster holen
## (deterministisch, Muster flow_mg_basis.kachel_einblenden).
func scrolle_zu(node_name: String) -> bool:
	var ziel := harness.root.find_child(node_name, true, false)
	if not (ziel is Control):
		return false
	var knoten: Node = ziel
	while knoten != null and not (knoten is ScrollContainer):
		knoten = knoten.get_parent()
	if knoten == null:
		return false
	(knoten as ScrollContainer).ensure_control_visible(ziel as Control)
	return true


## DLC-Karte einer Id ins Scroll-Fenster holen (DlcScreen-Bibliothek).
func karte_einblenden(dlc_id: String) -> bool:
	return scrolle_zu("DlcKarte_" + dlc_id)


## Mitte des „Ansehen“-Knopfs der Karte <id> (Canvas-Koordinaten für
## tipp_pos) — Vector2.ZERO, wenn Karte/Knopf fehlen.
func ansehen_knopf_pos(dlc_id: String) -> Vector2:
	var karte := harness.root.find_child("DlcKarte_" + dlc_id, true, false)
	if karte == null:
		return Vector2.ZERO
	var knopf := karte.find_child("Ansehen", true, false)
	if not (knopf is Control):
		return Vector2.ZERO
	return (knopf as Control).get_global_rect().get_center()


## Schritte: HUD-Zahnrad → Settings-Screen → DLC-Sektion sichtbar machen →
## „Alle DLCs ansehen“ → DLC-Bibliothek (Route `dlc`).
## BEFUND B2 GEFIXT (W18/4): dlc_sektion räumt den Settings-Screen jetzt
## selbst über back_pressed ab, bevor sie routet — der frühere
## Workaround-Schritt (`settings_overlay_schliessen`) ist RAUS, und der
## Wächter-Schritt `settings_overlay_weg` beweist den echten Weg: nach dem
## Routenwechsel darf KEIN SettingsScreen mehr sichtbar sein.
func schritte_zur_bibliothek() -> Array[Dictionary]:
	return [
		{
			"name": "settings_oeffnen",
			"aktion": "tipp_name",
			"node": "SettingsButton",
			"erwarte": {"klasse": "SettingsScreen"},
			"timeout_s": 90.0,
		},
		{"name": "settings_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "dlc_sektion_einblenden",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("DlcButton"),
			"erwartung": "Settings-Sektion DLC liegt im Scroll-Fenster",
		},
		{"name": "dlc_sektion_ruhe", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "dlc_bibliothek_oeffnen",
			"aktion": "tipp_name",
			"node": "DlcButton",
			"erwarte": {"route": "dlc"},
			"timeout_s": 90.0,
		},
		{
			"name": "settings_overlay_weg",
			"aktion": "warte_bis",
			"weg_klasse": "SettingsScreen",
			"timeout_s": 15.0,
		},
		{"name": "bibliothek_ansehen", "aktion": "warte", "sekunden": 2.5},
	]


## Schritte: Karte <id> einblenden + „Ansehen“ tippen; das Detail-Sheet
## steht, sobald `erwarte_text` sichtbar ist (Aktions-Knopf-Beschriftung).
## BEFUND B4 GEFIXT (W18/4): der Aktionsbereich sitzt jetzt GEPINNT im
## Blatt-Fuß (PanelSheet.add_footer) und ist in beiden Leitformaten ohne
## Scrollen sichtbar — der frühere Workaround-Schritt
## (`scrolle_zu("AktionKnopf")`) ist RAUS; die Folge-Schritte tippen den
## Knopf direkt und beweisen damit den echten Weg.
func schritte_detail_oeffnen(dlc_id: String, erwarte_text: String) -> Array[Dictionary]:
	return [
		{
			"name": "karte_%s_einblenden" % dlc_id,
			"aktion": "tue",
			"funktion": karte_einblenden.bind(dlc_id),
			"erwartung": "DlcKarte_%s existiert und liegt im Scroll-Fenster" % dlc_id,
		},
		{"name": "karte_%s_ruhe" % dlc_id, "aktion": "warte", "sekunden": 1.0},
		{
			"name": "detail_%s_oeffnen" % dlc_id,
			"aktion": "tipp_pos",
			"pos_funktion": ansehen_knopf_pos.bind(dlc_id),
			"erwarte": {"text": erwarte_text},
			"timeout_s": 30.0,
		},
		{"name": "detail_%s_ansehen" % dlc_id, "aktion": "warte", "sekunden": 1.5},
	]


## Schritt: offenes PanelSheet schließen — per Backdrop-Tap OBERHALB der
## Blattkante (Dim-Bereich). ACHTUNG BEFUND B3 (w18a5_hub): der dokumentierte
## Runterwisch-zum-Schließen (PanelSheet G7/P53) griff im Harness-Lauf im
## Inhaltsbereich NICHT (Sheet blieb offen, Lauf w18a5_hub Schritt 030),
## und das Sheet hat keinen X-Knopf — der Backdrop-Tap ist der einzige
## nachweislich funktionierende Spieler-Schließweg.
func schritt_sheet_schliessen(schritt_name: String) -> Dictionary:
	return {
		"name": schritt_name,
		"aktion": "tipp_pos",
		"pos_rel": Vector2(0.5, 0.04),
		"pflicht": false,
	}

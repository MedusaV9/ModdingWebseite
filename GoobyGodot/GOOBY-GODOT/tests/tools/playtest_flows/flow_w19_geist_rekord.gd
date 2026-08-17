extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## W19-Playtest — Flow „Geister-Rekorde“ (Regressionswächter): frischer
## Save, Runde 1 Sternenhüpfer (score-basiert, meldet live) — der
## Geist-Chip bleibt WEG (keine Referenzkurve); Runde regulär kurz beenden
## über den sanktionierten Kontext-Griff ctx.report_end mit dem ECHTEN
## Live-Score (Muster flow_mg_probe_results) → die Bestlauf-Kurve steht im
## Save. Runde 2 per „Nochmal“ (Quick-GO): der Geist-Chip erscheint in der
## Top-Bar mit ±-Anzeige; besser spielen als Runde 1 (länger fliegen —
## der Streckenscore wächst monoton), dann beenden → die Results-Karte
## zeigt die „Geist geschlagen!“-Zeile GENAU EINMAL, der Rekord ist
## abgelöst und der Chip nach Rundenende abgebaut.
## ROBUSTHEIT: Runde 1 bleibt bewusst KURZ (kleiner Bestlauf), und in
## Runde 2 fliegt ein Ausweich-Pilot mit — er liest die Meteor-Reihen wie
## ein aufmerksamer Spieler und tippt über den ECHTEN Eingabe-Pfad
## (synthetische Taps, Harness-Muster) auf die freie Nachbarbahn. Ohne
## ihn beendete ein Zufalls-Meteor Runde 2 gern VOR dem Überholen
## (reproduziert im Hochkant-Lauf w19geist_hoch_v1).
## Aufruf:  tools/ci/run_playtest.sh flow_w19_geist_rekord
## Hochkant: tools/ci/run_playtest.sh flow_w19_geist_rekord 1320x2868

const SPIEL_ID := "starHopper"
## Ausweich-Pilot: Blickweite auf Meteore voraus (m) — Tempo ist ~11 m/s,
## das lässt auch bei wenigen llvmpipe-FPS Zeit für den Bahnwechsel-Tap.
const PILOT_BLICK_M := 38.0
## Polls Abkühlzeit zwischen zwei Pilot-Taps (Bahnwechsel wirken lassen).
const PILOT_COOLDOWN_POLLS := 6

var _runde1_score := -1
var _runde2_score := -1
## Pilot-Zustand: 0 = beobachten, 1 = Tap gedrückt, >1 = Abkühlzeit.
var _pilot_phase := 0
var _pilot_pos := Vector2.ZERO


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame(SPIEL_ID, 2))
	liste.append_array(spiel_starten(false))
	liste.append_array(_schritte_runde_1())
	liste.append_array(nochmal_und_los())
	liste.append_array(_schritte_runde_2())
	liste.append_array(_schritte_results_2())
	return liste


## Runde 1: fliegen, Chip-Abwesenheit beweisen, kurz beenden (echter
## Live-Score), Kurve im Save + KEINE Geist-Zeile auf den ersten Results.
func _schritte_runde_1() -> Array[Dictionary]:
	return [
		{"name": "runde1_fliegen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "runde1_chip_bleibt_weg",
			"aktion": "tue",
			"funktion": chip_weg_ohne_referenz,
			"erwartung": "Geist-Chip unsichtbar (frischer Save = keine Referenzkurve)",
		},
		{
			"name": "runde1_score_erspielt",
			"aktion": "warte_bis",
			"bedingung": live_score_positiv,
			"timeout_s": 30.0,
		},
		{
			"name": "runde1_beenden",
			"aktion": "tue",
			"funktion": runde1_beenden,
			"erwartung": "ctx.report_end mit dem echten Live-Score (> 0)",
		},
		{
			"name": "results1_da",
			"aktion": "warte_bis",
			"text": "Runde vorbei!",
			"timeout_s": 30.0,
		},
		{"name": "results1_ansehen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "kurve_im_save",
			"aktion": "tue",
			"funktion": kurve_im_save,
			"erwartung": "minigames.geist.%s trägt die Runde-1-Kurve" % SPIEL_ID,
		},
		{
			"name": "results1_ohne_geist_zeile",
			"aktion": "tue",
			"funktion": geist_zeilen_anzahl.bind(0),
			"erwartung": "Runde 1 ohne Referenz = keine „Geist geschlagen!“-Zeile",
		},
	]


## Runde 2: Chip erscheint mit ±-Anzeige, dann den Bestlauf ECHT
## überholen (länger fliegen — Score wächst monoton) und beenden.
func _schritte_runde_2() -> Array[Dictionary]:
	return [
		{"name": "runde2_anlauf", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "runde2_chip_sichtbar",
			"aktion": "warte_bis",
			"bedingung": chip_sichtbar_pilot_fliegt,
			"timeout_s": 30.0,
		},
		{
			"name": "runde2_chip_zeigt_delta",
			"aktion": "tue",
			"funktion": chip_delta_format_ok,
			"erwartung": "Chip-Label zeigt „+N“ / „−N“ / „±0“",
		},
		{
			"name": "runde2_geist_ueberholen",
			"aktion": "warte_bis",
			"bedingung": runde2_vorn_pilot_fliegt,
			"timeout_s": 90.0,
		},
		{
			"name": "runde2_chip_vorn",
			"aktion": "tue",
			"funktion": chip_zeigt_plus,
			"erwartung": "Chip steht auf „+“ (vor dem Bestlauf)",
		},
		{
			"name": "runde2_beenden",
			"aktion": "tue",
			"funktion": runde2_beenden,
			"erwartung": "ctx.report_end mit Live-Score > Runde-1-Score",
		},
	]


## Results 2: „Geist geschlagen!“ genau einmal, Rekord abgelöst,
## Chip abgebaut — dann nach Hause.
func _schritte_results_2() -> Array[Dictionary]:
	return [
		{
			"name": "results2_da",
			"aktion": "warte_bis",
			"text": "Runde vorbei!",
			"timeout_s": 30.0,
		},
		{"name": "results2_ansehen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "geist_geschlagen_zeile",
			"aktion": "warte_bis",
			"text": I18nService.t("mg.geist.geschlagen"),
			"timeout_s": 15.0,
		},
		{
			"name": "geist_zeile_genau_einmal",
			"aktion": "tue",
			"funktion": geist_zeilen_anzahl.bind(1),
			"erwartung": "GENAU EINE „Geist geschlagen!“-Zeile auf der Karte",
		},
		{
			"name": "rekord_abgeloest",
			"aktion": "tue",
			"funktion": rekord_abgeloest,
			"erwartung": "Save-Kurve trägt jetzt den Runde-2-Score",
		},
		{
			"name": "chip_nach_ende_abgebaut",
			"aktion": "tue",
			"funktion": chip_abgebaut,
			"erwartung": "Chip versteckt + Tracking beendet (Rundenende)",
		},
		{
			"name": "results_nach_hause",
			"aktion": "tipp_text",
			"text": "Nach Hause",
			"erwarte": {"route": "home/living"},
			"timeout_s": 90.0,
		},
		{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------- Bausteine


func _chip() -> Control:
	var host := host_node()
	if host == null:
		return null
	var chip: Variant = host.get("_geist_chip")
	return chip if chip is Control else null


func _chip_label_text() -> String:
	var chip := _chip()
	if chip == null:
		return ""
	for kind in chip.get_children():
		if kind is Label:
			return (kind as Label).text
	return ""


## Runde 1 (frischer Save): der Chip existiert, bleibt aber unsichtbar,
## WEIL der Rekorder keine Referenzkurve hat — beides explizit prüfen.
func chip_weg_ohne_referenz() -> bool:
	var host := host_node()
	var chip := _chip()
	if host == null or chip == null or chip.visible:
		return false
	var geist: Variant = host.get("_geist")
	return geist != null and not geist.hat_referenz()


func chip_sichtbar() -> bool:
	var chip := _chip()
	return chip != null and chip.is_visible_in_tree()


## Chip-Label hält den Delta-Vertrag: „+N“, „−N“ (echtes Minus) oder „±0“.
func chip_delta_format_ok() -> bool:
	if not chip_sichtbar():
		return false
	var text := _chip_label_text()
	return text.begins_with("+") or text.begins_with("−") or text == "±0"


func chip_zeigt_plus() -> bool:
	return chip_sichtbar() and _chip_label_text().begins_with("+")


## Nach Rundenende: Chip versteckt UND der Rekorder ist abgebaut.
func chip_abgebaut() -> bool:
	var host := host_node()
	var chip := _chip()
	if host == null or chip == null or chip.visible:
		return false
	return host.get("_geist") == null


func _live_score() -> int:
	var spiel := spiel_node()
	if spiel == null or not is_instance_valid(spiel):
		return -1
	return int(spiel.call("live_score"))


func live_score_positiv() -> bool:
	return _live_score() > 0


## ---------------------------------------------------- Ausweich-Pilot


func chip_sichtbar_pilot_fliegt() -> bool:
	_pilot_tick()
	return chip_sichtbar()


func runde2_vorn_pilot_fliegt() -> bool:
	if runde2_vorn():
		return true
	_pilot_tick()
	return false


## Ein Poll des Ausweich-Piloten (die Harness ruft die Bedingung pro
## Frame): Meteor voraus auf der eigenen Bahn? → Tap auf die freie
## Nachbarbahn über den ECHTEN Eingabe-Pfad (Druck in diesem Poll,
## Loslassen im nächsten — die Geste löst wie beim Spieler beim
## Loslassen aus), danach kurze Abkühlzeit.
func _pilot_tick() -> void:
	if _pilot_phase == 1:
		harness._maus_knopf(_pilot_pos, false)
		_pilot_phase = 2
		return
	if _pilot_phase > 1:
		_pilot_phase = (_pilot_phase + 1) % (PILOT_COOLDOWN_POLLS + 2)
		return
	var spiel := spiel_node()
	if spiel == null or not is_instance_valid(spiel):
		return
	var richtung := _sichere_nachbarbahn(spiel)
	if richtung == 0:
		return
	var seite := 0.28 if richtung < 0 else 0.72
	_pilot_pos = harness._fenster_px(spielfeld_pos(Vector2(seite, 0.62)))
	harness._maus_knopf(_pilot_pos, true)
	_pilot_phase = 1


## -1/+1 = freie Nachbarbahn links/rechts, 0 = bleiben (eigene Bahn frei
## oder keine freie Nachbarbahn in Blickweite).
func _sichere_nachbarbahn(spiel: Node) -> int:
	var meteore: Variant = spiel.get("_meteors")
	if not (meteore is Array):
		return 0
	var bahn := int(spiel.get("lane"))
	var strecke := float(spiel.get("traveled"))
	if _bahn_frei(meteore, bahn, strecke):
		return 0
	var tune: Variant = spiel.get("tune")
	var bahnen := int((tune as Dictionary).get("LANES", 3)) if tune is Dictionary else 3
	for richtung: int in [-1, 1]:
		var kandidat := bahn + richtung
		if kandidat >= 0 and kandidat < bahnen and _bahn_frei(meteore, kandidat, strecke):
			return richtung
	return 0


func _bahn_frei(meteore: Array, bahn: int, strecke: float) -> bool:
	for meteor: Variant in meteore:
		if not (meteor is Dictionary) or int((meteor as Dictionary).get("lane", -1)) != bahn:
			continue
		var abstand := float((meteor as Dictionary).get("m", 0.0)) - strecke
		if abstand > -2.0 and abstand < PILOT_BLICK_M:
			return false
	return true


## Runde 1 regulär beenden — mit dem ECHT erspielten Live-Score (der
## sanktionierte Kontext-Griff aus flow_mg_probe_results).
func runde1_beenden() -> bool:
	var spiel := spiel_node()
	if spiel == null or spiel.get("ctx") == null:
		return false
	_runde1_score = _live_score()
	if _runde1_score <= 0:
		return false
	spiel.ctx.report_end({"score": _runde1_score})
	return true


func runde2_vorn() -> bool:
	return _runde1_score > 0 and _live_score() > _runde1_score


func runde2_beenden() -> bool:
	var spiel := spiel_node()
	if spiel == null or spiel.get("ctx") == null:
		return false
	_runde2_score = _live_score()
	if _runde2_score <= _runde1_score:
		return false
	spiel.ctx.report_end({"score": _runde2_score})
	return true


func kurve_im_save() -> bool:
	var gs := game_state()
	if gs == null or not gs.has_method("state"):
		return false
	var rekord := GeistRekord.rekord_von(gs.state(), SPIEL_ID)
	return GeistRekord.ist_gueltig(rekord) and GeistRekord.rekord_score(rekord) == _runde1_score


func rekord_abgeloest() -> bool:
	var gs := game_state()
	if gs == null or not gs.has_method("state"):
		return false
	var rekord := GeistRekord.rekord_von(gs.state(), SPIEL_ID)
	return GeistRekord.ist_gueltig(rekord) and GeistRekord.rekord_score(rekord) == _runde2_score


## Anzahl „GeistZeile“-Zeilen auf der aktuellen Results-Karte (genau-
## einmal-Wache; Godot nummeriert Namens-Duplikate mit @-Präfix durch).
func geist_zeilen_anzahl(erwartet: int) -> bool:
	var host := host_node()
	if host == null:
		return false
	var results: Variant = host.get("_results")
	if not (results is Control):
		return false
	var rows: Variant = (results as Control).get("_rows")
	if not (rows is Control):
		return false
	var anzahl := 0
	for kind in (rows as Control).get_children():
		if str(kind.name).contains("GeistZeile"):
			anzahl += 1
	return anzahl == erwartet

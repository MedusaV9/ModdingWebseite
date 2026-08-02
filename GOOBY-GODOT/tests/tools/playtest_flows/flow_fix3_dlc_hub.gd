extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## G8/FIX-3-Verifikationsflow (Befunde B1 HOCH + B5 KLEIN aus
## docs/playtest/G8-PT2-stadt-laeden.md): Einstellungen → „Alle DLCs
## ansehen“ → der DLC-Hub muss OHNE Zurück-Umweg bedienbar sein — das
## Settings-Overlay schließt sich beim Reiseantritt jetzt selbst (B1;
## vorher lag es unsichtbar über dem Hub und fraß jeden Tap). Danach
## Kachel-Tap (Detail-Sheet öffnet = der Hub bekommt echte Taps) und
## zurück ins Wohnzimmer. Zweiter Beleg für die GENERISCHE Wurzel: der
## Codes-Screen (zweiter goto-Ausgang der Einstellungen) wird genauso
## geprüft. Nebenbei B5: der Reise-Veil zum Hub trägt die eigene
## Hub-Karte statt „Trautes Heim“ (Titel wird bei travel_started direkt
## vom Veil abgelesen). Aufruf: tools/ci/run_playtest.sh flow_fix3_dlc_hub
##
## Vor dem Fix (Repro): `settings_zu_von_allein`/`hub_karte_statt_heim`/
## `detail_da` schlagen fehl — exakt Befund B1/B5 (Beleg pt2_d1/016…020).

const LEVEL := 15


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_hub_schritte())
	liste.append_array(_codes_schritte())
	liste.append({"name": "abschluss", "aktion": "warte", "sekunden": 2.0})
	return liste


## Teil 1 (B1 + B5): Einstellungen → DLC-Hub → Kachel-Tap → zurück.
func _hub_schritte() -> Array[Dictionary]:
	return [
		{"name": "level_fuenfzehn", "aktion": "tue", "funktion": gib_level.bind(LEVEL)},
		{"name": "veil_beobachter", "aktion": "tue", "funktion": _veil_beobachten},
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
		# B1-Kern: KEIN Zurück-Umweg mehr — das Overlay muss von allein
		# weg sein, sobald die Reise durch ist (vorher: Timeout, Beleg
		# pt2_d1/017…020 „wieder Einstellungen“).
		{
			"name": "settings_zu_von_allein",
			"aktion": "warte_bis",
			"weg_klasse": "SettingsScreen",
			"timeout_s": 30.0,
		},
		# B5-Kern: der Veil trug zur Hub-Reise die Hub-Karte (Titel wurde
		# bei travel_started festgehalten, s. _bei_reise_gestartet).
		{
			"name": "hub_karte_statt_heim",
			"aktion": "tue",
			"funktion": _hub_karte_gezeigt,
			"erwartung": "Veil-Titel = Hub-Karte (nicht „Trautes Heim“)",
		},
		{"name": "hub_ansehen", "aktion": "warte", "sekunden": 2.0},
		# Kachel-Tap: erst ins Bild rollen, dann der „Ansehen“-Knopf der
		# Ranch-Karte — öffnet das Detail-Sheet NUR, wenn der Hub wirklich
		# Taps bekommt (vorher fraß das unsichtbare Overlay den Tipp).
		{
			"name": "zu_ranch_rollen",
			"aktion": "tue",
			"funktion": rolle_zu.bind("DlcKarte_ranch"),
		},
		{
			"name": "ranch_kachel_tippen",
			"aktion": "tipp_pos",
			"pos_funktion": knopf_in.bind("DlcKarte_ranch"),
			"timeout_s": 20.0,
		},
		{
			"name": "detail_da",
			"aktion": "warte_bis",
			"bedingung": control_da.bind("AktionKnopf"),
			"timeout_s": 30.0,
		},
		# Sheet per Backdrop-Tipp schließen (ab Sheet-Mitte wischen
		# SCROLLT nur den Inhalt — Befund pt2_c4).
		{
			"name": "detail_schliessen",
			"aktion": "tipp_pos",
			"pos_funktion": canvas_punkt.bind(Vector2(0.9, 0.08)),
			"pflicht": false,
		},
		{"name": "sheet_zu_abwarten", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "hub_zurueck",
			"aktion": "tipp_name",
			"node": "Zurueck",
			"timeout_s": 30.0,
		},
		# Falls der erste Zurück-Tipp nur ein Rest-Sheet geschlossen hat.
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
	]


## Teil 2 (B1 generisch): auch der zweite goto-Ausgang der Einstellungen
## (Aktionscodes, Route `codes`) muss das Overlay von allein schließen.
func _codes_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "einstellungen_erneut",
			"aktion": "tipp_name",
			"node": "SettingsButton",
			"erwarte": {"klasse": "SettingsScreen"},
			"timeout_s": 90.0,
		},
		{"name": "zu_codes_rollen", "aktion": "tue", "funktion": rolle_zu.bind("CodesButton")},
		{
			"name": "codes_oeffnen",
			"aktion": "tipp_name",
			"node": "CodesButton",
			"erwarte": {"route": "codes"},
			"timeout_s": 120.0,
		},
		{
			"name": "settings_zu_auch_bei_codes",
			"aktion": "warte_bis",
			"weg_klasse": "SettingsScreen",
			"timeout_s": 30.0,
		},
		{
			"name": "codes_zurueck",
			"aktion": "tipp_name",
			"node": "Zurueck",
			"erwarte": {"route": "home/living"},
			"timeout_s": 120.0,
		},
	]


## Hängt sich an travel_started: sobald die Reise zum Ziel `dlc` startet,
## hat das Veil seine Karte schon gestellt (es verbindet sich beim Boot
## VOR diesem Beobachter) — Titel für den B5-Check festhalten.
func _veil_beobachten() -> bool:
	var router := harness.root.get_node_or_null("/root/SceneRouter")
	if router == null:
		print("[FIX3] Kein SceneRouter — Veil-Beobachtung unmöglich")
		return false
	router.connect("travel_started", _bei_reise_gestartet)
	return true


func _bei_reise_gestartet(ziel: StringName, _travel_type: int) -> void:
	if String(ziel) != "dlc" or zettel.has("veil_titel_hub"):
		return
	merke("veil_titel_hub", _veil_titel())


## %Title der Veil-Karte (das Veil ist Kind des SceneRouter-Autoloads).
func _veil_titel() -> String:
	var router := harness.root.get_node_or_null("/root/SceneRouter")
	if router == null:
		return ""
	for kind in router.get_children():
		if kind is LoadingVeil:
			return ((kind as LoadingVeil).get_node("%Title") as Label).text
	return ""


func _hub_karte_gezeigt() -> bool:
	var ist := str(zettel.get("veil_titel_hub", ""))
	var soll := I18nService.t("veil.dlc.hub.titel")
	var heim := I18nService.t("veil.home.titel")
	print("[FIX3] Veil-Titel zur Hub-Reise: '%s' (soll '%s', nicht '%s')" % [ist, soll, heim])
	return ist == soll and ist != heim

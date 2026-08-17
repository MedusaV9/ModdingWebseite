extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W19-Playtest — Flow „Entdecker-Karte“ (Regressionswächter): Ranch über
## die ECHTE Kauf-Logik erwerben (Staging Level 15 + Münzen, Muster
## flow_w18_ranch_rundritt), EIN Fundort-Fixture über die echte
## Entdeckungs-Logik setzen (RanchEntdeckungen.entdecke — so trägt der
## erste Kartenbesuch ein NEU-Badge), Karte aus dem Hof-Daumen-Cluster
## öffnen (NEU-Badge sichtbar, Fortschritts-Kopf exakt), Detail-Karte des
## entdeckten Pins („Dahin!“-Kompass), Geheimnis-Karte eines „?“-Pins,
## Karte per Zurück schließen (Router-History → Hof), Ausreiten und in der
## Region den Steinkreis ECHT anreiten (Position-Fixture springe_zu wie
## die Screenshot-Fahrten + gehaltenes ui_up — die Entdeckung läuft über
## die echte Fundort-Prüfung samt Toast), dann Karte aus dem Region-HUD:
## Pin jetzt golden (★) + NEU-Badge, Fortschritts-Kopf zählt hoch.
## Aufruf:  tools/ci/run_playtest.sh flow_w19_entdecker_karte
## Hochkant: tools/ci/run_playtest.sh flow_w19_entdecker_karte 1320x2868

const START_MUENZEN := 6000
## Vorab entdeckter Fundort (Fixture): trägt beim ersten Öffnen das NEU-Badge.
const FIXTURE_FUND := "alter_baum"
## Live in der Region zu entdeckender Ort — steht in FREIEM Land (kein
## Zonen-Toast funkt dem Fund-Toast dazwischen, s. ranch_karte.json).
const NEU_FUND := "steinkreis"
## Anritt: 30 m nördlich des Steinkreises (60, 250), Blick nach Süden
## (Reiter-Konvention: vorwärts = -basis.z; rotation.y = PI zeigt nach +z).
const ANRITT_START := Vector3(60.0, 0.0, 220.0)
const ANRITT_BLICK := PI

var _zoom_vorher := Vector2.ZERO


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ranch_betreten())
	liste.append_array(_schritte_karte_vom_hof())
	liste.append_array(_schritte_neuen_ort_entdecken())
	liste.append_array(_schritte_karte_aus_region())
	return liste


## Ranch freischalten wie flow_w18_ranch_rundritt: Level/Münzen stagen,
## echter Kauf (RanchKauf.kaufe, atomar), dann zum Hof reisen.
func _schritte_ranch_betreten() -> Array[Dictionary]:
	return [
		{
			"name": "staging_level15_reich",
			"aktion": "tue",
			"funktion": stage_level_muenzen.bind(15, START_MUENZEN),
			"erwartung": "Level 15 + %d Münzen gesetzt (Staging)" % START_MUENZEN,
		},
		{
			"name": "ranch_kaufen",
			"aktion": "tue",
			"funktion": ranch_kaufen,
			"erwartung": "RanchKauf.kaufe liefert 'ok' (atomarer Kauf)",
		},
		{
			"name": "fund_fixture_setzen",
			"aktion": "tue",
			"funktion": fund_fixture_setzen,
			"erwartung": "%s über die echte Entdeckungs-Logik entdeckt" % FIXTURE_FUND,
		},
		{
			"name": "hof_anreisen",
			"aktion": "tue",
			"funktion": zum_hof_reisen,
			"erwarte": {"route": "ranch/hof"},
			"timeout_s": 240.0,
		},
		{"name": "hof_ankommen", "aktion": "warte", "sekunden": 4.0},
	]


## Karte aus dem Hof-Daumen-Cluster: NEU-Badge, Fortschritts-Kopf,
## Detail-Karte („Dahin!“), Geheimnis-Karte, Zurück in den Hof.
func _schritte_karte_vom_hof() -> Array[Dictionary]:
	return [
		{
			"name": "karte_vom_hof_oeffnen",
			"aktion": "tipp_text",
			"text": I18nService.t("rkarte.knopf"),
			"erwarte": {"route": "ranch/karte"},
			"timeout_s": 90.0,
		},
		{"name": "karte_ansehen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "neu_badge_sichtbar",
			"aktion": "warte_bis",
			"text": I18nService.t("rkarte.neu"),
			"timeout_s": 15.0,
		},
		{
			"name": "fortschritt_kopf_1_fund",
			"aktion": "tue",
			"funktion": fortschritt_ok.bind(1),
			"erwartung": "Kopf zählt '1/16 Orte entdeckt · 1/16 Zonen bereist'",
		},
		{
			"name": "pin_entdeckt_tippen",
			"aktion": "tipp_name",
			"node": "Pin_%s" % FIXTURE_FUND,
			"erwarte": {"text": "Dahin!"},
			"timeout_s": 30.0,
		},
		{"name": "detail_karte_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "detail_karte_schliessen",
			"aktion": "tipp_text",
			"text": I18nService.t("rkarte.schliessen"),
			"erwarte": {"weg_text": "Dahin!"},
			"timeout_s": 30.0,
		},
		{
			"name": "geheimnis_pin_tippen",
			"aktion": "tipp_name",
			"node": "Pin_%s" % NEU_FUND,
			"erwarte": {"text": "Psst"},
			"timeout_s": 30.0,
		},
		{"name": "geheimnis_karte_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "geheimnis_karte_schliessen",
			"aktion": "tipp_text",
			"text": I18nService.t("rkarte.schliessen"),
			"erwarte": {"weg_text": "Psst"},
			"timeout_s": 30.0,
		},
		{
			"name": "karte_zurueck_zum_hof",
			"aktion": "tipp_text",
			"text": I18nService.t("rkarte.zurueck"),
			"erwarte": {"route": "ranch/hof"},
			"timeout_s": 240.0,
		},
		{"name": "hof_wieder_da", "aktion": "warte", "sekunden": 2.0},
	]


## Ausreiten und den Steinkreis ECHT anreiten: springe_zu 30 m davor
## (Test-Griff der Screenshot-Fahrten), dann gehaltenes ui_up bis der
## Entdeckungs-Toast der echten Fundort-Prüfung erscheint.
func _schritte_neuen_ort_entdecken() -> Array[Dictionary]:
	return [
		{
			"name": "ausreiten",
			"aktion": "tipp_text",
			"text": "Ausreiten",
			"erwarte": {"route": "ranch/welt"},
			"timeout_s": 300.0,
		},
		{"name": "welt_ankommen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vor_den_steinkreis_springen",
			"aktion": "tue",
			"funktion": springe_vor_den_fund,
			"erwartung": "Reiter steht 30 m nördlich des Steinkreises",
		},
		{
			"name": "fund_anreiten_bis_toast",
			"aktion": "tue",
			"funktion": reiten_druecken,
			"erwarte": {"text": I18nService.t("rwelt.fund.%s" % NEU_FUND)},
			"timeout_s": 30.0,
		},
		{
			"name": "anhalten",
			"aktion": "tue",
			"funktion": reiten_loslassen,
			"erwartung": "ui_up losgelassen",
		},
		{
			"name": "fund_im_save",
			"aktion": "tue",
			"funktion": fund_im_save,
			"erwartung": "%s steht in ranch.welt.funde" % NEU_FUND,
		},
	]


## Karte aus dem Region-HUD: frisch entdeckter Pin golden + NEU-Badge,
## Fixture-Pin ohne Badge (Erst-Ansehen war schon), Kopf zählt 2 Funde;
## danach Zoom-Stufen (+/−, Pins kleben am Fundort) und Zurück in die
## Region (Karten-Route liegt in der Router-History).
func _schritte_karte_aus_region() -> Array[Dictionary]:
	return [
		{
			"name": "karte_aus_region_oeffnen",
			"aktion": "tipp_text",
			"text": I18nService.t("rkarte.knopf"),
			"erwarte": {"route": "ranch/karte"},
			"timeout_s": 90.0,
		},
		{"name": "karte_region_ansehen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "pin_jetzt_golden_mit_neu",
			"aktion": "tue",
			"funktion": pin_golden_mit_badge,
			"erwartung": "Pin %s zeigt ★ + NEU; %s-Badge ist weg" % [NEU_FUND, FIXTURE_FUND],
		},
		{
			"name": "fortschritt_kopf_2_funde",
			"aktion": "tue",
			"funktion": fortschritt_ok.bind(2),
			"erwartung": "Kopf zählt '2/16 Orte entdeckt · 1/16 Zonen bereist'",
		},
		{
			"name": "zoom_stand_merken",
			"aktion": "tue",
			"funktion": zoom_merken,
			"erwartung": "Kartenfläche hat eine messbare Ausgangsgröße",
		},
		{"name": "zoom_rein_tippen", "aktion": "tipp_name", "node": "ZoomRein"},
		{"name": "zoom_wirken_lassen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "zoom_vergroessert_karte",
			"aktion": "tue",
			"funktion": zoom_vergroessert,
			"erwartung": "Zoom-Stufe + macht die Kartenfläche deutlich größer",
		},
		{
			"name": "pin_klebt_nach_zoom",
			"aktion": "tue",
			"funktion": pin_klebt_am_fundort,
			"erwartung": "Pin %s sitzt nach dem Zoom exakt am Fundort" % NEU_FUND,
		},
		{"name": "zoom_raus_tippen", "aktion": "tipp_name", "node": "ZoomRaus"},
		{"name": "zoom_zurueck_ruhe", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "karte_zurueck_zur_region",
			"aktion": "tipp_text",
			"text": I18nService.t("rkarte.zurueck"),
			"erwarte": {"route": "ranch/welt"},
			"timeout_s": 300.0,
		},
		{"name": "abschluss_region", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------- Bausteine


func ranch_kaufen() -> bool:
	return RanchKauf.kaufe(game_state()) == RanchKauf.RESULT_OK


## Fixture über die ECHTE Entdeckungs-Logik (schreibt Save-Slice + Münzen)
## — danach wartet genau EIN NEU-Badge auf den ersten Kartenbesuch.
func fund_fixture_setzen() -> bool:
	var ergebnis := RanchEntdeckungen.entdecke(game_state(), FIXTURE_FUND)
	return bool(ergebnis["neu"]) and RanchEntdeckerKarte.neue_funde(game_state()).size() == 1


func zum_hof_reisen() -> bool:
	return RanchRouten.fahre_zum_hof(harness)


func _karten_screen() -> RanchKarteScreen:
	var screen: Variant = harness._finde_klasse(harness.root, "RanchKarteScreen")
	return screen if screen is RanchKarteScreen else null


## Fortschritts-Kopf exakt gegen die I18n-Vorlage prüfen (Zonen bleiben
## im ganzen Flow bei 1/16: Hof ist ab Start bereist, der Steinkreis
## steht in freiem Land).
func fortschritt_ok(funde: int) -> bool:
	var screen := _karten_screen()
	if screen == null:
		return false
	var gesamt := RanchEntdeckungen.alle_orte().size()
	var zonen_gesamt := RanchKarte.zonen().size()
	var erwartet := (
		I18nService
		. t(
			"rkarte.fortschritt",
			{
				"funde": str(funde),
				"funde_gesamt": str(gesamt),
				"zonen": "1",
				"zonen_gesamt": str(zonen_gesamt),
			}
		)
	)
	return screen.fortschritt_text() == erwartet


func springe_vor_den_fund() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not (szene is RanchRegionScene):
		return false
	var region := szene as RanchRegionScene
	if region.reiter == null:
		return false
	region.reiter.springe_zu(ANRITT_START, ANRITT_BLICK)
	return true


func reiten_druecken() -> bool:
	Input.action_press("ui_up")
	return true


func reiten_loslassen() -> bool:
	Input.action_release("ui_up")
	return true


func fund_im_save() -> bool:
	return RanchEntdeckungen.gefunden(game_state()).has(NEU_FUND)


func zoom_merken() -> bool:
	var screen := _karten_screen()
	if screen == null:
		return false
	_zoom_vorher = screen._canvas.custom_minimum_size
	return _zoom_vorher.x > 0.0


func zoom_vergroessert() -> bool:
	var screen := _karten_screen()
	if screen == null:
		return false
	return screen._canvas.custom_minimum_size.x > _zoom_vorher.x * 1.2


## Pins müssen nach jedem Zoom wieder EXAKT auf ihrer Weltposition sitzen
## (deferred _positioniere_pins) — sonst zeigen Sterne auf falsche Orte.
func pin_klebt_am_fundort() -> bool:
	var screen := _karten_screen()
	if screen == null:
		return false
	var knopf: Button = screen.pins().get(NEU_FUND)
	if knopf == null:
		return false
	for fund: Dictionary in screen._modell["fundorte"]:
		if str(fund["id"]) != NEU_FUND:
			continue
		var soll: Vector2 = screen._canvas.call("welt_zu_px", fund["zeig_pos"])
		return (knopf.position + knopf.size / 2.0).distance_to(soll) < 2.0
	return false


## Nach der Live-Entdeckung: der neue Pin ist golden (★) und trägt das
## NEU-Badge; das Fixture-Badge ist nach dem Erst-Ansehen abgebaut.
func pin_golden_mit_badge() -> bool:
	var screen := _karten_screen()
	if screen == null:
		return false
	var neu: Button = screen.pins().get(NEU_FUND)
	var fixture: Button = screen.pins().get(FIXTURE_FUND)
	if neu == null or fixture == null:
		return false
	if str(neu.text) != "★" or neu.get_node_or_null("Neu") == null:
		return false
	return str(fixture.text) == "★" and fixture.get_node_or_null("Neu") == null

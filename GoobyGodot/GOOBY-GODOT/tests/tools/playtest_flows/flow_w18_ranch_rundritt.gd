extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W18/3-Playtest (Agent 5) — Flow „Ranch-Rundritt“: Level/Münzen stagen,
## Ranch über die ECHTE Kauf-Logik (RanchKauf.kaufe, atomar) erwerben und
## die Münz-Abbuchung gegenprüfen, Hof ansehen (Tiere aus dem Start-Pack),
## Random-Event „Heudieb“ gezielt starten (RanchEventHost.start = der
## dokumentierte Test-Griff) und die 3 Krähen wie ein Spieler antippen
## (Heu-Belohnung gegenprüfen), dann Ausreiten in die offene Region:
## echtes Reiten (ui_up gehalten), Zonensprünge zu Glitzersee (Bergsee),
## Lavendelwiese und Wolkenhorn-Massiv (Test-Griff reiter.springe_zu wie
## die Screenshot-Fahrten), Galopp-Schalter, Entdeckungs-Save-Gegenprobe
## und zurück zum Hof. Aufruf:
##   tools/ci/run_playtest.sh flow_w18_ranch_rundritt

const START_MUENZEN := 6000

var _muenzen_vor_kauf := -1
var _heu_vor_event := -1
var _reiter_start := Vector3.ZERO


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "staging_level15_reich",
					"aktion": "tue",
					"funktion": stage_level_muenzen.bind(15, START_MUENZEN),
					"erwartung": "Level 15 + %d Münzen gesetzt (Staging)" % START_MUENZEN,
				},
				{
					"name": "kauf_muenzen_merken",
					"aktion": "tue",
					"funktion": merke_muenzen_vor_kauf,
					"erwartung": "Münzstand vor dem Ranch-Kauf notiert",
				},
				{
					"name": "ranch_kaufen",
					"aktion": "tue",
					"funktion": ranch_kaufen,
					"erwartung": "RanchKauf.kaufe liefert 'ok' (atomarer Kauf)",
				},
				{
					"name": "kaufpreis_abgebucht",
					"aktion": "tue",
					"funktion": kaufpreis_verbucht,
					"erwartung": "Genau der Katalog-Preis wurde abgebucht",
				},
				{
					"name": "kauf_im_save_verankert",
					"aktion": "tue",
					"funktion": kauf_im_save_verankert,
					"erwartung": "Save: gekauft+Abbuchung; Hub bietet NICHT erneut an (W18/B1)",
				},
				{
					"name": "hof_anreisen",
					"aktion": "tue",
					"funktion": zum_hof_reisen,
					"erwarte": {"route": "ranch/hof"},
					"timeout_s": 240.0,
				},
				{"name": "hof_ankommen", "aktion": "warte", "sekunden": 5.0},
				{
					"name": "hof_tiere_da",
					"aktion": "tue",
					"funktion": hof_hat_tiere,
					"erwartung": "Start-Pferde stehen nach dem Kauf auf dem Hof",
				},
			]
		)
	)
	liste.append_array(_schritte_heudieb())
	liste.append_array(_schritte_rundritt())
	return liste


## Random-Event „Heudieb“: gezielt über den dokumentierten Test-Griff
## starten (host.start — „sanctioned hook“ laut Host-Doku) und die drei
## Krähen wie ein Spieler per Tap verscheuchen.
## W18/4-B5-FIX (G6): ranch_event_host verarbeitet Taps nur noch über
## EINEN Eingabepfad (Screen-Space-Fangradius; Physics-Picking der
## Requisiten still) — die drei Krähen-Zähler-Checks (ein Tap = exakt −1)
## sind damit wieder PFLICHT-Wachen.
func _schritte_heudieb() -> Array[Dictionary]:
	return [
		{
			"name": "event_heudieb_starten",
			"aktion": "tue",
			"funktion": heudieb_starten,
			"erwartung": "RanchEventHost läuft mit dem Heudieb-Event",
		},
		{"name": "event_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "kraehe_1_verscheuchen",
			"aktion": "tipp_3d",
			"finder": kraehe_finden,
			"erwarte": {"bedingung": kraehen_uebrig.bind(2)},
			"timeout_s": 30.0,
		},
		{"name": "kraehe_1_ruhe", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "kraehe_2_verscheuchen",
			"aktion": "tipp_3d",
			"finder": kraehe_finden,
			"erwarte": {"bedingung": kraehen_uebrig.bind(1)},
			"timeout_s": 30.0,
		},
		{"name": "kraehe_2_ruhe", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "kraehe_3_verscheuchen",
			"aktion": "tipp_3d",
			"finder": kraehe_finden,
			"erwarte": {"bedingung": event_geloest},
			"timeout_s": 30.0,
		},
		{
			"name": "heu_belohnung_verbucht",
			"aktion": "tue",
			"funktion": heu_belohnung_da,
			"erwartung": "Gerettetes Heu (+2) liegt im Ranch-Lager",
		},
	]


## Offene Region: echt anreiten, dann Zonensprünge (Screenshot-Fahrt-
## Muster) mit HUD-/Save-Gegenproben und Rückkehr zum Hof.
func _schritte_rundritt() -> Array[Dictionary]:
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
			"name": "ritt_start_merken",
			"aktion": "tue",
			"funktion": reiter_position_merken,
			"erwartung": "Reiter steht in der Region (Startpunkt notiert)",
		},
		{
			"name": "antraben",
			"aktion": "tue",
			"funktion": reiten_druecken,
			"erwartung": "ui_up gedrückt — Pferd trabt an",
		},
		{"name": "ritt_am_hof", "aktion": "warte", "sekunden": 6.0},
		{
			"name": "anhalten",
			"aktion": "tue",
			"funktion": reiten_loslassen,
			"erwartung": "ui_up losgelassen",
		},
		{
			"name": "reiter_hat_sich_bewegt",
			"aktion": "tue",
			"funktion": reiter_bewegt,
			"erwartung": "Reiter ist beim Halten-Ritt > 4 m vorangekommen",
		},
		{
			"name": "zone_glitzersee",
			"aktion": "tue",
			"funktion": springe_zu_zone.bind("see"),
			"erwarte": {"text": "Glitzersee"},
			"timeout_s": 30.0,
		},
		{"name": "glitzersee_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "see_antraben",
			"aktion": "tue",
			"funktion": reiten_druecken,
			"erwartung": "ui_up gedrückt — Ritt am Seeufer",
		},
		{"name": "ritt_am_see", "aktion": "warte", "sekunden": 4.0},
		{
			"name": "see_anhalten",
			"aktion": "tue",
			"funktion": reiten_loslassen,
			"erwartung": "ui_up losgelassen",
		},
		{
			"name": "zone_lavendelwiese",
			"aktion": "tue",
			"funktion": springe_zu_zone.bind("blumenwiese"),
			"erwarte": {"text": "Lavendelwiese"},
			"timeout_s": 30.0,
		},
		{"name": "lavendel_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "galopp_einschalten",
			"aktion": "tipp_text",
			"text": "Galopp",
			"pflicht": false,
		},
		{
			"name": "lavendel_antraben",
			"aktion": "tue",
			"funktion": reiten_druecken,
			"erwartung": "ui_up gedrückt — Galopp durch den Lavendel",
		},
		{"name": "galopp_im_lavendel", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "lavendel_anhalten",
			"aktion": "tue",
			"funktion": reiten_loslassen,
			"erwartung": "ui_up losgelassen",
		},
		{
			"name": "zone_wolkenhorn",
			"aktion": "tue",
			"funktion": springe_zu_zone.bind("bergmassiv"),
			"erwarte": {"text": "Wolkenhorn"},
			"timeout_s": 30.0,
		},
		{"name": "wolkenhorn_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "zonen_im_save",
			"aktion": "tue",
			"funktion": zonen_entdeckt_ok,
			"erwartung": "see/blumenwiese/bergmassiv stehen in ranch.welt.entdeckt",
		},
		{
			"name": "zum_hof_zurueck",
			"aktion": "tipp_text",
			"text": "Zum Hof",
			"erwarte": {"route": "ranch/hof"},
			"timeout_s": 300.0,
		},
		{"name": "abschluss_hof", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------ Kauf-Wachen


func merke_muenzen_vor_kauf() -> bool:
	_muenzen_vor_kauf = muenzstand()
	return _muenzen_vor_kauf >= 0


func ranch_kaufen() -> bool:
	return RanchKauf.kaufe(game_state()) == RanchKauf.RESULT_OK


## Progression-Wache: exakt der Katalog-Preis ging vom Konto.
func kaufpreis_verbucht() -> bool:
	if _muenzen_vor_kauf < 0:
		return false
	return muenzstand() == _muenzen_vor_kauf - RanchKatalog.preis()


## W18/B1-Wache: der Kauf steht WIRKLICH im Save (nicht nur im RAM) —
## save_now() + Datei frisch von Platte lesen (Geldfluss-Beweis), dazu die
## Doppel-Angebots-Sperre (Hub/Recap dürfen den Kauf nicht erneut anbieten).
func kauf_im_save_verankert() -> bool:
	var gs := game_state()
	if gs == null or not bool(gs.save_now()):
		return false
	var save: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://save_v5.json"))
	if not (save is Dictionary):
		return false
	var ranch: Variant = (save as Dictionary).get("ranch")
	if not (ranch is Dictionary) or not bool((ranch as Dictionary).get("gekauft", false)):
		return false
	if (ranch as Dictionary).get("hoftiere", []).is_empty():
		return false
	var econ: Variant = (save as Dictionary).get("economy", {})
	if int((econ as Dictionary).get("coins", -1)) != _muenzen_vor_kauf - RanchKatalog.preis():
		return false
	return not RanchOffer.sollte_zeigen(gs) and RanchKauf.check(gs) == RanchKauf.RESULT_OWNED


func zum_hof_reisen() -> bool:
	return RanchRouten.fahre_zum_hof(harness)


func hof_hat_tiere() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not (szene is RanchHofScene):
		return false
	return (szene as RanchHofScene).pferde.size() >= 1


## --------------------------------------------------------- Heudieb-Event


func _event_host() -> RanchEventHost:
	var szene := aktuelle_szene()
	if szene == null:
		return null
	var host := szene.get_node_or_null("RanchEventHost")
	return host if host is RanchEventHost else null


## Heudieb gezielt starten. Läuft vom Zufalls-Roll schon ein ANDERES
## Event, wird es abgeräumt (Test-Staging), damit die Krähen-Probe
## deterministisch bleibt; Heu-Stand vorher für die Belohnungs-Gegenprobe.
func heudieb_starten() -> bool:
	var host := _event_host()
	if host == null:
		return false
	if host.is_running() and str(host._def.get("id", "")) != "heudieb":
		host._clear_props()
		host._running = false
		host._def = {}
	_heu_vor_event = _heu_im_lager()
	if not host.is_running():
		var def := RandomEventEngine.def_by_id(RandomEventEngine.defs_from_registry(), "heudieb")
		if def.is_empty():
			return false
		host.start(def)
	return host.is_running() and str(host._def.get("id", "")) == "heudieb"


## Nächste noch sitzende Krähe (Requisite des Hosts) für tipp_3d.
func kraehe_finden() -> Node3D:
	var host := _event_host()
	if host == null:
		return null
	for prop: Variant in host._props:
		if prop is Node3D and is_instance_valid(prop) and (prop as Node3D).is_inside_tree():
			return prop
	return null


func kraehen_uebrig(anzahl: int) -> bool:
	var host := _event_host()
	return host != null and int(host._remaining) == anzahl


func event_geloest() -> bool:
	var host := _event_host()
	return host != null and not host.is_running()


func _heu_im_lager() -> int:
	var gs := game_state()
	if gs == null:
		return -1
	return int(gs.get_value("ranch.wirtschaft.lager.heu", 0))


## Belohnungs-Gegenprobe: das Heudieb-Event schreibt genau +2 Heu gut.
func heu_belohnung_da() -> bool:
	return _heu_vor_event >= 0 and _heu_im_lager() == _heu_vor_event + 2


## ------------------------------------------------------------ Region-Ritt


func _region() -> RanchRegionScene:
	var szene := aktuelle_szene()
	return szene if szene is RanchRegionScene else null


func reiter_position_merken() -> bool:
	var region := _region()
	if region == null or region.reiter == null:
		return false
	_reiter_start = region.reiter.position
	return true


func reiten_druecken() -> bool:
	Input.action_press("ui_up")
	return true


func reiten_loslassen() -> bool:
	Input.action_release("ui_up")
	return true


func reiter_bewegt() -> bool:
	var region := _region()
	if region == null or region.reiter == null:
		return false
	return region.reiter.position.distance_to(_reiter_start) > 4.0


## Zonensprung (Test-Griff der Screenshot-Fahrten: springe_zu) — die
## Zonen-Erkennung/Entdeckung läuft danach über die ECHTE Spiellogik.
func springe_zu_zone(zone_id: String) -> bool:
	var region := _region()
	if region == null or region.reiter == null:
		return false
	region.reiter.springe_zu(RanchKarte.spawn_punkt(zone_id))
	return true


func zonen_entdeckt_ok() -> bool:
	var entdeckt := RanchWeltState.entdeckte_zonen(game_state())
	return entdeckt.has("see") and entdeckt.has("blumenwiese") and entdeckt.has("bergmassiv")

extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18-Playtest (Welle 3, Stadt-Agent) — Flow „Reise komplett“: Flughafen →
## Abflugtafel (FlapBoard) → Ziel „Glitzermeer“ buchen → Taxi (Dev-Key
## debug.taxi_warte_s = 4) → Einsteigen → BOARDING-PASS → „Gute Reise!“ →
## Abflug-Cutscene → Wohnzimmer. Danach Gooby VOR ORT besuchen
## (UrlaubsOrt strand): Souvenir-Spot (Riesenmuschel!), Muscheln sammeln
## (alle 5 Tap-Spots), Streicheln — und zum Schluss die Rückkehr: Slice per
## Staging auf returnReady stellen, „Abholen 🧳“, Souvenir-Münzen kassieren.
## Aufruf: tools/ci/run_playtest.sh flow_w18_reise_strand
##
## Staging (KEINE Spielmechanik-Änderung): Münzen auf 500 (Strand 180 + 10
## Taxi > Startgeld 100), debug.taxi_warte_s = 4 (sonst 300–600 s reale
## Wartezeit) und fürs Abholen returnAt in die Vergangenheit (sonst 3 REALE
## Tage warten). Alles über die öffentlichen GameState/AppSettings-APIs.

const STAGING_MUENZEN := 500
const TAXI_WARTE_S := 4
## Ein Urlaubs-Tag in REAL-ms (Vacation.MS_PER_DAY).
const TAG_MS := 86400000

## Münzstand-Merker (Kauf sinkt / Abholung steigt).
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ritual_puffer())
	liste.append_array(_schritte_buchung())
	liste.append_array(_schritte_besuch())
	liste.append_array(_schritte_abholung())
	return liste


## ------------------------------------------- Buchung (Tafel → Pass → Flug)


func _schritte_buchung() -> Array[Dictionary]:
	return [
		{
			"name": "staging_reisekasse",
			"aktion": "tue",
			"funktion": staging_reisekasse,
			"erwartung": "Münzen aufgestockt + Taxi-Wartezeit verkürzt",
		},
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vorfahren_flughafen",
			"aktion": "tue",
			"funktion": fahre_vor_flughafen,
			"erwartung": "Auto steht am Flughafen-Parkplatz",
		},
		# B7-FIX (W18/4): parkplatz_welt wählt jetzt das STRASSENSEITIGE
		# Tile ([0,3] statt tiles[0]=[0,2]) und das Pad liegt außerhalb der
		# Gebäude-Collider — der ECHTE Betreten-Prompt ist per Auto
		# erreichbar, kein Force-Enter mehr.
		{
			"name": "flughafen_betreten",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/flughafen"},
			"timeout_s": 60.0,
		},
		{"name": "terminal_ansehen", "aktion": "warte", "sekunden": 4.0},
		{
			"name": "reise_schalter_oeffnen",
			"aktion": "tipp_name",
			"node": "Reise",
			"erwarte": {"klasse": "FlapBoard"},
			"timeout_s": 60.0,
		},
		# Die Split-Flap-Tafel in Ruhe durchklappern lassen (Screenshot).
		{"name": "abflugtafel_ansehen", "aktion": "warte", "sekunden": 4.0},
		{
			"name": "ziel_glitzermeer",
			"aktion": "tipp_text",
			"text": "Glitzermeer",
			"erwarte": {"text": "Buchen"},
			"timeout_s": 30.0,
		},
		{"name": "confirm_lesen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "kasse_merken_buchung",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "reise_buchen",
			"aktion": "tipp_text",
			"text": "Buchen",
			"erwarte": {"bedingung": kauf_verbucht},
			"timeout_s": 20.0,
		},
		# Taxi kommt nach 4 s (Dev-Key) + 1-s-Tick der ReiseApp.
		{
			"name": "taxi_abwarten",
			"aktion": "warte_bis",
			"text": "Einsteigen!",
			"timeout_s": 60.0,
		},
		{
			"name": "einsteigen",
			"aktion": "tipp_text",
			"text": "Einsteigen!",
			"erwarte": {"klasse": "BoardingPass"},
			"timeout_s": 30.0,
		},
		# Bordkarte in Ruhe ansehen (Gate 3¾, Sitz 1A, Barcode-Gag).
		{"name": "bordkarte_ansehen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "gute_reise",
			"aktion": "tipp_text",
			"text": "Gute Reise!",
			"erwarte": {"weg_klasse": "BoardingPass"},
			"timeout_s": 30.0,
		},
		# Abflug-Cutscene mittendrin ablichten, dann bis nach Hause warten.
		{"name": "cutscene_mitte", "aktion": "warte", "sekunden": 6.0},
		# B8-FIX (W18/4): der Reise-Abschluss hängt jetzt STATISCH an der
		# Cutscene (nicht an der längst freigegebenen ReiseApp) — fertig
		# bucht den Urlaub, schließt das Taxi ab und routet heim. Der
		# Schritt ist wieder PFLICHT (vorher B8-Sonde in den Timeout +
		# umgehe_cutscene_blocker-Nachbau).
		{
			"name": "cutscene_bis_wohnzimmer",
			"aktion": "warte_bis",
			"route": "home/living",
			"timeout_s": 90.0,
		},
		# B9-FIX (W18/4): vacation.phase = away → Home OHNE Gooby, dafür
		# steht der Urlaubs-Hinweis (travel.weg-Strings).
		{
			"name": "daheim_ohne_gooby_check",
			"aktion": "tue",
			"funktion": daheim_ohne_gooby,
			"erwartung": "away-Phase: kein Home-Gooby, Urlaubs-Hinweis steht",
		},
		{"name": "daheim_ohne_gooby", "aktion": "warte", "sekunden": 3.0},
	]


## --------------------------------- Besuch am Urlaubsort (Muschel-Programm)


func _schritte_besuch() -> Array[Dictionary]:
	return [
		{
			"name": "zurueck_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen_2", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vorfahren_flughafen_2",
			"aktion": "tue",
			"funktion": fahre_vor_flughafen,
			"erwartung": "Auto steht am Flughafen-Parkplatz",
		},
		# B7-FIX (W18/4): auch der zweite Besuch nimmt den ECHTEN
		# Betreten-Prompt am straßenseitigen Parkplatz-Pad (kein
		# Force-Enter mehr).
		{
			"name": "flughafen_betreten_2",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/flughafen"},
			"timeout_s": 60.0,
		},
		{
			"name": "urlaubs_ansicht_oeffnen",
			"aktion": "tipp_name",
			"node": "Reise",
			"erwarte": {"text": "Gooby ist im Urlaub"},
			"timeout_s": 60.0,
		},
		{"name": "weg_ansicht_lesen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "gooby_besuchen",
			"aktion": "tipp_text",
			"text": "Gooby besuchen",
			"erwarte": {"klasse": "UrlaubsOrt"},
			"timeout_s": 120.0,
		},
		{"name": "strand_ansehen", "aktion": "warte", "sekunden": 4.0},
		{
			"name": "souvenir_spot",
			"aktion": "tipp_text",
			"text": "Souvenir-Spot",
			"erwarte": {"text": "Riesenmuschel"},
			"timeout_s": 30.0,
		},
		{"name": "muschel_freuen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "muscheln_sammeln_starten",
			"aktion": "tipp_text",
			"text": "Muscheln sammeln",
			"erwarte": {"name": "TapSpot0"},
			"timeout_s": 30.0,
		},
		{"name": "spot_0", "aktion": "tipp_name", "node": "TapSpot0", "timeout_s": 15.0},
		{"name": "spot_1", "aktion": "tipp_name", "node": "TapSpot1", "timeout_s": 15.0},
		{"name": "spot_2", "aktion": "tipp_name", "node": "TapSpot2", "timeout_s": 15.0},
		{"name": "spot_3", "aktion": "tipp_name", "node": "TapSpot3", "timeout_s": 15.0},
		{
			"name": "spot_4_alle_gefunden",
			"aktion": "tipp_name",
			"node": "TapSpot4",
			"erwarte": {"text": "Alle gefunden!"},
			"timeout_s": 15.0,
		},
		{"name": "mini_feiern", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "streicheln",
			"aktion": "tipp_text",
			"text": "Streicheln",
			"timeout_s": 20.0,
			"pflicht": false,
		},
		{"name": "kuschel_moment", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "strand_verlassen",
			"aktion": "tipp_text",
			"text": "Raus",
			"erwarte": {"route": "city/ort/flughafen"},
			"timeout_s": 120.0,
		},
	]


## ----------------------------------------------- Rückkehr (Abholen 🧳)


func _schritte_abholung() -> Array[Dictionary]:
	return [
		{
			"name": "staging_rueckkehr",
			"aktion": "tue",
			"funktion": staging_rueckkehr,
			"erwartung": "vacation.returnAt in der Vergangenheit (returnReady)",
		},
		{
			"name": "abhol_ansicht_oeffnen",
			"aktion": "tipp_name",
			"node": "Reise",
			"erwarte": {"text": "Gooby wartet am Flughafen!"},
			"timeout_s": 60.0,
		},
		{"name": "abhol_ansicht_lesen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "kasse_merken_abholung",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "abholen",
			"aktion": "tipp_text",
			"text": "Abholen",
			"erwarte": {"bedingung": muenzen_gestiegen},
			"timeout_s": 30.0,
		},
		{"name": "wiedersehen_feiern", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "reise_sheet_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{
			"name": "reise_sheet_weg",
			"aktion": "warte_bis",
			"weg_klasse": "ReiseApp",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "sheet_zu_moment", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "flughafen_verlassen",
			"aktion": "tipp_text",
			"text": "Raus",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "abschluss_strasse", "aktion": "warte", "sekunden": 3.0},
	]


## ---------------------------------------------------------------- Bausteine


func staging_reisekasse() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("economy.coins", STAGING_MUENZEN)
	var settings := harness.root.get_node_or_null("/root/AppSettings")
	if settings == null or not settings.has_method("set_setting"):
		return false
	settings.set_setting("debug.taxi_warte_s", TAXI_WARTE_S)
	return true


## Rückkehr vorziehen: returnAt in die Vergangenheit, pickupBy großzügig in
## die Zukunft — die ReiseApp leitet daraus returnReady ab (phase_at).
func staging_rueckkehr() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var roh: Variant = gs.get_value("vacation", {})
	if not (roh is Dictionary):
		return false
	var v: Dictionary = roh
	if str(v.get("phase", "")) != "away":
		return false
	var jetzt := _now_ms()
	v["returnAt"] = jetzt - 1000
	v["pickupBy"] = jetzt + TAG_MS
	gs.set_value("vacation", v)
	return true


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	return true


func kauf_verbucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	return int(gs.get_value("economy.coins", 0)) < _muenzen_vorher


## Abholung verbucht? Souvenir-Münzen kommen REIN (Stand steigt).
func muenzen_gestiegen() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	return int(gs.get_value("economy.coins", 0)) > _muenzen_vorher


## B9-Wache: in der away-Phase spawnt der Raum KEIN Home-Gooby, dafür
## steht der Urlaubs-Hinweis (AcBubble mit den travel.weg-Strings).
func daheim_ohne_gooby() -> bool:
	var szene := aktuelle_szene()
	if not (szene is RoomBase):
		print("[FLOW-DIAG] b9-check: Szene ist kein RoomBase: ", szene)
		return false
	var raum: RoomBase = szene
	var hinweis: Variant = raum.get("_bubble")
	print(
		"[FLOW-DIAG] b9-check urlaub=",
		raum.gooby_im_urlaub(),
		" gooby=",
		raum.gooby(),
		" hinweis=",
		hinweis
	)
	return raum.gooby_im_urlaub() and raum.gooby() == null and hinweis != null


func fahre_vor_flughafen() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	var park: Vector3 = stadt.karte.parkplatz_welt("flughafen")
	stadt.auto.teleport(park.x, park.z)
	# Auto-Runner: ohne gehaltene Bremse rollt das Auto sofort aus dem
	# 7-m-Parkradius (Lauf-1-Lehre aus flow_w18_stadt_tour).
	stadt.auto.set_brake(true)
	return true


func _now_ms() -> int:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## Nachzügler-Wache: die Erste-Viertelstunde-Tour-Karte (OnboardingGuide)
## kehrt NACH der Morgen-Ritual-Sequenz zurück und blockiert mit ihrem
## Scrim alle HUD-Taps — erst ausklingen lassen, dann (falls da) das X.
func _schritte_ritual_puffer() -> Array[Dictionary]:
	return [
		{
			"name": "tagesbonus_nachzuegler",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 45.0,
			"pflicht": false,
		},
		{"name": "bonus_zu_moment", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "coachmark_nachzuegler",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "guide_nachzuegler_wegtippen",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{"name": "hud_frei_moment", "aktion": "warte", "sekunden": 2.0},
	]

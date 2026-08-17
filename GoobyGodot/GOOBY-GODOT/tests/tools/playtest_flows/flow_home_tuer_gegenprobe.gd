extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Tür-Gegenprobe“: identischer Fütter-Loop wie flow_home_basis,
## aber VOR dem Tür-Tap wird der „Was nun?“-Hinweis (WhatsNextHint) über
## sein × geschlossen. Hintergrund (Lauf heim01): der Tap auf die
## Küchentür landete auf der „Was nun?“-Karte oben mittig — statt der
## Tür-Bestätigung öffnete sich das Tagesquest-Blatt und der ganze
## Fütter-Loop lief ins Leere. Läuft DIESER Flow grün, ist die Karte als
## Tap-Dieb überführt.
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_home_tuer_gegenprobe

var _hunger_vorher := -1.0


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "was_nun_wegtippen",
					"aktion": "tipp_falls_da",
					"node": "WasNunSchliessen",
					"timeout_s": 8.0,
					"pflicht": false,
				},
				{
					"name": "tuer_zur_kueche_tippen",
					"aktion": "tipp_3d",
					"finder": finde_tuer.bind("kitchen"),
					"offset": Vector3(0.0, 1.0, 0.0),
					"erwarte": {"text": "Los!"},
					"timeout_s": 45.0,
				},
				{
					"name": "tuer_bestaetigen",
					"aktion": "tipp_text",
					"text": "Los!",
					"erwarte": {"route": "home/kitchen"},
					"timeout_s": 120.0,
					"nebenbei_tipp_klasse": "TapMashOverlay",
				},
				{"name": "kueche_ankommen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "kuehlschrank_tippen",
					"aktion": "tipp_3d",
					"finder": finde_moebel.bind("kitchenFridge"),
					"offset": Vector3(0.0, 0.9, 0.0),
					"erwarte": {"klasse": "FuetterGrid"},
					"timeout_s": 45.0,
				},
				{
					"name": "hunger_merken",
					"aktion": "tue",
					"funktion": merke_hunger,
					"erwartung": "gooby.stats.hunger lesbar",
				},
				{
					"name": "moehre_waehlen",
					"aktion": "tipp_name",
					"node": "Karte_carrot",
					"erwarte": {"weg_klasse": "FuetterGrid"},
					"timeout_s": 30.0,
				},
				{"name": "mampf_sequenz_ansehen", "aktion": "warte", "sekunden": 12.0},
				{
					"name": "hunger_gestiegen",
					"aktion": "warte_bis",
					"bedingung": hunger_gestiegen,
					"timeout_s": 20.0,
					"erwartung": "gooby.stats.hunger steigt nach dem Füttern",
				},
				{"name": "abschluss_kueche", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


func merke_hunger() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_hunger_vorher = float(gs.get_value("gooby.stats.hunger", -1.0))
	return _hunger_vorher >= 0.0


## Möhre bucht +Hunger; kleine Toleranz, weil der Ticker nebenher zehrt.
func hunger_gestiegen() -> bool:
	var gs := game_state()
	if gs == null or _hunger_vorher < 0.0:
		return false
	var jetzt := float(gs.get_value("gooby.stats.hunger", -1.0))
	return jetzt >= _hunger_vorher + 2.0

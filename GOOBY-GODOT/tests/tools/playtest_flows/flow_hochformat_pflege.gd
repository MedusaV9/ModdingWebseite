extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Hochformat-Pflege“: derselbe Pflege-Kernloop wie flow_home_basis,
## aber im Hochformat (Daumen-Dock-Layout statt Cockpit-Spalte): Boot →
## Onboarding → Status-Kapsel öffnet das Stat-Detail-Sheet („Gooby-Status“)
## und schließt wieder → ein Streichler bucht → Tür in die Küche →
## Kühlschrank → Möhre → Hunger steigt wirklich. Prüft nebenbei das
## Portrait-HUD (5+4/5+5-Dock, Status-Chips oben).
## Format: HOCH 1320x2868 (BxH beim Aufruf zwingend mitgeben).
## Aufruf: tools/ci/run_playtest.sh flow_hochformat_pflege 1320x2868

var _hunger_vorher := -1.0
var _pets_basis := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				# „Was nun?"-Karte wegtippen (Befund heim01: Tap-Dieb).
				{
					"name": "was_nun_wegtippen",
					"aktion": "tipp_falls_da",
					"node": "WasNunSchliessen",
					"timeout_s": 8.0,
					"pflicht": false,
				},
				# Status-Sheet über die Hunger-Kapsel
				{
					"name": "status_kapsel_tippen",
					"aktion": "tipp_name",
					"node": "StatChipHunger",
					"erwarte": {"text": "Gooby-Status"},
					"timeout_s": 30.0,
				},
				{"name": "status_sheet_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "status_sheet_schliessen",
					"aktion": "taste",
					"keycode": KEY_ESCAPE,
					"erwarte": {"weg_text": "Gooby-Status"},
					"timeout_s": 20.0,
				},
				# Ein Streichler im Hochformat
				{
					"name": "pets_merken",
					"aktion": "tue",
					"funktion": merke_pets,
					"erwartung": "petsToday lesbar",
				},
				{
					"name": "streichler_hochformat",
					"aktion": "tipp_3d",
					"finder": finde_gooby,
					"offset": Vector3(0.0, 0.35, 0.0),
					"erwarte": {"bedingung": pets_gestiegen},
					"timeout_s": 30.0,
				},
				# Fütter-Loop wie flow_home_basis, nur hochkant; vorher
				# einen evtl. neu aufgetauchten Hinweis wegtippen.
				{
					"name": "was_nun_wegtippen_2",
					"aktion": "tipp_falls_da",
					"node": "WasNunSchliessen",
					"timeout_s": 5.0,
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


## 3D-Ziel für tipp_3d: der Gooby des aktuellen Raums.
func finde_gooby() -> Node3D:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("gooby"):
		return null
	var gooby: Variant = szene.call("gooby")
	return gooby if gooby is Node3D else null


func merke_pets() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_pets_basis = int(gs.get_value("achievements.counters.petsToday", 0))
	return true


func pets_gestiegen() -> bool:
	var gs := game_state()
	if gs == null or _pets_basis < 0:
		return false
	return int(gs.get_value("achievements.counters.petsToday", 0)) >= _pets_basis + 1


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

extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Streicheln“: Boot → Onboarding → Gooby anhalten (Staging, sonst
## wandert er unter dem Finger weg) → 10 echte Streichel-Taps auf den
## 3D-Gooby. Geprüft wird die ECHTE Buchung
## (achievements.counters.petsToday steigt pro Tap), der Kitzel-Zähler
## (3. Tap in Serie = „kitzlig“) und der Streichel-Bonus (+1 Münze beim
## 10. Streichler des Tages). Sprechblasen (AcBubble) sind weiche Checks
## (pflicht=false), weil die Seelen-Frequenzbremse (BUBBLE_MIN_GAP_S =
## 12 s) Blasen legal verschlucken darf und die Kicher-Stufen ein
## 4-s-Tap-Fenster haben, das llvmpipe-Schrittzeiten überdehnen können.
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_streicheln

var _pets_basis := -1
var _muenzen_basis := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				# „Was nun?"-Karte wegtippen (Befund heim01: sie stiehlt
				# Welt-Taps oben mittig), dann die Bubble-Bremse des
				# Betreten-Moments verstreichen lassen.
				{
					"name": "was_nun_wegtippen",
					"aktion": "tipp_falls_da",
					"node": "WasNunSchliessen",
					"timeout_s": 8.0,
					"pflicht": false,
				},
				{"name": "bubble_bremse_abwarten", "aktion": "warte", "sekunden": 13.0},
				{
					"name": "gooby_anhalten",
					"aktion": "tue",
					"funktion": gooby_anhalten,
					"erwartung": "Gooby steht (Staging: set_wander_enabled(false))",
				},
				{
					"name": "zaehler_merken",
					"aktion": "tue",
					"funktion": merke_zaehler,
					"erwartung": "petsToday/coins lesbar",
				},
			]
		)
	)
	for i in range(1, 11):
		var schritt := {
			"name": "streichler_%02d" % i,
			"aktion": "tipp_3d",
			"finder": finde_gooby,
			"offset": Vector3(0.0, 0.35, 0.0),
			"erwarte": {"bedingung": pets_mindestens.bind(i)},
			"timeout_s": 30.0,
		}
		liste.append(schritt)
		if i == 1:
			(
				liste
				. append(
					{
						"name": "kicher_blase_sichtbar",
						"aktion": "warte_bis",
						"klasse": "AcBubble",
						"timeout_s": 8.0,
						"pflicht": false,
					}
				)
			)
		if i == 3:
			(
				liste
				. append(
					{
						"name": "kitzlig_gebucht",
						"aktion": "warte_bis",
						"bedingung": tickles_mindestens.bind(1),
						"timeout_s": 8.0,
						"pflicht": false,
					}
				)
			)
		if i == 6:
			liste.append({"name": "schwindelig_ansehen", "aktion": "warte", "sekunden": 3.0})
	(
		liste
		. append_array(
			[
				{
					"name": "streichel_bonus_muenze",
					"aktion": "warte_bis",
					"bedingung": muenzen_mindestens_plus.bind(1),
					"timeout_s": 15.0,
				},
				{
					"name": "gooby_weiterlaufen_lassen",
					"aktion": "tue",
					"funktion": gooby_weiter,
					"erwartung": "Wandern wieder an",
				},
				{"name": "abschluss_streicheln", "aktion": "warte", "sekunden": 3.0},
			]
		)
	)
	return liste


func _gooby() -> Node:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("gooby"):
		return null
	return szene.call("gooby")


## 3D-Ziel für tipp_3d: der Gooby des aktuellen Raums (nicht per Namen
## suchen — find_child könnte ein gleichnamiges Control zuerst treffen).
func finde_gooby() -> Node3D:
	var gooby := _gooby()
	return gooby if gooby is Node3D else null


## Staging: Gooby bleibt stehen, damit 10 Taps dieselbe Stelle treffen.
func gooby_anhalten() -> bool:
	var gooby := _gooby()
	if gooby == null or not gooby.has_method("set_wander_enabled"):
		return false
	gooby.call("set_wander_enabled", false)
	return true


func gooby_weiter() -> bool:
	var gooby := _gooby()
	if gooby == null:
		return false
	gooby.call("set_wander_enabled", true)
	return true


func merke_zaehler() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_pets_basis = int(gs.get_value("achievements.counters.petsToday", 0))
	_muenzen_basis = int(gs.get_value("economy.coins", -1))
	return _muenzen_basis >= 0


## Jeder Tap MUSS als Streichler buchen (EVAL-1 D5 _count_pet).
func pets_mindestens(anzahl: int) -> bool:
	var gs := game_state()
	if gs == null or _pets_basis < 0:
		return false
	return int(gs.get_value("achievements.counters.petsToday", 0)) >= _pets_basis + anzahl


func tickles_mindestens(anzahl: int) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	return int(gs.get_value("achievements.counters.tickles", 0)) >= anzahl


## Der 10. Streichler des Tages zahlt +1 Münze (pet_bonus_due).
func muenzen_mindestens_plus(plus: int) -> bool:
	var gs := game_state()
	if gs == null or _muenzen_basis < 0:
		return false
	return int(gs.get_value("economy.coins", -1)) >= _muenzen_basis + plus

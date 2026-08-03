extends "res://tests/tools/playtest_flows/flow_pt2_helfer.gd"
## PT-2-Basisklasse (Welle H, G8): gemeinsame Bausteine für Stadt-/Läden-
## Flows — Auto an Ort-Parkplätze stellen, Münzen/Energie merken+prüfen,
## GameState-Spritzen (Level/Coins/Essen) und Stadtleben-Checks. Die
## UI-Sucher/Gesten/Termine liegen in flow_pt2_helfer.gd (gdlint-Split).

## Merkzettel für merke()/pruefe()-Bausteine (Münzen, Energie, Bestände).
var zettel: Dictionary = {}

## ---------------------------------------------------------------- Stadt


## CityScene der aktuellen Route (null = nicht in der Stadt).
func stadt() -> Node:
	var szene := aktuelle_szene()
	return szene if szene is CityScene else null


## Auto direkt an den Parkplatz-Trigger eines Orts stellen (wie ein
## Spieler, der vorgefahren ist). _spawn_bei räumt das Ausparken auf und
## setzt Collider. WICHTIG (Lauf pt2_a1/a2): Das Auto ist ein Auto-
## Runner — Bremse HALTEN, sonst rollt es aus dem Prompt-Radius. Und
## selbst MIT Bremse kriecht es weiter (BRAKE_MIN_SPEED, Web-Parität
## §C7.2) und der Spur-Assist zieht es seitwärts Richtung Fahrbahn —
## deshalb steht das Auto GENAU auf dem Anker (Distanz 0 = volle
## 4-m-Radius-Reserve gegen das Kriechen). Der frühere +2,5-m-Versatz
## Richtung Straße stammte aus der Zeit, als der Anker selbst im
## Fassaden-Collider steckte; seit dem PT2-B3-Fix (Offset ≥ halb 7,5 +
## Auto 1,5 + Luft) ist der Anker frei und der Versatz verschenkte nur
## Reserve (Lauf fix8_stadt_v2: Prompt riss beim Flughafen ab).
func fahre_zu(ort_id: String) -> bool:
	var szene := stadt()
	if szene == null:
		print("[PT2] fahre_zu(%s): keine CityScene aktiv" % ort_id)
		return false
	szene.call("_spawn_bei", ort_id)
	var park: Vector3 = szene.karte.parkplatz_welt(ort_id)
	szene.auto.teleport(park.x, park.z)
	szene.auto.set_brake(true)
	print("[PT2] Auto steht (Bremse an) vor %s (%s)" % [ort_id, str(park)])
	return true


## Verkehr + Fußgänger der Stadt zählen (FIX-5 „Die Stadt ist leer“).
func stadt_lebt() -> bool:
	var szene := stadt()
	if szene == null:
		return false
	var verkehr: Array = szene.get("_verkehr")
	var fussgaenger: Array = szene.get("_fussgaenger")
	print("[PT2] Stadtleben: %d Autos, %d Fußgänger" % [verkehr.size(), fussgaenger.size()])
	return verkehr.size() > 0 and fussgaenger.size() > 0


## Ambient-Leben eines Orts (G7-P55): OrtLeben-Node vorhanden?
func ort_lebt() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var leben := szene.find_child("OrtLeben", true, false)
	print("[PT2] OrtLeben im %s: %s" % [szene.name, "ja" if leben != null else "NEIN"])
	return leben != null


## ---------------------------------------------------------------- Werte


func coins() -> int:
	var gs := game_state()
	return int(gs.get_value("economy.coins", 0)) if gs != null else 0


func energie() -> float:
	var gs := game_state()
	return float(gs.get_value("gooby.stats.energy", 0.0)) if gs != null else 0.0


func merke(key: String, wert: Variant) -> bool:
	zettel[key] = wert
	print("[PT2] merke %s = %s" % [key, str(wert)])
	return true


func merke_coins(key: String) -> bool:
	return merke(key, coins())


## Energie ERST bei Schritt-Ausführung lesen (merke.bind(energie()) würde
## den Wert schon beim Bauen der Schrittliste einfrieren — vor Onboarding!).
func merke_energie(key: String) -> bool:
	return merke(key, energie())


## Prüft coins() == zettel[key] + delta (Geld-Logik-Checks).
func pruefe_coins_delta(key: String, delta: int) -> bool:
	var soll := int(zettel.get(key, 0)) + delta
	var ist := coins()
	print("[PT2] Münzen: ist %d, soll %d (Basis %s%+d)" % [ist, soll, key, delta])
	return ist == soll


## Prüft, dass Münzen seit merke gestiegen sind (Erlös unbekannter Höhe).
func pruefe_coins_gestiegen(key: String) -> bool:
	var vorher := int(zettel.get(key, 0))
	var ist := coins()
	print("[PT2] Münzen: vorher %d, jetzt %d" % [vorher, ist])
	return ist > vorher


func gib_coins(betrag: int) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("economy.coins", betrag)
	print("[PT2] Münzen auf %d gesetzt" % betrag)
	return true


func gib_level(level: int) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("progression.level", level)
	print("[PT2] Level auf %d gesetzt" % level)
	return true


func gib_essen(id: String, menge: int) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("inventory.food.%s" % id, menge)
	print("[PT2] inventory.food.%s = %d" % [id, menge])
	return true


func essen_bestand(id: String) -> int:
	var gs := game_state()
	return int(gs.get_value("inventory.food.%s" % id, 0)) if gs != null else 0


func setting_setzen(key: String, wert: Variant) -> bool:
	var settings := harness.root.get_node_or_null("/root/AppSettings")
	if settings == null:
		return false
	settings.call("set_setting", key, wert)
	print("[PT2] AppSettings %s = %s" % [key, str(wert)])
	return true

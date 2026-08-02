extends "res://tests/tools/playtest_flows/flow_pt3_basis.gd"
## PT-3 Flow (b1) „Sternenhüpfer KOMPLETT“ (Welle H): Onboarding → Arcade →
## Kachel starHopper (Grid-Scrollen nötig, Kachel 37/38) → Pregame „Leicht“
## → komplette Runde SPIELEN: reaktive Bahnwechsel-Taps (der Flow liest wie
## ein aufmerksamer Spieler das Feld — Meteor voraus? → freie Nachbarbahn),
## bis die Runde endet (75 s Zeitlimit oder Treffer) → Results-Rahmen
## prüfen (Runde vorbei!/Punkte/Sterne/Münzen/XP) → „Nochmal“ (Quick-GO,
## KEIN 3-2-1 — EF-3 F2) → Pause → „Neustart“ (frische Runde) → Pause →
## „Beenden“ → Arcade → „Zurück“ nach Hause (Blocker-Regression).
## Aufruf: tools/ci/run_playtest.sh flow_pt3_star_hopper

## So weit voraus (m) gilt ein Meteor auf der eigenen Bahn als Gefahr.
const GEFAHR_M := 30.0
## Fenster (m), in dem die ZIEL-Bahn frei sein muss (etwas großzügiger).
const ZIEL_FREI_M := 36.0
## Reaktions-Taps während der Runde (75 s / ~2 s je Schritt + Reserve).
const DODGE_SCHRITTE := 42


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_pregame_schritte("starHopper", "Leicht"))
	(
		liste
		. append(
			{
				"name": "intro_beat_ansehen",
				"aktion": "warte",
				"sekunden": 2.0,
			}
		)
	)
	for i in DODGE_SCHRITTE:
		(
			liste
			. append(
				{
					"name": "ausweichen_%02d" % (i + 1),
					"aktion": "tipp_pos",
					"pos_funktion": dodge_punkt,
					"pflicht": false,
				}
			)
		)
		liste.append({"name": "flug_pause_%02d" % (i + 1), "aktion": "warte", "sekunden": 0.5})
	(
		liste
		. append_array(
			[
				{
					"name": "runde_zu_ende",
					"aktion": "warte_bis",
					"bedingung": rundenende_da,
					"timeout_s": 180.0,
				},
				{"name": "results_zaehlen_lassen", "aktion": "warte", "sekunden": 4.0},
				{
					"name": "results_rahmen_pruefen",
					"aktion": "tue",
					"funktion": results_pruefen,
					"erwartung": "Runde vorbei!/Punkte/Sterne/Nochmal/Arcade/Heim",
				},
				{
					"name": "muenzen_gutgeschrieben",
					"aktion": "tue",
					"funktion": pruefe_coins_gestiegen.bind("start_coins"),
					"erwartung": "Score > 0 → Münz-Award gebucht",
				},
				{
					"name": "zweite_energie_merken",
					"aktion": "tue",
					"funktion": merke_energie.bind("nochmal"),
				},
				{
					"name": "nochmal_starten",
					"aktion": "tipp_text",
					"text": "Nochmal",
					"erwarte": {"bedingung": spiel_aktiv},
					"timeout_s": 90.0,
				},
				{
					"name": "nochmal_kostet_energie",
					"aktion": "tue",
					"funktion": energie_delta_pruefen.bind("nochmal", -8.0),
					"erwartung": "auch „Nochmal“ bucht 8 Energie ab",
					"pflicht": false,
				},
				{
					"name": "runde_2_frisch",
					"aktion": "tue",
					"funktion": score_loggen.bind("Runde 2 nach Nochmal"),
				},
				{
					"name": "runde_2_ausweichen_1",
					"aktion": "tipp_pos",
					"pos_funktion": dodge_punkt,
					"pflicht": false,
				},
				{"name": "runde_2_fliegen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "pause_oeffnen",
					"aktion": "tipp_text",
					"text": "Pause",
					"erwarte": {"text": "Beenden"},
					"timeout_s": 30.0,
				},
				# Pause-„Neustart“ = frische Runde (Quick-GO) mitten im Spiel.
				{
					"name": "pause_neustart",
					"aktion": "tipp_text",
					"text": "Neustart",
					"erwarte": {"bedingung": spiel_aktiv},
					"timeout_s": 90.0,
				},
				{
					"name": "runde_3_frisch",
					"aktion": "tue",
					"funktion": neustart_frisch,
					"erwartung": "Score nach Neustart wieder klein (frische Runde)",
					"pflicht": false,
				},
				{"name": "runde_3_fliegen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "pause_wieder_oeffnen",
					"aktion": "tipp_text",
					"text": "Pause",
					"erwarte": {"text": "Beenden"},
					"timeout_s": 30.0,
				},
				{
					"name": "spiel_beenden",
					"aktion": "tipp_text",
					"text": "Beenden",
					"erwarte": {"route": "arcade"},
					"timeout_s": 90.0,
				},
				{
					"name": "history_sauber_nach_runden",
					"aktion": "tue",
					"funktion": history_sauber,
					"erwartung": "mg_host/mg_pregame NICHT in der History",
				},
				{
					"name": "zurueck_nach_hause",
					"aktion": "tipp_text",
					"text": "Zurück",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Reaktiver Bahnwechsel wie ein Spieler: Meteor (oder Schauer-Bahn) voraus
## → Tap auf die Seite der freien Nachbarbahn; sonst Pickup in freier
## Nachbarbahn mitnehmen; nichts zu tun → Vector2.ZERO (Tap verpufft).
func dodge_punkt() -> Vector2:
	var g := spiel()
	if g == null or not bool(g.get("running")) or bool(g.get("finished")):
		return Vector2.ZERO
	if float(g.get("_intro_left")) > 0.0:
		return Vector2.ZERO
	var bahn := int(g.get("lane"))
	var gefahr := _bahn_gefahr(g)
	var ziel := bahn
	if bool(gefahr.get(bahn, false)):
		ziel = _freie_nachbarbahn(bahn, gefahr)
		print("[PT3] Hopper: Gefahr auf Bahn %d -> weiche auf %d (%s)" % [bahn, ziel, gefahr])
	else:
		ziel = _pickup_bahn(g, bahn, gefahr)
		if ziel != bahn:
			print("[PT3] Hopper: Pickup auf Bahn %d — hole ich mir" % ziel)
	if ziel == bahn:
		return Vector2.ZERO
	var vp := spiel_viewport()
	var seite := 0.22 if ziel < bahn else 0.78
	return spiel_punkt(Vector2(vp.x * seite, vp.y * 0.72))


## Nach Pause-„Neustart“ muss die Runde frisch sein (Score fast 0).
func neustart_frisch() -> bool:
	var h := host()
	if h == null:
		return false
	var score := int(h.get("score"))
	print("[PT3] Score nach Neustart: %d" % score)
	return score <= 5


## G7-P56-Results-Rahmen: Titel, Punkte-Zeile, Stern-Reihe, die EINE
## Knopf-Reihenfolge Nochmal/Zur Arcade/Nach Hause, Münz-/XP-Zeilen.
func results_pruefen() -> bool:
	var ok := true
	for text in ["Runde vorbei!", "Punkte", "Nochmal", "Zur Arcade", "Nach Hause", "XP"]:
		if _finde_text_irgendwo(harness.root, text) == null:
			print("[PT3] Results: '%s' FEHLT" % text)
			ok = false
	var sterne := _suche_klasse(harness.root, "FeelStarRow")
	print("[PT3] Results: Stern-Reihe %s" % ["da" if sterne != null else "FEHLT"])
	var muenzen := _finde_text_irgendwo(harness.root, "Münzen")
	print("[PT3] Results: Münz-Zeile %s" % ["da" if muenzen != null else "fehlt (Score 0?)"])
	return ok and sterne != null


func _bahn_gefahr(g: Node) -> Dictionary:
	var gefahr := {}
	var strecke := float(g.get("traveled"))
	var meteore: Array = g.get("_meteors")
	for meteor: Dictionary in meteore:
		var abstand := float(meteor["m"]) - strecke
		if abstand > 0.5 and abstand < GEFAHR_M:
			gefahr[int(meteor["lane"])] = true
	# Angekündigter/aktiver Meteorschauer: die Gefahr-Bahnen meiden.
	var schauer := str(g.get("_shower_state"))
	if schauer != "idle":
		var bahnen: Dictionary = g.get("_shower_lanes")
		for bahn: int in bahnen.get("danger", []):
			gefahr[bahn] = true
	return gefahr


func _freie_nachbarbahn(bahn: int, gefahr: Dictionary) -> int:
	for kandidat in [bahn - 1, bahn + 1]:
		if kandidat >= 0 and kandidat <= 2 and not bool(gefahr.get(kandidat, false)):
			return kandidat
	# Beide Nachbarn blockiert: zur Mitte hin ausweichen (kleinstes Risiko).
	return clampi(bahn + (1 if bahn < 1 else -1), 0, 2)


func _pickup_bahn(g: Node, bahn: int, gefahr: Dictionary) -> int:
	var strecke := float(g.get("traveled"))
	var pickups: Array = g.get("_pickups")
	for pickup: Dictionary in pickups:
		var abstand := float(pickup["m"]) - strecke
		if abstand <= 2.0 or abstand >= ZIEL_FREI_M:
			continue
		var ziel := int(pickup["lane"])
		if absi(ziel - bahn) == 1 and not bool(gefahr.get(ziel, false)):
			return ziel
	return bahn


func _finde_text_irgendwo(node: Node, text: String) -> Control:
	var nadel := text.to_lower()
	var stapel: Array[Node] = [node]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is Label or aktuell is Button:
			if str(aktuell.get("text")).to_lower().contains(nadel):
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null

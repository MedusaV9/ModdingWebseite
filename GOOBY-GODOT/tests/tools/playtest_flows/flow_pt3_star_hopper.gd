extends "res://tests/tools/playtest_flows/flow_pt3_basis.gd"
## PT-3 Flow (b1) „Sternenhüpfer KOMPLETT“ (Welle H): Onboarding → Arcade →
## Kachel starHopper (Grid-Scrollen nötig, Kachel 37/38) → Pregame „Leicht“
## → komplette Runde SPIELEN: reaktive Bahnwechsel-Taps (der Flow liest wie
## ein aufmerksamer Spieler das Feld — Meteor voraus? → freie Nachbarbahn),
## bis die Runde endet (75 s Zeitlimit oder Treffer) → Results-Rahmen
## prüfen (Runde vorbei!/Punkte/Sterne/Münzen/XP) → „Nochmal“ (Quick-GO,
## KEIN 3-2-1 — EF-3 F2) → Pause → „Neustart“ (frische Runde) → Pause →
## „Beenden“ → Arcade → „Zurück“ nach Hause (Blocker-Regression).
## A2 REKORD-PULS-PROBE (G8-IDEEN A2): vor dem Start wird ein NIEDRIGER
## Easy-Bestwert (1) gesät — der Lauf ist damit „ein Lauf mit niedrigem
## Bestwert“: der Rekord fällt bei Score 2 = 20 m, DETERMINISTISCH vor der
## ersten Meteor-Reihe (30 m, Hitbox ab ~25 m — ohne Ausweichen erreichbar;
## Pickups spawnen erst mit den Reihen). Banner „NEUER REKORD!“ + goldene
## Score-Pill (Stufe 2) werden im Lauf geprüft; nach „Nochmal“ muss der
## Host den NEUEN Bestwert frisch lesen (Pill neutral).
## A1 STERNENBUCH: nach der gebuchten Runde zeigt die Arcade-Kachel
## rückwirkend ≥1 ★ + Bestwert-Zeile.
## Aufruf: tools/ci/run_playtest.sh flow_pt3_star_hopper

## So weit voraus (m) gilt ein Meteor auf der eigenen Bahn als Gefahr.
const GEFAHR_M := 30.0
## Fenster (m), in dem die ZIEL-Bahn frei sein muss (etwas großzügiger).
const ZIEL_FREI_M := 36.0
## Reaktions-Taps während der Runde (75 s / ~2 s je Schritt + Reserve).
const DODGE_SCHRITTE := 42
## A2-Probe: gesäter Easy-Bestwert. GENAU 1: der Rekord fällt bei Score 2
## (= 20 m bei 10 m/Punkt) — VOR der ersten Meteor-Reihe (_next_row_m 30,
## Hitbox-Reichweite ~4,6 m), also auch ohne Ausweich-Eingaben sicher.
const REKORD_SAAT_BEST := 1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append(
			{
				"name": "rekord_bestwert_saeen",
				"aktion": "tue",
				"funktion": rekord_bestwert_saeen,
				"erwartung":
				"niedriger Easy-Bestwert (%d) für die Rekord-Puls-Probe" % REKORD_SAAT_BEST,
			}
		)
	)
	liste.append_array(arcade_pregame_schritte("starHopper", "Leicht"))
	(
		liste
		. append_array(
			[
				{
					"name": "intro_beat_ansehen",
					"aktion": "warte",
					"sekunden": 2.0,
				},
				# A2: der Score überholt den gesäten Bestwert nach wenigen
				# Metern — das Banner ist der Screenshot-Beleg des Moments.
				{
					"name": "rekord_banner_zuendet",
					"aktion": "warte_bis",
					"bedingung": rekord_banner_da,
					"timeout_s": 90.0,
				},
				{
					"name": "rekord_pill_golden",
					"aktion": "tue",
					"funktion": rekord_pill_pruefen,
					"erwartung": "Score-Pill Rekord-Gold (Stufe 2), Trigger einmalig",
				},
			]
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
				# A2: „Nochmal“ liest den Bestwert FRISCH (Runde 1 hat ihn
				# gerade überschrieben) — Pill neutral, kein alter Rekord-
				# Zustand. pflicht=false: sehr kurze Runde-1-Läufe (früher
				# Meteor-Treffer) können die 80 %-Zone in Sekunden erreichen.
				{
					"name": "runde_2_pill_neutral",
					"aktion": "tue",
					"funktion": rekord_pill_neutral,
					"erwartung": "frische Runde: Pill neutral + NEUER Bestwert geladen",
					"pflicht": false,
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
				# A1 Sternenbuch: die gebuchte Runde füllt die Kachel
				# rückwirkend — Pips ≥1 ★ + Bestwert-Zeile + Sterne-Kapsel.
				{
					"name": "sternenbuch_fuellt_sich",
					"aktion": "tue",
					"funktion": sternenbuch_nach_runde,
					"erwartung": "starHopper-Kachel: ≥1 ★, Bestwert-Zeile, Kapsel zählt ★",
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


## A2-Saat: niedriger Easy-Bestwert — der Lauf wird zum „Lauf mit
## niedrigem Bestwert“, Puls (80 %) und Rekord-Moment zünden sichtbar.
func rekord_bestwert_saeen() -> bool:
	var gs := game_state()
	if gs == null or not gs.has_method("update"):
		print("[PT3] Rekord-Saat: kein GameState")
		return false
	gs.update(
		func(state: Dictionary) -> void:
			var legacy: Dictionary = state["minigames"]["legacy"]
			if not (legacy.get("bestByDiff") is Dictionary):
				legacy["bestByDiff"] = {}
			var by_diff: Dictionary = legacy["bestByDiff"]
			if not (by_diff.get("starHopper") is Dictionary):
				by_diff["starHopper"] = {}
			by_diff["starHopper"]["easy"] = REKORD_SAAT_BEST
	)
	print("[PT3] Rekord-Saat: starHopper-Bestwert (Leicht) = %d" % REKORD_SAAT_BEST)
	return true


## A2: das „NEUER REKORD!“-Banner des Hosts ist gerade sichtbar.
func rekord_banner_da() -> bool:
	var banner := harness.root.find_child("RekordBanner", true, false)
	return banner is Control and (banner as Control).is_visible_in_tree()


## A2: nach dem Überholen bleibt die Pill Rekord-Gold (Stufe 2) und der
## Trigger ist verbraucht (einmalig pro Lauf).
func rekord_pill_pruefen() -> bool:
	var h := host()
	if h == null:
		return false
	var anzeige: Node = h.get("_puls_anzeige")
	var stufe := int(anzeige.get("stufe")) if anzeige != null else -1
	var puls: RefCounted = h.get("_puls")
	var einmalig: bool = puls != null and bool(puls.get("rekord_gefeuert"))
	print("[PT3] Rekord-Puls: Pill-Stufe %d, rekord_gefeuert=%s" % [stufe, einmalig])
	return stufe == 2 and einmalig


## A2: „Nochmal“ setzt den Puls frisch auf — Pill neutral und der Host hat
## den NEUEN Bestwert (Runde-1-Score > Saat) geladen.
func rekord_pill_neutral() -> bool:
	var h := host()
	if h == null:
		return false
	var anzeige: Node = h.get("_puls_anzeige")
	var stufe := int(anzeige.get("stufe")) if anzeige != null else -1
	var puls: RefCounted = h.get("_puls")
	var best := int(puls.get("best")) if puls != null else -1
	print("[PT3] Runde 2: Pill-Stufe %d, geladener Bestwert %d" % [stufe, best])
	return stufe == 0 and best > REKORD_SAAT_BEST


## A1: nach der gebuchten Runde trägt die starHopper-Kachel ≥1 ★, eine
## Bestwert-Zeile und die Kopfzeilen-Kapsel zählt Sterne mit.
func sternenbuch_nach_runde() -> bool:
	var kachel := harness.root.find_child("Tile_starHopper", true, false)
	if kachel == null:
		print("[PT3] Sternenbuch: Tile_starHopper fehlt")
		return false
	var pips := kachel.find_child("SternPips", true, false)
	var sterne := int(pips.get("earned")) if pips != null else -1
	var best_label := kachel.find_child("BestwertLabel", true, false) as Label
	var zaehler := harness.root.find_child("CountLabel", true, false) as Label
	var kapsel := zaehler.text if zaehler != null else "?"
	print(
		(
			"[PT3] Sternenbuch: starHopper %d ★, Bestwert-Zeile '%s', Kapsel '%s'"
			% [sterne, best_label.text if best_label != null else "FEHLT", kapsel]
		)
	)
	return sterne >= 1 and best_label != null and kapsel.contains("★")


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

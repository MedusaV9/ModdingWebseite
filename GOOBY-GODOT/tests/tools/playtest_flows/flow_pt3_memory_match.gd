extends "res://tests/tools/playtest_flows/flow_pt3_basis.gd"
## PT-3 Flow (c) „Memory KOMPLETT“ (Welle H, ruhiges Spiel): Onboarding →
## Arcade → memoryMatch (4×4, 8 Paare auf Level 1) → Merk-Fenster abwarten →
## Brett DETERMINISTISCH lösen: der Flow liest die Kartengesichter wie ein
## Spieler mit perfektem Gedächtnis (immer ein echtes Paar tippen, während
## Auflöse-/Merk-/Spick-Fenstern verpufft der Tap) → Spick-Knopf testen
## (erscheint nach 3 sauberen Treffern, deckt 1 s alles auf) → „Alle Paare
## gefunden!“ → Results (Titel, Rekord beim Erstlauf, 0 Fehlgriffe, Münzen)
## → „Nochmal“ (Quick-GO, 8 Energie) → auf Brett 2 drei Paare lösen →
## Pause → „Beenden“ → Arcade → History-Wache (Blocker-Regression).
## Aufruf: tools/ci/run_playtest.sh flow_pt3_memory_match

## Tap-Budget Brett 1: 16 Pflicht-Taps + Verpuffer (Auflöse-Fenster).
const LOESE_TAPS_1 := 14
const LOESE_TAPS_2 := 26
## Brett 2 (nach „Nochmal“): nur ein paar Paare zum Beleg.
const LOESE_TAPS_B2 := 8


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_pregame_schritte("memoryMatch"))
	liste.append({"name": "intro_und_merken_ansehen", "aktion": "warte", "sekunden": 2.0})
	_loese_taps(liste, "loesen", LOESE_TAPS_1)
	(
		liste
		. append_array(
			[
				# Nach 3 sauberen Treffern in Folge ist der Spick verdient —
				# der Knopf lebt IM Spiel-Viewport, darum über spick_punkt
				# (tipp_text würde SubViewport-Koordinaten verfehlen).
				{
					"name": "spicken_falls_verdient",
					"aktion": "tipp_pos",
					"pos_funktion": spick_punkt,
					"pflicht": false,
				},
				{
					"name": "spick_fenster_loggen",
					"aktion": "tue",
					"funktion": spick_loggen,
					"pflicht": false,
				},
				{"name": "spick_ansehen", "aktion": "warte", "sekunden": 1.2},
			]
		)
	)
	_loese_taps(liste, "weiter_loesen", LOESE_TAPS_2)
	(
		liste
		. append_array(
			[
				{
					"name": "brett_geschafft",
					"aktion": "warte_bis",
					"bedingung": rundenende_da,
					"timeout_s": 120.0,
				},
				{"name": "results_zaehlen_lassen", "aktion": "warte", "sekunden": 4.0},
				{
					"name": "fehlgriffe_geprueft",
					"aktion": "tue",
					"funktion": fehlgriffe_pruefen,
					"erwartung": "perfektes Lösen = 0 Fehlgriffe",
					"pflicht": false,
				},
				{
					"name": "results_rahmen_da",
					"aktion": "warte_bis",
					"text": "Runde vorbei!",
					"timeout_s": 20.0,
				},
				# Erstlauf: Bestwert 0 → jeder Score > 0 ist „Neuer Rekord!“.
				{
					"name": "rekord_zeile_da",
					"aktion": "warte_bis",
					"text": "Neuer Rekord!",
					"timeout_s": 15.0,
					"pflicht": false,
				},
				{
					"name": "muenzen_gutgeschrieben",
					"aktion": "tue",
					"funktion": pruefe_coins_gestiegen.bind("start_coins"),
					"erwartung": "Score > 0 → Münz-Award gebucht",
				},
				{
					"name": "energie_vor_nochmal",
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
			]
		)
	)
	_loese_taps(liste, "brett2_loesen", LOESE_TAPS_B2)
	(
		liste
		. append_array(
			[
				{
					"name": "brett2_fortschritt",
					"aktion": "tue",
					"funktion": fortschritt_loggen,
				},
				{
					"name": "pause_oeffnen",
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
					"name": "history_sauber_arcade",
					"aktion": "tue",
					"funktion": history_sauber,
					"erwartung": "mg_host/mg_pregame NICHT in der History",
				},
				{"name": "abschluss_arcade", "aktion": "warte", "sekunden": 1.5},
			]
		)
	)
	return liste


## `anzahl` Löse-Taps + kurze Denkpausen anhängen.
func _loese_taps(liste: Array[Dictionary], prefix: String, anzahl: int) -> void:
	for i in anzahl:
		(
			liste
			. append(
				{
					"name": "%s_%02d" % [prefix, i + 1],
					"aktion": "tipp_pos",
					"pos_funktion": karten_punkt,
					"pflicht": false,
				}
			)
		)
		liste.append(
			{"name": "%s_pause_%02d" % [prefix, i + 1], "aktion": "warte", "sekunden": 0.5}
		)


## Perfektes Gedächtnis: liegt schon eine Karte offen → ihren Partner
## tippen; sonst das erste verdeckte Paar anfangen. Während Intro/Merk-/
## Spick-/Auflöse-Fenster (Eingabe gesperrt) verpufft der Tap (ZERO).
func karten_punkt() -> Vector2:
	var g := spiel()
	if g == null or not _tippbar(g):
		return Vector2.ZERO
	var karten: Array = g.get("cards")
	var picked: Array = g.get("picked")
	var index := -1
	if picked.size() == 1:
		index = _partner_von(karten, int(picked[0]))
	elif picked.is_empty():
		index = _erstes_paar(karten)
	if index < 0:
		return Vector2.ZERO
	return spiel_punkt(_karten_mitte(g, index))


## Nimmt das Spiel gerade Karten-Taps an? (Spiegel der _unhandled_input-
## Sperren: Intro, Merk-Fenster, Spick-Blick, Auflöse-Pause, Pause-Modal.)
func _tippbar(g: Node) -> bool:
	if not bool(g.get("running")) or bool(g.get("finished")) or bool(g.get("game_paused")):
		return false
	if float(g.get("_intro_left")) > 0.0 or float(g.get("reveal_left")) > 0.0:
		return false
	return float(g.get("peek_left")) <= 0.0 and float(g.get("resolve_left")) <= 0.0


## Spick-Knopf (im Spiel-Viewport!) — nur wenn sichtbar, sonst verpufft.
func spick_punkt() -> Vector2:
	var g := spiel()
	if g == null:
		return Vector2.ZERO
	var knopf := g.get("_peek_button") as Button
	if knopf == null or not knopf.visible:
		print("[PT3] Spicken: Knopf (noch) nicht da — Tap verpufft")
		return Vector2.ZERO
	print("[PT3] Spicken: Knopf da — tippe ihn")
	return spiel_punkt(knopf.position + knopf.size * 0.5)


func spick_loggen() -> bool:
	var g := spiel()
	if g == null:
		return true
	var peek: Dictionary = g.get("peek")
	print("[PT3] Spick-Zustand: %s, peek_left %.2f" % [str(peek), float(g.get("peek_left"))])
	return true


func fortschritt_loggen() -> bool:
	var g := spiel()
	if g == null:
		print("[PT3] Fortschritt: Spiel weg")
		return true
	print(
		(
			"[PT3] Memory: Paare %d, Fehlgriffe %d, Score %d, %.1f s"
			% [
				int(g.get("matched_pairs")),
				int(g.get("misses")),
				int(g.get("score")) if g.get("score") != null else -1,
				float(g.get("elapsed")),
			]
		)
	)
	return true


## Perfektes Lösen lässt 0 Fehlgriffe zu (der Löser tippt nur echte Paare).
func fehlgriffe_pruefen() -> bool:
	var g := spiel()
	if g == null:
		print("[PT3] Fehlgriffe: Spiel schon abgeräumt")
		return true
	var misses := int(g.get("misses"))
	print("[PT3] Fehlgriffe am Brettende: %d" % misses)
	return misses == 0


func _erstes_paar(karten: Array) -> int:
	for i in karten.size():
		var karte: Dictionary = karten[i]
		if str(karte.get("state")) != "down":
			continue
		if _partner_von(karten, i) >= 0:
			return i
	return -1


## Zweite verdeckte Karte mit demselben Gesicht wie karten[index].
func _partner_von(karten: Array, index: int) -> int:
	var face := int((karten[index] as Dictionary).get("face"))
	for j in karten.size():
		if j == index:
			continue
		var karte: Dictionary = karten[j]
		if str(karte.get("state")) == "down" and int(karte.get("face")) == face:
			return j
	return -1


## Kartenmitte in Spiel-Pixeln (Spiegel von _card_pos + _card_size/2).
func _karten_mitte(g: Node, index: int) -> Vector2:
	var layout: Dictionary = g.get("layout")
	var cols := int(layout.get("cols", 4))
	var origin: Vector2 = g.get("_grid_origin")
	var groesse: Vector2 = g.get("_card_size")
	var gap: Vector2 = g.get("_card_gap")
	var col := index % cols
	var row := index / cols
	var pos := origin + Vector2(col * (groesse.x + gap.x), row * (groesse.y + gap.y))
	return pos + groesse * 0.5

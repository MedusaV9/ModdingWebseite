extends "res://tests/tools/playtest_flows/flow_basis.gd"
## PT-3-Basisklasse (Welle H, G8): gemeinsame Bausteine für die Minispiel-/
## Arcade-Flows — Host/Spiel/Spielfeld-Zugriff (SubViewport-Mapping Canvas ↔
## Spiel-Pixel), Rundenzustand (Countdown vorbei? Results offen?), Münz-/
## Energie-Zettel und die Router-History-Wache für den G7-Blocker-Fix
## („Arcade-Zurück startete eine frische Runde“ — mg_pregame/mg_host dürfen
## NIE in der History liegen). Die konkreten Flows (rahmen/star_hopper/
## carrot_guard/city_drive/memory_match) erben hiervon.

## Merkzettel für merke_*/pruefe_*-Bausteine (Münzen, Energie, Zeiten).
var zettel: Dictionary = {}

## ------------------------------------------------------- Host & Spielfeld


## Der MinigameHost (Rahmen aller 38 Spiele) — null, wenn keiner sichtbar.
func host() -> Control:
	return _suche_klasse(harness.root, "MinigameHost") as Control


## Die laufende Spiel-Instanz (MinigameBase) im SubViewport des Hosts.
func spiel() -> Node:
	var h := host()
	if h == null:
		return null
	return h.get("_game") as Node


## Global-Rect des letterboxten Spielfelds (SubViewportContainer) in
## Canvas-Koordinaten — Basis für alle Spielfeld-Taps.
func _feld_rect() -> Rect2:
	var h := host()
	if h == null:
		return Rect2()
	var container := h.get("_viewport_container") as Control
	if container == null:
		return Rect2()
	return container.get_global_rect()


## Pixelgröße des Spiel-Viewports (das Koordinatensystem, in dem die
## Spiele ihre Rects/Löcher/Karten rechnen).
func spiel_viewport() -> Vector2:
	var h := host()
	if h == null:
		return Vector2.ZERO
	var viewport := h.get("_viewport") as SubViewport
	if viewport == null:
		return Vector2.ZERO
	return Vector2(viewport.size)


## Spiel-Pixel → Canvas-Punkt (für tipp_pos/halte/wisch der Harness).
## Vector2.ZERO = kein gültiges Ziel (Tap verpufft oben links im Rand).
func spiel_punkt(pos_im_spiel: Vector2) -> Vector2:
	var rect := _feld_rect()
	var groesse := spiel_viewport()
	if rect.size.x <= 0.0 or groesse.x <= 0.0 or groesse.y <= 0.0:
		return Vector2.ZERO
	return rect.position + pos_im_spiel * (rect.size / groesse)


## Relativer Spielfeld-Punkt (0..1 je Achse) → Canvas-Punkt.
func spiel_punkt_rel(rel: Vector2) -> Vector2:
	return spiel_punkt(rel * spiel_viewport())


## ------------------------------------------------------- Rundenzustand


## true, sobald der 3-2-1-Countdown durch ist und die Runde WIRKLICH
## läuft (MinigameBase.start() setzt running).
func runde_laeuft() -> bool:
	var g := spiel()
	return g != null and bool(g.get("running"))


## true NUR wenn die Runde läuft UND nicht pausiert ist — `pause()` lässt
## running an (MinigameBase), erst game_paused unterscheidet Modal-Zustand.
## DER Resume-Indikator: nach „Weiter“/Backdrop erst wieder true, wenn der
## 3-2-1-Countdown durch ist und der Host _game.resume() gerufen hat.
func spiel_aktiv() -> bool:
	var g := spiel()
	return g != null and bool(g.get("running")) and not bool(g.get("game_paused"))


## Host-Countdown-Ziffer (3-2-1) gerade sichtbar? (Start UND Resume.)
func countdown_sichtbar() -> bool:
	var h := host()
	if h == null:
		return false
	var label := h.get("_countdown_label") as Label
	return label != null and label.visible


## Results-Screen des Rahmens sichtbar? (G7-P56: EIN Look für alle Spiele.)
func rundenende_da() -> bool:
	return _suche_klasse(harness.root, "MinigameResults") != null


## Pause-Knopf des Hosts wieder tippbar (nach Resume-Countdown)?
func pause_knopf_aktiv() -> bool:
	var h := host()
	if h == null:
		return false
	var knopf := h.get("_pause_button") as Button
	return knopf != null and not knopf.disabled


## Host-Score in den Log schreiben (immer ok — reiner Beleg-Helfer).
func score_loggen(prefix: String) -> bool:
	var h := host()
	if h == null:
		print("[PT3] %s: kein Host mehr" % prefix)
		return true
	print("[PT3] %s: Host-Score %d" % [prefix, int(h.get("score"))])
	return true


## ------------------------------------------------------- Werte-Zettel


func coins() -> int:
	var gs := game_state()
	return int(gs.get_value("economy.coins", 0)) if gs != null else 0


func energie() -> float:
	var gs := game_state()
	return float(gs.get_value("gooby.stats.energy", 0.0)) if gs != null else 0.0


## Zettel-Eintrag mit Log (interner Baustein der merke_*-Helfer).
func _merke(key: String, wert: Variant) -> bool:
	zettel[key] = wert
	print("[PT3] merke %s = %s" % [key, str(wert)])
	return true


## Werte ERST bei Schritt-Ausführung lesen (bind() würde beim Bauen der
## Schrittliste einfrieren — vor dem Onboarding!).
func merke_coins(key: String) -> bool:
	return _merke(key, coins())


func merke_energie(key: String) -> bool:
	return _merke(key, energie())


## Münzen seit merke_coins(key) gestiegen (Award unbekannter Höhe)?
func pruefe_coins_gestiegen(key: String) -> bool:
	var vorher := int(zettel.get(key, 0))
	var ist := coins()
	print("[PT3] Münzen: vorher %d, jetzt %d" % [vorher, ist])
	return ist > vorher


## Energie-Delta seit merke_energie(key) gegen soll_delta loggen/prüfen
## (±0,5 Toleranz — §C6: jeder echte Rundenstart bucht energy_cost ab).
func energie_delta_pruefen(key: String, soll_delta: float) -> bool:
	var vorher := float(zettel.get(key, 0.0))
	var ist := energie()
	var delta := ist - vorher
	print(
		(
			"[PT3] Energie: vorher %.1f, jetzt %.1f (Delta %+.1f, soll %+.1f)"
			% [vorher, ist, delta, soll_delta]
		)
	)
	return absf(delta - soll_delta) < 0.51


## ------------------------------------------------------- Router-Wache


## G7-Blocker-Regression: flüchtige Ziele (mg_pregame/mg_host) dürfen NIE
## in der Router-History stehen — sonst startet Arcade-„Zurück“ eine
## frische Runde statt nach Hause zu führen (Fix-Commit ec242ee3).
func history_sauber() -> bool:
	var router := harness.root.get_node_or_null("/root/SceneRouter")
	if router == null:
		return false
	var history: Array[StringName] = router.get_history()
	print("[PT3] Router-History: %s" % str(history))
	for ziel in history:
		if ziel == &"mg_host" or ziel == &"mg_pregame":
			print("[PT3] BLOCKER-REGRESSION: '%s' liegt in der History!" % ziel)
			return false
	return true


## ------------------------------------------------------- Schritt-Fabriken


## Ziel-Kachel/-Control in allen Scroll-Ahnen sichtbar rollen (Arcade-Grid
## clippt ab Reihe 3 — ein Tap auf weggescrollte Kacheln ginge daneben).
func anrollen(node_name: String) -> bool:
	var ziel := harness.root.find_child(node_name, true, false)
	if not (ziel is Control):
		print("[PT3] anrollen: '%s' nicht im Baum" % node_name)
		return false
	var ahn: Node = ziel.get_parent()
	var gerollt := 0
	while ahn != null:
		if ahn is ScrollContainer:
			(ahn as ScrollContainer).ensure_control_visible(ziel)
			gerollt += 1
		ahn = ahn.get_parent()
	print("[PT3] anrollen: '%s' über %d Scroller geholt" % [node_name, gerollt])
	return true


## Standard-Einstieg jedes Spiel-Flows: HUD → Arcade → Kachel anrollen +
## tippen → Pregame (optional Schwierigkeits-Chip) → Münzen/Energie merken
## → „Spielen!“ → Host da → Countdown abwarten (Runde läuft wirklich).
## energie_kosten = meta.energy_cost des Spiels (cityDrive: 6, sonst 8).
func arcade_pregame_schritte(
	game_id: String, schwierigkeit := "", energie_kosten := 8.0
) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{
			"name": "arcade_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnArcade",
			"erwarte": {"route": "arcade"},
			"timeout_s": 90.0,
		},
		{"name": "arcade_ansehen", "aktion": "warte", "sekunden": 2.0},
	]
	# Doppelt rollen: verschachtelte Scroller sitzen erst nach einem
	# Layout-Frame endgültig (PT-2-Lauf-Lektion pt2_c1).
	for i in 2:
		(
			out
			. append(
				{
					"name": "kachel_anrollen_%d" % (i + 1),
					"aktion": "tue",
					"funktion": anrollen.bind("Tile_%s" % game_id),
					"pflicht": false,
				}
			)
		)
		out.append({"name": "roll_pause_%d" % (i + 1), "aktion": "warte", "sekunden": 0.6})
	(
		out
		. append_array(
			[
				# Route-Erwartung statt Text: is_busy() deckt das LoadingVeil
				# ab — ein Text-Treffer käme schon UNTER dem Veil (Lauf pt3_a1:
				# der „Spielen!“-Tap verpuffte im Veil-Blocker).
				{
					"name": "kachel_waehlen",
					"aktion": "tipp_name",
					"node": "Tile_%s" % game_id,
					"erwarte": {"route": "mg_pregame"},
					"timeout_s": 90.0,
				},
				{"name": "pregame_ansehen", "aktion": "warte", "sekunden": 1.5},
			]
		)
	)
	if schwierigkeit != "":
		(
			out
			. append(
				{
					"name": "schwierigkeit_waehlen",
					"aktion": "tipp_text",
					"text": schwierigkeit,
					"timeout_s": 20.0,
					"pflicht": false,
				}
			)
		)
	(
		out
		. append_array(
			[
				# GETRENNTE Zettel-Schlüssel (Lauf pt3_b1: „start“ für Münzen
				# UND Energie überschrieb den Münz-Basiswert).
				{
					"name": "start_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("start_coins"),
				},
				{
					"name": "start_energie_merken",
					"aktion": "tue",
					"funktion": merke_energie.bind("start_energie"),
				},
				{
					"name": "spiel_starten",
					"aktion": "tipp_text",
					"text": "Spielen!",
					"erwarte": {"route": "mg_host"},
					"timeout_s": 120.0,
				},
				{
					"name": "countdown_abwarten",
					"aktion": "warte_bis",
					"bedingung": spiel_aktiv,
					"timeout_s": 90.0,
				},
				{
					"name": "energie_abgebucht",
					"aktion": "tue",
					"funktion": energie_delta_pruefen.bind("start_energie", -energie_kosten),
					"erwartung": "Rundenstart bucht energy_cost ab (§C6)",
					"pflicht": false,
				},
			]
		)
	)
	return out


## ------------------------------------------------------- intern


## Sichtbaren Node per Script-Klassenname finden (Spiegel der Harness-Suche).
func _suche_klasse(node: Node, klasse: String) -> Node:
	var skript: Script = node.get_script()
	if skript != null and skript.get_global_name() == StringName(klasse):
		if not (node is Control) or (node as Control).is_visible_in_tree():
			return node
	for kind in node.get_children():
		var treffer := _suche_klasse(kind, klasse)
		if treffer != null:
			return treffer
	return null

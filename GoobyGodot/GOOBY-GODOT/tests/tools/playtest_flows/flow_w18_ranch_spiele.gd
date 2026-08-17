extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## W18/3-Playtest (Agent 5) — Flow „Ranch-Spiele“: beide Ranch-Minispiele
## über die Arcade wie ein Spieler. (1) Arena-Wettbewerb: Turnier-Liga
## öffnen, Disziplin „Schau-Wettbewerb“ (Simon-Says-Kür) reiten — die
## ersten Kommandos ECHT über den „Jetzt!“-Knopf, die letzten beiden
## deterministisch im Idealmoment (Test-Griff: richter._zeit stellen wie
## die Patty-Uhr im McGooby-Flow, llvmpipe schafft ±300 ms nicht ehrlich),
## Endstand/Belohnung/Teilnahme-Buchung gegenprüfen, Siegerehrung falls
## Platz 1–3. (2) Schaf-Hüten: Level 1, Herde per Feld-Taps (Bot-Politik
## als Tipp-Ziel — die W15-Forgiveness) durchs Tor treiben, Sterne-Buchung
## prüfen. Geld-Wache: Arena/Herde dürfen Münzen nur GUTSCHREIBEN.
## Aufruf: tools/ci/run_playtest.sh flow_w18_ranch_spiele

const HerdeLogic := preload("res://scripts/minigames/games/ranch_herde/herde_logic.gd")

## Anzahl Treib-Taps für Level 1 (3 Schafe, 61 s Limit).
const HERDE_TAPS := 26

var _muenzen_vor_arena := -1
var _herde_fallback_gebraucht := false


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_arena())
	liste.append_array(_schritte_herde())
	return liste


## ---------------------------------------------------- (d) Arena-Wettbewerb


func _schritte_arena() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(arcade_bis_pregame("ranchTurnier", 1))
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{
					"name": "turnier_menu_da",
					"aktion": "warte_bis",
					"text": "Turnierplatz",
					"timeout_s": 60.0,
				},
				{"name": "turnier_menu_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "arena_muenzen_merken",
					"aktion": "tue",
					"funktion": merke_muenzen_vor_arena,
					"erwartung": "Münzstand vor dem Turnier notiert",
				},
				# HARNESS-FALLE (Lauf w18a5_spiele/1): das Turnier-UI lebt im
				# letterboxten SubViewport — tipp_text tippt auf UNGEMAPPTE
				# Koordinaten und traf „Grasbahn-Rennen“ statt der Schau.
				# Deshalb alle In-Game-Taps über spiel_text_pos (spielfeld_punkt).
				# BEFUND (Lauf w21_mg_ranch_quer/024): die Schau-Kachel hängt im
				# ScrollContainer UNTER der Falz — erst scrollen (wie beim
				# Fertig-Knopf), sonst tippt der Fallback ins Leere.
				{
					"name": "turnier_menu_zur_schau_scrollen",
					"aktion": "tue",
					"funktion": turnier_menu_scrollen,
					"erwartung": "Turnier-Menü gescrollt — Schau-Kachel im Sichtfenster",
				},
				{"name": "schau_kachel_ruhe", "aktion": "warte", "sekunden": 0.5},
				{
					"name": "disziplin_schau_waehlen",
					"aktion": "tipp_pos",
					"pos_funktion": spiel_text_pos.bind("Schau-Wettbewerb"),
					"erwarte": {"bedingung": disziplin_schau_ok},
					"timeout_s": 30.0,
				},
				{"name": "einweisung_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "los_gehts",
					"aktion": "tipp_pos",
					"pos_funktion": spiel_text_pos.bind("Los geht"),
					"erwarte": {"bedingung": schau_lauf_da},
					"timeout_s": 60.0,
				},
			]
		)
	)
	for i in [1, 2, 3]:
		(
			liste
			. append_array(
				[
					{
						"name": "kommando_%d_abwarten" % i,
						"aktion": "warte_bis",
						"bedingung": kommando_angesagt,
						"timeout_s": 20.0,
						"pflicht": false,
					},
					{
						"name": "kommando_%d_jetzt_knopf" % i,
						"aktion": "tipp_pos",
						"pos_funktion": spiel_text_pos.bind("Jetzt!"),
						"pflicht": false,
					},
				]
			)
		)
	for i in [4, 5]:
		(
			liste
			. append_array(
				[
					{
						"name": "kommando_%d_abwarten" % i,
						"aktion": "warte_bis",
						"bedingung": kommando_angesagt,
						"timeout_s": 20.0,
						"pflicht": false,
					},
					{
						"name": "kommando_%d_idealtreffer" % i,
						"aktion": "tue",
						"funktion": schau_exakt_tippen,
						"erwartung": "Tipp im Idealmoment wird als Treffer gewertet",
						"pflicht": false,
					},
				]
			)
		)
	(
		liste
		. append_array(
			[
				{
					"name": "endstand_da",
					"aktion": "warte_bis",
					"text": "Endstand",
					"timeout_s": 120.0,
				},
				{"name": "endstand_ansehen", "aktion": "warte", "sekunden": 2.5},
				{
					"name": "teilnahme_verbucht",
					"aktion": "tue",
					"funktion": teilnahme_verbucht,
					"erwartung": "ranch.comp.teilnahmen wurde hochgezählt",
				},
				{
					"name": "keine_muenzen_verloren",
					"aktion": "tue",
					"funktion": keine_muenzen_verloren,
					"erwartung": "Arena zieht keine Münzen ab (nur Gold-Gutschrift)",
				},
				{
					"name": "endstand_weiter",
					"aktion": "tipp_pos",
					"pos_funktion": spiel_text_pos.bind("Weiter"),
					"timeout_s": 30.0,
				},
				{"name": "nach_endstand_ruhe", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "zeremonie_falls_podium",
					"aktion": "tipp_pos",
					"pos_funktion": spiel_text_pos.bind("Zur Übersicht"),
					"pflicht": false,
				},
				{
					"name": "zurueck_im_menu",
					"aktion": "warte_bis",
					"text": "Turnierplatz",
					"timeout_s": 60.0,
				},
				{
					"name": "heute_geritten_markiert",
					"aktion": "warte_bis",
					"text": "Heute geritten",
					"timeout_s": 15.0,
					"pflicht": false,
				},
				# BEFUND (Lauf w18a5_spiele2): der Fertig-Knopf des Turnier-
				# platzes hängt IM ScrollContainer und liegt quer unter der
				# Falz — ohne Scroll erreicht ihn kein Tap (comp_level_select
				# hält seinen Fertig-Fuß bewusst AUSSERHALB des Scrolls).
				{
					"name": "turnier_menu_ans_ende_scrollen",
					"aktion": "tue",
					"funktion": turnier_menu_scrollen,
					"erwartung": "Turnier-Menü ans Ende gescrollt (Fertig sichtbar)",
				},
				{"name": "turnier_fuss_ruhe", "aktion": "warte", "sekunden": 0.5},
				{
					"name": "turnier_fertig",
					"aktion": "tipp_pos",
					"pos_funktion": spiel_text_pos.bind("Fertig"),
					"erwarte": {"text": "Runde vorbei!"},
					"timeout_s": 60.0,
				},
				{"name": "turnier_results_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "zurueck_zur_arcade",
					"aktion": "tipp_text",
					"text": "Zur Arcade",
					"erwarte": {"route": "arcade"},
					"timeout_s": 90.0,
				},
				{"name": "arcade_wieder_da", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## ------------------------------------------------------ (c) Schaf-Hüten


func _schritte_herde() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "herde_kachel_sichtbar",
			"aktion": "tue",
			"funktion": kachel_einblenden.bind("Tile_ranchHerde"),
			"erwartung": "Kachel Tile_ranchHerde liegt im Scroll-Fenster",
		},
		{"name": "herde_kachel_ruhe", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "herde_kachel_tippen",
			"aktion": "tipp_name",
			"node": "Tile_ranchHerde",
			"erwarte": {"text": "Spielen!"},
			"timeout_s": 60.0,
		},
		{"name": "herde_pregame_ansehen", "aktion": "warte", "sekunden": 2.0},
	]
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{
					"name": "herde_levelwahl_da",
					"aktion": "warte_bis",
					"text": "Schaf-Hüten",
					"timeout_s": 60.0,
				},
				{"name": "herde_levelwahl_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "herde_level1_tippen",
					"aktion": "tipp_pos",
					"pos_funktion": herde_level1_pos,
					"erwarte": {"bedingung": herde_laeuft},
					"timeout_s": 20.0,
					"pflicht": false,
				},
				{
					"name": "herde_level_sicherstellen",
					"aktion": "tue",
					"funktion": herde_level_sicherstellen,
					"erwartung": "Level 1 läuft (Tap oder Signal-Fallback)",
				},
				{"name": "herde_feld_ansehen", "aktion": "warte", "sekunden": 1.5},
			]
		)
	)
	for i in HERDE_TAPS:
		(
			liste
			. append(
				{
					"name": "herde_treib_tap_%02d" % (i + 1),
					"aktion": "tipp_pos",
					"pos_funktion": herde_treib_pos,
					"pflicht": false,
				}
			)
		)
	(
		liste
		. append_array(
			[
				{
					"name": "herde_runde_endet",
					"aktion": "warte_bis",
					"bedingung": herde_runde_vorbei,
					"timeout_s": 100.0,
				},
				{
					"name": "herde_alle_schafe_drin",
					"aktion": "tue",
					"funktion": herde_alle_drin,
					"erwartung": "Alle 3 Schafe vor Ablauf der Zeit im Pferch",
					"pflicht": false,
				},
				{
					"name": "herde_levelwahl_wieder_da",
					"aktion": "warte_bis",
					"text": "Schaf-Hüten",
					"timeout_s": 30.0,
				},
				{
					"name": "herde_sterne_verbucht",
					"aktion": "tue",
					"funktion": herde_sterne_verbucht,
					"erwartung": "Level-1-Sterne stehen in ranch.spiele.herde",
					"pflicht": false,
				},
				{
					"name": "herde_fertig",
					"aktion": "tipp_pos",
					"pos_funktion": spiel_text_pos.bind("Fertig"),
					"erwarte": {"text": "Runde vorbei!"},
					"timeout_s": 60.0,
				},
				{"name": "herde_results_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "nach_hause",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## ------------------------------------------------------------ Arena-Wachen


## Canvas-Tap-Punkt eines SPIEL-UI-Elements mit Text: das Minispiel lebt im
## letterboxten SubViewport, get_global_rect liefert also SPIEL-Koordinaten
## — erst spielfeld_punkt macht daraus Fenster-Canvas-Koordinaten (Harness-
## Falle aus Lauf w18a5_spiele/1: tipp_text traf die falsche Disziplin).
## Fallback: tote Ecke unten links (löst in Menüs nichts aus).
func spiel_text_pos(text: String) -> Vector2:
	var spiel := spiel_node()
	if spiel == null:
		return spielfeld_pos(Vector2(0.02, 0.98))
	var ziel: Control = harness._finde_text(spiel, text)
	if ziel == null:
		return spielfeld_pos(Vector2(0.02, 0.98))
	return spielfeld_punkt(ziel.get_global_rect().get_center())


## Turnier-Menü ans Ende scrollen: der Fertig-Knopf lebt IM Scrollbereich
## und liegt quer unter der Falz (Befund w18a5_spiele2/046) — wie ein
## Spieler scrollen, dann tippen.
func turnier_menu_scrollen() -> bool:
	var spiel := spiel_node()
	if spiel == null:
		return false
	var menu: Variant = spiel.get("_menu")
	if not (menu is Node):
		return false
	var scroll := _erster_scroll(menu)
	if scroll == null:
		return false
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	return true


func _erster_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for kind in node.get_children():
		var gefunden := _erster_scroll(kind)
		if gefunden != null:
			return gefunden
	return null


## Einweisung zeigt wirklich die SCHAU (nicht die Nachbar-Disziplin).
func disziplin_schau_ok() -> bool:
	var spiel := spiel_node()
	return spiel != null and str(spiel.get("_disziplin")) == "schau"


## Der Kür-Lauf ist gestartet (lauf + Schau-Richter stehen).
func schau_lauf_da() -> bool:
	return _schau_richter() != null


func merke_muenzen_vor_arena() -> bool:
	_muenzen_vor_arena = _muenzen()
	return _muenzen_vor_arena >= 0


func _muenzen() -> int:
	var gs := game_state()
	return int(gs.get_value("economy.coins", -1)) if gs != null else -1


## Progression-Wache: die Arena darf Münzen nur gutschreiben, nie abziehen.
func keine_muenzen_verloren() -> bool:
	return _muenzen_vor_arena >= 0 and _muenzen() >= _muenzen_vor_arena


func _schau_lauf() -> RcompLauf:
	var spiel := spiel_node()
	if spiel == null:
		return null
	var lauf: Variant = spiel.get("lauf")
	return lauf if lauf is RcompLauf else null


func _schau_richter() -> RcompRichterSchau:
	var lauf := _schau_lauf()
	if lauf == null:
		return null
	var richter: Variant = lauf.get("richter")
	return richter if richter is RcompRichterSchau else null


## Kommando ist angesagt und wartet auf den Tipp.
func kommando_angesagt() -> bool:
	var richter := _schau_richter()
	if richter == null or richter.fertig():
		return false
	return bool(richter._angesagt)


## Test-Griff (llvmpipe-Frames sind zu grob für ±300 ms): die Kür-Uhr auf
## den Idealmoment stellen und über die ECHTE Lauf-API tippen — geprüft
## wird die Wertungs-Logik (Treffer), nicht das Renderer-Timing.
func schau_exakt_tippen() -> bool:
	var lauf := _schau_lauf()
	var richter := _schau_richter()
	if lauf == null or richter == null or richter.fertig():
		return false
	var kommando := richter.aktuelles_kommando()
	if kommando.is_empty():
		return false
	richter._zeit = float(kommando["zeit_s"])
	var wertung := lauf.tippe()
	return str(wertung.get("typ", "")) == "treffer"


func teilnahme_verbucht() -> bool:
	var comp := RanchCompState.lese(game_state())
	return int(comp.get("teilnahmen", 0)) >= 1


## ------------------------------------------------------------ Herde-Wachen


func _herde_spiel() -> Node:
	return spiel_node()


func herde_laeuft() -> bool:
	var spiel := _herde_spiel()
	return spiel != null and bool(spiel.get("level_running"))


## Mitte der L1-Kachel im Canvas-Raum (Level-Select lebt im SubViewport —
## spielfeld_punkt rechnet Spiel-Pixel in Canvas-Koordinaten um).
func herde_level1_pos() -> Vector2:
	var select: Node = harness._finde_klasse(harness.root, "RanchLevelSelect")
	if select == null:
		return spielfeld_pos(Vector2(0.5, 0.5))
	var buttons: Variant = select.get("_buttons")
	if not (buttons is Array) or (buttons as Array).is_empty():
		return spielfeld_pos(Vector2(0.5, 0.5))
	var knopf: Button = (buttons as Array)[0]
	return spielfeld_punkt(knopf.get_global_rect().get_center())


## Wache mit Fallback: hat der Positions-Tap nicht gezündet, wählt das
## Level-Signal (ECHTER Spiel-Einstiegspfad) Level 1 — der Fallback wird
## fürs Protokoll gemerkt (Befund-Kandidat: Kachel-Tap kam nicht an).
func herde_level_sicherstellen() -> bool:
	if herde_laeuft():
		return true
	var select: Node = harness._finde_klasse(harness.root, "RanchLevelSelect")
	if select == null:
		return false
	_herde_fallback_gebraucht = true
	(select as RanchLevelSelect).level_chosen.emit(1)
	return herde_laeuft()


## Treib-Ziel der zertifizierten Bot-Politik als Canvas-Tap-Punkt — das
## Spiel bekommt einen ECHTEN Feld-Tap an der klügsten Stelle.
func herde_treib_pos() -> Vector2:
	var spiel := _herde_spiel()
	if spiel == null or not bool(spiel.get("level_running")):
		return spielfeld_pos(Vector2(0.5, 0.9))
	var schafe: Array = spiel.get("schafe")
	var level: Dictionary = spiel.get("level")
	var ziel: Vector2 = HerdeLogic.bot_ziel(schafe, level)
	var screen: Vector2 = spiel._screen_pos(Vector3(ziel.x, 0.0, ziel.y))
	return spielfeld_punkt(screen)


func herde_runde_vorbei() -> bool:
	var spiel := _herde_spiel()
	return spiel != null and not bool(spiel.get("level_running"))


func herde_alle_drin() -> bool:
	var spiel := _herde_spiel()
	if spiel == null:
		return false
	var schafe: Array = spiel.get("schafe")
	return not schafe.is_empty() and HerdeLogic.drin_anzahl(schafe) == schafe.size()


func herde_sterne_verbucht() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	return RanchSpieleProgress.level_stars(gs, RanchSpieleProgress.SPIEL_HERDE, 1) >= 1

extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## W19-Playtest — Flow „Arcade-Spotlight (Spiel des Tages)“: die komplette
## Bonus-Strecke des Pakets W19/SPOTLIGHT wie ein Spieler:
## (1) Fixture: die INJIZIERTE GameState-Uhr wird auf den nächsten Tag
##     gepinnt, an dem der Sternenhüpfer (starHopper) das Spiel des Tages
##     ist (deterministische Rotation, ArcadeSpotlight.spotlight_id) —
##     dadurch ist der Lauf an JEDEM Realdatum reproduzierbar,
## (2) Arcade: die Spotlight-Kachel trägt das goldene „Spiel des Tages“-
##     Banner (SpotlightBadge an der Cover-Unterkante) + den Puls-Rahmen
##     (SpotlightGlow) — und zwar an GENAU der berechneten Kachel,
## (3) Pregame zeigt die Bonus-Zeile („+50 % Münzen — einmal heute!“),
## (4) eine echte kurze Runde (Meteor-Treffer oder 75-s-Uhr beendet sie),
##     Results zeigt die Bonus-Zeile „Spiel des Tages: +n Münzen“ und der
##     Save trägt den Einmal-Marker (minigames.spotlightBonusDay),
## (5) zweite Runde am SELBEN Tag: Pregame sagt ehrlich „Tagesbonus schon
##     eingelöst“, die Results-Karte zeigt KEINE zweite Bonus-Zeile.
## Format: quer 2868x1320 (Default) UND hochkant 1320x2868.
## Aufruf: tools/ci/run_playtest.sh flow_w19_spotlight
##         tools/ci/run_playtest.sh flow_w19_spotlight 1320x2868

## Das Wunsch-Spotlight des Laufs: Sternenhüpfer endet von selbst (EIN
## Meteor-Treffer oder 75-s-Uhr) — die Runde braucht keine Spielereingabe.
const SPIEL := "starHopper"
const KACHEL := "Tile_%s" % SPIEL
const TAG_MS := 86400000
## Wie viele Tage die Fixture maximal vorspult (Rotations-Kette streut
## gleichmäßig — bei n Spielen ist der Treffer nach wenigen Tagen da).
const SUCHE_TAGE := 120

## Der gepinnte Spotlight-Tag (YYYY-MM-DD) für die Marker-Wachen.
var _tag := ""
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_kachel())
	liste.append_array(_schritte_runde_mit_bonus())
	liste.append_array(_schritte_runde_eingeloest())
	return liste


## ------------------------- Arcade: Banner + Puls-Rahmen an der Kachel


func _schritte_kachel() -> Array[Dictionary]:
	return [
		{
			"name": "staging_spotlight_tag",
			"aktion": "tue",
			"funktion": staging_spotlight_tag,
			"erwartung": "Uhr auf den nächsten %s-Spotlight-Tag gepinnt" % SPIEL,
		},
		{
			"name": "arcade_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnArcade",
			"erwarte": {"route": "arcade"},
			"timeout_s": 60.0,
		},
		{"name": "arcade_ansehen", "aktion": "warte", "sekunden": 2.0},
		# Spieler-Wische (Touch-Scrolling), dann die Kachel deterministisch
		# ins Sichtfenster holen (Muster flow_mg_basis.arcade_bis_pregame).
		{
			"name": "arcade_scrollen",
			"aktion": "wisch",
			"von_rel": Vector2(0.5, 0.75),
			"nach_rel": Vector2(0.5, 0.3),
			"dauer_s": 0.6,
		},
		{
			"name": "kachel_sichtbar_machen",
			"aktion": "tue",
			"funktion": kachel_einblenden.bind(KACHEL),
			"erwartung": "Kachel %s existiert und liegt im Scroll-Fenster" % KACHEL,
		},
		{"name": "kachel_ruhe", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "spotlight_markierung_da",
			"aktion": "tue",
			"funktion": spotlight_markierung_da,
			"erwartung": "SpotlightBadge + SpotlightGlow sitzen an %s" % KACHEL,
		},
		{
			"name": "kachel_tippen",
			"aktion": "tipp_name",
			"node": KACHEL,
			"erwarte": {"text": "Spielen!"},
			"timeout_s": 60.0,
		},
		{"name": "pregame_ansehen", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------ Runde 1: Bonus versprochen + ausgezahlt


func _schritte_runde_mit_bonus() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "pregame_bonus_zeile",
			"aktion": "tue",
			"funktion": pregame_bonus_zeile,
			"erwartung": "SpotlightLine verspricht +50 % — einmal heute",
		},
		{
			"name": "kasse_merken",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
	]
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{"name": "fliegen_lassen", "aktion": "warte", "sekunden": 3.0},
				runde_zu_ende(160.0),
				{"name": "results_ansehen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "results_bonus_zeile",
					"aktion": "tue",
					"funktion": results_bonus_zeile,
					"erwartung": "„Spiel des Tages: +n Münzen“-Zeile sichtbar",
				},
				{
					"name": "bonus_verbucht",
					"aktion": "tue",
					"funktion": bonus_verbucht,
					"erwartung": "Einmal-Marker gestempelt + Münzen gestiegen",
				},
			]
		)
	)
	return liste


## ------------------- Runde 2 am selben Tag: ehrlich „schon eingelöst“


func _schritte_runde_eingeloest() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "zurueck_zur_arcade",
			"aktion": "tipp_text",
			"text": "Zur Arcade",
			"erwarte": {"route": "arcade"},
			"timeout_s": 90.0,
		},
		{"name": "arcade_ruhe", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "kachel_wieder_sichtbar",
			"aktion": "tue",
			"funktion": kachel_einblenden.bind(KACHEL),
			"erwartung": "Kachel %s liegt im Scroll-Fenster" % KACHEL,
		},
		{"name": "kachel_ruhe_2", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "kachel_tippen_2",
			"aktion": "tipp_name",
			"node": KACHEL,
			"erwarte": {"text": "Spielen!"},
			"timeout_s": 60.0,
		},
		{"name": "pregame_ansehen_2", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "pregame_eingeloest_zeile",
			"aktion": "tue",
			"funktion": pregame_eingeloest_zeile,
			"erwartung": "SpotlightLine sagt ehrlich „Tagesbonus schon eingelöst“",
		},
	]
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{"name": "fliegen_lassen_2", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "runde2_zu_ende",
					"aktion": "warte_bis",
					"text": "Runde vorbei!",
					"timeout_s": 160.0,
				},
				{"name": "results2_ansehen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "results2_ohne_bonus_zeile",
					"aktion": "tue",
					"funktion": results_ohne_bonus_zeile,
					"erwartung": "KEINE zweite Bonus-Zeile am selben Tag",
				},
				{
					"name": "results_nach_hause",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 90.0,
					"pflicht": false,
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## ---------------------------------------------------------------- Bausteine


## Fixture: Uhr auf den nächsten Kalendertag pinnen, an dem SPIEL das
## Spotlight ist (Rotation aus ArcadeSpotlight — deterministisch, ohne
## OS-Zufall). k=0 lässt den Realtag zu, sonst wird vorgespult.
func staging_spotlight_tag() -> bool:
	var gs := game_state()
	if gs == null or not ("clock" in gs) or gs.clock == null:
		return false
	var jetzt := int(gs.clock.now_ms())
	var spiele := MinigameRegistry.all_games()
	for k in SUCHE_TAGE:
		var kandidat := jetzt + k * TAG_MS
		var tag: String = gs.clock.local_day(kandidat)
		if ArcadeSpotlight.spotlight_id(spiele, tag) == SPIEL:
			gs.clock.pin(kandidat)
			# Der Uhr-Sprung würde sonst k Tage §C1-Verfall nachholen —
			# Gooby wäre „zu müde zum Spielen“ (Pregame-Energie-Gate).
			# Deshalb lastTickAt mitziehen + Stats auffüllen (W19-Lehre).
			gs.set_value("gooby.lastTickAt", kandidat)
			for stat: String in ["hunger", "energy", "hygiene", "fun"]:
				gs.set_value("gooby.stats.%s" % stat, 90.0)
			_tag = tag
			print("[FLOW] Spotlight-Tag gepinnt: %s (+%d Tage)" % [tag, k])
			return true
	return false


## Banner + Puls-Rahmen sitzen an GENAU der berechneten Spotlight-Kachel.
func spotlight_markierung_da() -> bool:
	var badge := harness.root.find_child("SpotlightBadge", true, false)
	var glow := harness.root.find_child("SpotlightGlow", true, false)
	if badge == null or glow == null:
		return false
	return _kachel_vorfahr(badge) == KACHEL and _kachel_vorfahr(glow) == KACHEL


func pregame_bonus_zeile() -> bool:
	var zeile := _spotlight_line()
	if zeile == null:
		return false
	return zeile.text.contains("einmal heute")


func pregame_eingeloest_zeile() -> bool:
	var zeile := _spotlight_line()
	if zeile == null:
		return false
	return zeile.text.contains("schon eingelöst")


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	return true


## Results-Zeile „Spiel des Tages: +n Münzen“ steht sichtbar auf der
## Results-Karte („Runde vorbei!“ als Anker — die PREGAME-Bonus-Zeile
## enthält denselben Präfix und wäre sonst ein falsch-positiver Treffer).
func results_bonus_zeile() -> bool:
	if harness._finde_text(harness.root, "Runde vorbei!") == null:
		return false
	var zeile: Control = harness._finde_text(harness.root, "Spiel des Tages: +")
	return zeile != null and not str(zeile.get("text")).contains("%")


## Runde 2 am selben Tag: die Bonus-Zeile darf auf der Results-Karte
## NICHT wiederkommen (Anker „Runde vorbei!“ wie oben).
func results_ohne_bonus_zeile() -> bool:
	if harness._finde_text(harness.root, "Runde vorbei!") == null:
		return false
	return harness._finde_text(harness.root, "Spiel des Tages: +") == null


## Der Bonus ist verbucht: Einmal-Marker trägt den gepinnten Tag und die
## Kasse ist gestiegen (Basis + Tages-×2 + Spotlight-Bonus).
func bonus_verbucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0 or _tag.is_empty():
		return false
	if str(gs.get_value("minigames.%s" % ArcadeSpotlight.MARKER_KEY, "")) != _tag:
		return false
	return int(gs.get_value("economy.coins", 0)) > _muenzen_vorher


## Kachel-Name (Tile_*) des nächstgelegenen Button-Vorfahren.
func _kachel_vorfahr(node: Node) -> String:
	var aktuell: Node = node
	while aktuell != null:
		if aktuell is Button and str(aktuell.name).begins_with("Tile_"):
			return str(aktuell.name)
		aktuell = aktuell.get_parent()
	return ""


## Die Pregame-Spotlight-Zeile (null, wenn nicht sichtbar).
func _spotlight_line() -> Label:
	var zeile := harness.root.find_child("SpotlightLine", true, false)
	if not (zeile is Label) or not (zeile as Label).is_visible_in_tree():
		return null
	return zeile as Label

extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18/J4-Playtest — Flow „Stadt-Tagesrhythmus": die Stadt zu ZWEI Tages-
## zeiten erleben, gesteuert über den DEV-Zeit-Override (derselbe Pfad wie
## der Zeit-Tab im DEV-Tools-Kasten: Dev.set_clock_offset_ms pinnt die
## injizierte GameState-Clock — CityScene._stunde() liest genau diese Uhr).
## Ablauf: Uhr auf MORGEN (8:30) pinnen → in die Stadt reisen (ruhiger
## Verkehr, Laternen aus, Zeitungs-Gooby-Fenster) → Uhr LIVE auf ABEND
## (19:30) stellen — die gebaute Stadt schaltet ohne Neubau um (goldene
## Sonne, Laternen + Lichtkegel an, Fensterlichter, Auto-Scheinwerfer,
## weniger Verkehr). Screenshots morgens vs. abends zeigen den Unterschied
## (Licht, Dichte, CC0-Häuser).
## Aufruf: tools/ci/run_playtest.sh flow_j4_stadt_rhythmus

const MORGEN_STUNDE := 8.5
const ABEND_STUNDE := 19.5
## Uhr-Toleranz in h: der Offset läuft weiter (DevZeit re-pinnt pro Frame),
## zwischen Setzen und Prüfen vergeht etwas Echtzeit.
const STUNDEN_TOLERANZ := 0.35


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ritual_puffer())
	liste.append_array(_schritte_morgen())
	liste.append_array(_schritte_abend())
	return liste


## ------------------------------------------------------- Morgen (8:30 Uhr)


func _schritte_morgen() -> Array[Dictionary]:
	return [
		{
			"name": "uhr_auf_morgen_stellen",
			"aktion": "tue",
			"funktion": stelle_uhr_auf_morgen,
			"erwartung": "DEV-Zeit-Override pinnt die GameState-Clock auf ~8:30",
		},
		{"name": "catchup_beruhigen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "catchup_overlays_wegtippen",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_morgens_ankommen", "aktion": "warte", "sekunden": 6.0},
		{
			"name": "morgen_rhythmus_check",
			"aktion": "tue",
			"funktion": pruefe_morgen,
			"erwartung": "8:30: Phase morgen, ruhige Dichte, Laternen/Fenster AUS",
		},
		{
			"name": "morgen_strasse_ansehen",
			"aktion": "tue",
			"funktion": rolle_auf_die_strasse,
			"erwartung": "Auto steht auf der Wohnstraße (CC0-Häuser im Blick)",
		},
		{"name": "morgen_screenshot_strasse", "aktion": "warte", "sekunden": 4.0},
	]


## -------------------------------------------------------- Abend (19:30 Uhr)


func _schritte_abend() -> Array[Dictionary]:
	return [
		{
			"name": "uhr_auf_abend_stellen",
			"aktion": "tue",
			"funktion": stelle_uhr_auf_abend,
			"erwartung": "DEV-Zeit-Override springt LIVE auf ~19:30 (kein Neubau)",
		},
		# Rhythmus-Tick (0,5 s) + Skalen-Fade (1,2 s) durchlaufen lassen.
		{"name": "abendlicht_umschalten_lassen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "abend_rhythmus_check",
			"aktion": "tue",
			"funktion": pruefe_abend,
			"erwartung": "19:30: goldene Stunde, Laternen+Fenster AN, Dichte folgt Kurve",
		},
		{"name": "abend_screenshot_strasse", "aktion": "warte", "sekunden": 4.0},
		{
			"name": "abend_screenshot_laternen",
			"aktion": "tue",
			"funktion": rolle_ein_stueck_weiter,
			"erwartung": "Auto rollt ein Stück die Straße entlang (Laternen im Bild)",
		},
		{"name": "abend_abschluss", "aktion": "warte", "sekunden": 4.0},
	]


## ---------------------------------------------------------------- Bausteine


func stelle_uhr_auf_morgen() -> bool:
	return _setze_uhr_auf(MORGEN_STUNDE)


func stelle_uhr_auf_abend() -> bool:
	return _setze_uhr_auf(ABEND_STUNDE)


## DEV-Zeit-Override wie der Zeit-Tab im Dev-Menü: Offset in ms auf die
## Systemzeit, Dev.set_clock_offset_ms pinnt die GameState-Clock (und
## re-pinnt pro Frame, die Uhr LÄUFT also mit Offset weiter).
func _setze_uhr_auf(ziel_stunde: float) -> bool:
	var dev := harness.root.get_node_or_null("/root/Dev")
	if dev == null or not dev.has_method("set_clock_offset_ms"):
		return false
	var jetzt := Time.get_time_dict_from_system()
	var stunde := (
		float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0 + float(jetzt["second"]) / 3600.0
	)
	var delta_h := fposmod(ziel_stunde - stunde, 24.0)
	if delta_h < 0.1:
		delta_h += 24.0
	dev.set_clock_offset_ms(int(delta_h * 3_600_000.0))
	return true


## Morgens 8:30 — die Wächter-Erwartungen aus test_city_rhythmus.gd live:
## Phase "morgen", aktive Dichte == Kurvenwert, Laternen-Birnen und
## Fensterlichter existieren nicht (oder sind unsichtbar, nach Nacht-
## Zwischenspiel — beides lazy gebaut), Auto-Scheinwerfer aus.
func pruefe_morgen() -> bool:
	return _pruefe_stadt(MORGEN_STUNDE, "morgen", false)


## Abends 19:30 — dieselbe Stadt, LIVE umgeschaltet: goldene Stunde heißt
## Laternen-Birnen + Lichtkegel sichtbar, Fensterlichter voll an, Auto-
## Scheinwerfer an, Dichte folgt der Abend-Kurve (weniger als mittags).
func pruefe_abend() -> bool:
	return _pruefe_stadt(ABEND_STUNDE, "abend", true)


## Gemeinsamer Rhythmus-Check: Stunde nah am Soll, Phase, Dichte auf der
## Kurve, Nachtlichter (Laternen-Birnen/Fensterlichter/Scheinwerfer)
## GENAU dann sichtbar, wenn `lichter` es verlangt.
func _pruefe_stadt(soll_stunde: float, soll_phase: String, lichter: bool) -> bool:
	var stadt := _stadt()
	if stadt == null:
		return false
	var stunde := float(stadt.get("_stunde_cache"))
	var befunde: Array[String] = []
	if absf(stunde - soll_stunde) > STUNDEN_TOLERANZ:
		befunde.append("Stadt-Stunde %.2f statt ~%.1f" % [stunde, soll_stunde])
	if CityRhythmus.phase(stunde) != soll_phase:
		befunde.append("Phase %s statt %s" % [CityRhythmus.phase(stunde), soll_phase])
	if not _dichte_folgt_kurve(stadt, stunde):
		befunde.append("Dichte weicht von der Kurve ab")
	if _sichtbar(stadt.get_node_or_null("Laternen/Birnen")) != lichter:
		befunde.append("Laternen-Birnen sichtbar=%s erwartet=%s" % [not lichter, lichter])
	if _sichtbar(stadt.get_node_or_null("Fensterlichter")) != lichter:
		befunde.append("Fensterlichter sichtbar=%s erwartet=%s" % [not lichter, lichter])
	if stadt.auto != null and stadt.auto.licht_an != lichter:
		befunde.append("Auto-Scheinwerfer an=%s erwartet=%s" % [stadt.auto.licht_an, lichter])
	for befund in befunde:
		push_warning("Rhythmus-Check %s: %s" % [soll_phase, befund])
	return befunde.is_empty()


## Aktive Autos/Goobys == Rhythmus-Kurvenwert zur Stadt-Stunde (die Pools
## sind größer — gezählt wird die AKTIVE Teilliste).
func _dichte_folgt_kurve(stadt: Node, stunde: float) -> bool:
	var verkehr: Array = stadt.get("_verkehr")
	var fussgaenger: Array = stadt.get("_fussgaenger")
	var v_soll := CityRhythmus.verkehr_anzahl(stunde)
	var f_soll := CityRhythmus.fussgaenger_anzahl(stunde)
	if verkehr.size() != v_soll or fussgaenger.size() != f_soll:
		push_warning(
			(
				"Dichte %.1f h: Autos %d/%d, Goobys %d/%d"
				% [stunde, verkehr.size(), v_soll, fussgaenger.size(), f_soll]
			)
		)
		return false
	return true


## Auto aus der Einfahrt auf die Wohnstraße stellen (Straßen-Reihe 7, vor
## den CC0-Häusern in Reihe 8/9) — Blick auf die Häuserzeile; Fahr-Skill
## ist nicht Testziel (Muster flow_w18_stadt_tour._fahre_vor).
func rolle_auf_die_strasse() -> bool:
	var stadt := _stadt()
	if stadt == null or stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	stadt.auto.position = stadt.karte.tile_zu_welt(Vector2i(7, 3))
	stadt.auto.rotation.y = 0.0
	stadt.auto.speed = 0.0
	return true


## Für den zweiten Abend-Schuss die Straße ENTLANG schauen (Laternenreihe
## + Lichtkegel im Bild statt nur der Häuserfront).
func rolle_ein_stueck_weiter() -> bool:
	var stadt := _stadt()
	if stadt == null or stadt.karte == null or stadt.auto == null:
		return false
	stadt.auto.position = stadt.karte.tile_zu_welt(Vector2i(7, 2))
	stadt.auto.rotation.y = PI / 2.0
	stadt.auto.speed = 0.0
	return true


func _stadt() -> CityScene:
	return aktuelle_szene() as CityScene


func _sichtbar(node: Node) -> bool:
	return node is Node3D and (node as Node3D).visible


## Nachzügler-Wache (Muster flow_w18_stadt_tour): Morgen-Ritual-Overlays
## ausklingen lassen, damit kein Scrim die Reise-Taps frisst.
func _schritte_ritual_puffer() -> Array[Dictionary]:
	return [
		{
			"name": "tagesbonus_nachzuegler",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 45.0,
			"pflicht": false,
		},
		{"name": "bonus_zu_moment", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "coachmark_nachzuegler",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "guide_nachzuegler_wegtippen",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{"name": "hud_frei_moment", "aktion": "warte", "sekunden": 2.0},
	]

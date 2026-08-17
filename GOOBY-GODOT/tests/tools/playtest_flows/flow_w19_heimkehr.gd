extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W19-Playtest — Flow „Mitbring-Momente (Heimkehr)“: die komplette
## Rückkehr-Strecke des Pakets W19/MITBRINGSEL wie ein Spieler:
## (1) Fixture „Urlaub gebucht + Gooby abholbereit“ (vacation-Slice auf
##     returnReady, Muster staging_rueckkehr aus flow_w18_reise_strand),
## (2) Stadt → Flughafen: VOR der Abholung ist GOOBY-FREE zu (Wache),
##     dann Reise-Schalter → „Abholen 🧳“ (Souvenir-Münzen kommen rein,
##     Heimkehr-Latches gestempelt) → direkt danach ist das 24-h-Fenster
##     am Ort SICHTBAR offen (Knopf aktiv + Mitbringsel-Hinweis-Zeile),
## (3) Heim: der HeimkehrMoment reiht sich beim Overlay-Dirigenten ein —
##     Reunion-Karte mit Mitbringsel-Name, Koffer+Tüte-Props neben Gooby,
##     Mitbringsel liegt GENAU EINMAL im Inventar, „Fest drücken!“ feuert
##     Konfetti und schließt die Karte (Latch: nie eine zweite Karte),
## (4) zurück zum Flughafen: exklusives Fenster-Sortiment mit „Nur 24 h“-
##     Chip (KEINE Standard-Ware ohne Abflug-Buchung), Kauf einer
##     Fenster-Ware (Münzen runter, Ware in inventory.items),
## (5) Uhr +25 h (gs.clock.pin — injizierte Uhr) → Fenster zu: Knopf
##     wieder disabled + „öffnet nur vor dem Abflug“-Hinweis.
## Format: quer 2868x1320 (Default) UND hochkant 1320x2868.
## Aufruf: tools/ci/run_playtest.sh flow_w19_heimkehr
##         tools/ci/run_playtest.sh flow_w19_heimkehr 1320x2868
##
## Staging (KEINE Spielmechanik-Änderung, öffentliche APIs): Münzen 600,
## vacation-Slice abholbereit (bookedAt vor 3 Tagen = Mitbringsel-Seed,
## returnAt knapp vorbei, pickupBy morgen), am Ende Uhr-Pin +25 h.

const STAGING_MUENZEN := 600
const ZIEL := "beach"
const TAG_MS := 86400000
const STUNDE_MS := 3600000

var _muenzen_vorher := -1
## Erwartete Mitbringsel-Item-Id (deterministisch aus Ziel + bookedAt).
var _mitbringsel_id := ""
var _mitbringsel_vorher := -1
## Fenster-Sortiment-Ids (die zwei NICHT mitgebrachten Varianten).
var _fenster_ids: Array[String] = []
var _fenster_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ritual_puffer())
	liste.append_array(_schritte_abholung())
	liste.append_array(_schritte_reunion())
	liste.append_array(_schritte_fenster_kauf())
	liste.append_array(_schritte_fenster_zu())
	return liste


## ------------------------------------ Abholung am Flughafen (returnReady)


func _schritte_abholung() -> Array[Dictionary]:
	return [
		{
			"name": "staging_abholbereit",
			"aktion": "tue",
			"funktion": staging_abholbereit,
			"erwartung": "Münzen 600 + vacation-Slice abholbereit (returnReady)",
		},
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vorfahren_flughafen",
			"aktion": "tue",
			"funktion": fahre_vor_flughafen,
			"erwartung": "Auto steht am Flughafen-Parkplatz",
		},
		{
			"name": "flughafen_betreten",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/flughafen"},
			"timeout_s": 60.0,
		},
		{"name": "terminal_ansehen", "aktion": "warte", "sekunden": 3.0},
		# VOR der Abholung: kein Heimkehr-Fenster, keine Abflug-Buchung →
		# GOOBY-FREE ist zu (Knopf disabled + „öffnet nur…“-Zeile).
		{
			"name": "gfree_vor_abholung_zu",
			"aktion": "tue",
			"funktion": gfree_ist_zu,
			"erwartung": "GOOBY-FREE vor der Abholung disabled + Standard-Hinweis",
		},
		{
			"name": "abhol_ansicht_oeffnen",
			"aktion": "tipp_name",
			"node": "Reise",
			"erwarte": {"text": "Gooby wartet am Flughafen!"},
			"timeout_s": 60.0,
		},
		{"name": "abhol_ansicht_lesen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "kasse_merken_abholung",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "abholen",
			"aktion": "tipp_text",
			"text": "Abholen",
			"erwarte": {"bedingung": muenzen_gestiegen},
			"timeout_s": 30.0,
		},
		{
			"name": "heimkehr_latch_gestempelt",
			"aktion": "tue",
			"funktion": heimkehr_latch_gestempelt,
			"erwartung": "heimkehrZiel/At/Abflug gestempelt, noch nicht gefeiert",
		},
		{
			"name": "reise_sheet_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{
			"name": "reise_sheet_zu",
			"aktion": "warte_bis",
			"weg_klasse": "ReiseApp",
			"timeout_s": 20.0,
		},
		# NACH der Abholung: das 24-h-Fenster öffnet den Stand SOFORT —
		# Knopf aktiv + Mitbringsel-Hinweis-Zeile (statt „öffnet nur…“).
		{
			"name": "gfree_fenster_offen",
			"aktion": "tue",
			"funktion": gfree_fenster_offen,
			"erwartung": "GOOBY-FREE-Knopf aktiv + Mitbringsel-Fenster-Hinweis sichtbar",
		},
		{
			"name": "inventar_merken",
			"aktion": "tue",
			"funktion": merke_mitbringsel_inventar,
			"erwartung": "Mitbringsel-Zähler vor der Reunion notiert",
		},
	]


## --------------------------------------- Reunion daheim (HeimkehrMoment)


func _schritte_reunion() -> Array[Dictionary]:
	return [
		{
			"name": "flughafen_verlassen",
			"aktion": "tipp_text",
			"text": "Raus",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "strasse_moment", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "heimfahrt",
			"aktion": "tipp_text",
			"text": "Nach Hause",
			"erwarte": {"route": "home/living"},
			"timeout_s": 180.0,
		},
		# Der Moment reiht sich beim Overlay-Dirigenten ein (Prio 5,
		# Vorlauf 0,6 s) — die Tüten-Übergabe-Karte gleitet von selbst rein.
		# Suche per NODE-NAME: HeimkehrKarte ist eine INNERE Klasse, deren
		# get_global_name() leer ist — die Klassen-Suche des Harness greift
		# dort nicht (W19-Playtest-Lehre).
		{
			"name": "reunion_karte_da",
			"aktion": "warte_bis",
			"bedingung": reunion_karte_sichtbar,
			"timeout_s": 60.0,
		},
		{"name": "reunion_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "gepaeck_props_da",
			"aktion": "tue",
			"funktion": gepaeck_props_da,
			"erwartung": "Koffer+Tüte-Props (HeimkehrGepaeck) stehen neben Gooby",
		},
		{
			"name": "mitbringsel_im_inventar",
			"aktion": "tue",
			"funktion": mitbringsel_im_inventar,
			"erwartung": "GENAU EIN Mitbringsel mehr in inventory.items",
		},
		{
			"name": "fest_druecken",
			"aktion": "tipp_text",
			"text": "Fest drücken!",
			"erwarte": {"bedingung": karte_zu_und_konfetti},
			"timeout_s": 30.0,
		},
		{"name": "konfetti_moment", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "reunion_genau_einmal",
			"aktion": "tue",
			"funktion": reunion_genau_einmal,
			"erwartung": "heimkehrGefeiert gelatcht — kein zweiter Moment",
		},
	]


## ----------------------- 24-h-Fenster: Chip + Kauf einer Fenster-Ware


func _schritte_fenster_kauf() -> Array[Dictionary]:
	return [
		{
			"name": "zurueck_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen_2", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vorfahren_flughafen_2",
			"aktion": "tue",
			"funktion": fahre_vor_flughafen,
			"erwartung": "Auto steht am Flughafen-Parkplatz",
		},
		{
			"name": "flughafen_betreten_2",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/flughafen"},
			"timeout_s": 60.0,
		},
		{"name": "terminal_ansehen_2", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "gfree_fenster_offen_2",
			"aktion": "tue",
			"funktion": gfree_fenster_offen,
			"erwartung": "Fenster nach Heimkehr weiter offen (Knopf + Hinweis)",
		},
		{
			"name": "gfree_oeffnen",
			"aktion": "tipp_name",
			"node": "GoobyFree",
			"erwarte": {"text": "Flughafenpreise"},
			"timeout_s": 60.0,
		},
		{"name": "sortiment_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "fenster_chip_da",
			"aktion": "tue",
			"funktion": fenster_chip_da,
			"erwartung": "„Nur 24 h“-Chip sichtbar, KEINE Standard-Ware ohne Buchung",
		},
		{
			"name": "kasse_und_inventar_merken",
			"aktion": "tue",
			"funktion": merke_kasse_und_fenster_inventar,
			"erwartung": "Münzstand + Fenster-Waren-Zähler notiert",
		},
		{
			"name": "fenster_ware_kaufen",
			"aktion": "tipp_pos",
			"pos_funktion": kauf_knopf_pos,
			"erwarte": {"bedingung": fenster_kauf_verbucht},
			"timeout_s": 20.0,
		},
		{"name": "einpack_moment", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "gfree_sheet_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{"name": "gfree_zu_moment", "aktion": "warte", "sekunden": 1.5},
	]


## ------------------------------ Uhr +25 h → Fenster zu (Runde komplett)


func _schritte_fenster_zu() -> Array[Dictionary]:
	return [
		{
			"name": "uhr_25h_vorspulen",
			"aktion": "tue",
			"funktion": uhr_25h_vorspulen,
			"erwartung": "injizierte Uhr (gs.clock) auf +25 h gepinnt",
		},
		{
			"name": "flughafen_verlassen_2",
			"aktion": "tipp_text",
			"text": "Raus",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "strasse_moment_2", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "vorfahren_flughafen_3",
			"aktion": "tue",
			"funktion": fahre_vor_flughafen,
			"erwartung": "Auto steht am Flughafen-Parkplatz",
		},
		{
			"name": "flughafen_betreten_3",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/flughafen"},
			"timeout_s": 60.0,
		},
		{"name": "terminal_ansehen_3", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "gfree_fenster_zu",
			"aktion": "tue",
			"funktion": gfree_ist_zu,
			"erwartung": "nach +25 h wieder disabled + „öffnet nur…“-Hinweis",
		},
	]


## ---------------------------------------------------------------- Bausteine


## Fixture „Urlaub gebucht + Gooby abholbereit“: Kasse auf 600, vacation-
## Slice direkt auf returnReady (bookedAt vor 3 Tagen ist der spätere
## Mitbringsel-Seed). Erwartete Item-Id gleich mitnotieren.
func staging_abholbereit() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("economy.coins", STAGING_MUENZEN)
	var jetzt := _now_ms()
	var abflug := jetzt - 3 * TAG_MS
	var roh: Variant = gs.get_value("vacation", {})
	var v: Dictionary = roh if roh is Dictionary else {}
	v["phase"] = "away"
	v["destId"] = ZIEL
	v["bookedAt"] = abflug
	v["returnAt"] = jetzt - 60000
	v["pickupBy"] = jetzt + TAG_MS
	v["postcards"] = 0
	gs.set_value("vacation", v)
	_mitbringsel_id = str(HeimkehrLogik.mitbringsel(ZIEL, abflug)["item_id"])
	return not _mitbringsel_id.is_empty()


func fahre_vor_flughafen() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	var park: Vector3 = stadt.karte.parkplatz_welt("flughafen")
	stadt.auto.teleport(park.x, park.z)
	# Ohne gehaltene Bremse rollt das Auto aus dem Parkradius (W18-Lehre).
	stadt.auto.set_brake(true)
	return true


## „Geschlossen“-Vertrag (Muster flow_w18_gfree_hochkant): Knopf disabled
## UND die Standard-Hinweis-Zeile („öffnet nur vor dem Abflug“) sichtbar.
func gfree_ist_zu() -> bool:
	var knopf := harness.root.find_child("GoobyFree", true, false)
	if not (knopf is Button):
		return false
	var hinweis := harness.root.find_child("GoobyFreeHinweis", true, false)
	if not (hinweis is Label):
		return false
	if not (knopf as Button).disabled or not (hinweis as Label).is_visible_in_tree():
		return false
	return (hinweis as Label).text.contains("öffnet nur vor dem Abflug")


## „Fenster offen“-Vertrag (W19): Knopf AKTIV (ohne Abflug-Buchung!) und
## die Hinweis-Zeile zeigt den Mitbringsel-Fenster-Text mit Rest-Stunden.
func gfree_fenster_offen() -> bool:
	var knopf := harness.root.find_child("GoobyFree", true, false)
	if not (knopf is Button):
		return false
	var hinweis := harness.root.find_child("GoobyFreeHinweis", true, false)
	if not (hinweis is Label):
		return false
	if (knopf as Button).disabled or not (hinweis as Label).is_visible_in_tree():
		return false
	return (hinweis as Label).text.contains("Mitbringsel-Fenster offen")


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	return true


## Abholung verbucht? Souvenir-Münzen kommen REIN (Stand steigt).
func muenzen_gestiegen() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	return int(gs.get_value("economy.coins", 0)) > _muenzen_vorher


## Abholung stempelt die Heimkehr-Latches (Ziel/Abflug/At, ungefeiert).
func heimkehr_latch_gestempelt() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var roh: Variant = gs.get_value("vacation", {})
	if not (roh is Dictionary):
		return false
	var v: Dictionary = roh
	if str(v.get("heimkehrZiel", "")) != ZIEL:
		return false
	if int(v.get("heimkehrAt", 0)) <= 0 or int(v.get("heimkehrAbflug", 0)) <= 0:
		return false
	return not bool(v.get("heimkehrGefeiert", true))


func merke_mitbringsel_inventar() -> bool:
	_mitbringsel_vorher = _inventar_zaehler(_mitbringsel_id)
	return _mitbringsel_vorher >= 0


## Die Übergabe-Karte steht sichtbar (per Node-Name — s. reunion_karte_da).
func reunion_karte_sichtbar() -> bool:
	return harness._finde_control(harness.root, "HeimkehrKarte") != null


## Koffer + Tüte stehen als kurzlebige Props im Raum neben Gooby.
func gepaeck_props_da() -> bool:
	return harness.root.find_child("HeimkehrGepaeck", true, false) != null


## Das deterministische Mitbringsel liegt GENAU EINMAL mehr im Inventar
## (feiern läuft beim ÖFFNEN der Karte — der Latch ist der Beweis).
func mitbringsel_im_inventar() -> bool:
	return _inventar_zaehler(_mitbringsel_id) == _mitbringsel_vorher + 1


## Nach „Fest drücken!“: Karte weg UND das Umarmungs-Konfetti regnet.
func karte_zu_und_konfetti() -> bool:
	if reunion_karte_sichtbar():
		return false
	return harness.root.find_child("RewardKonfetti", true, false) != null


## Genau-einmal-Latch: gefeiert, nichts steht mehr aus.
func reunion_genau_einmal() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	if not bool(gs.get_value("vacation.heimkehrGefeiert", false)):
		return false
	return not HeimkehrLogik.ausstehend(gs.state())


## Chip-Vertrag im Sheet: „Nur 24 h“ sichtbar; OHNE Abflug-Buchung darf
## KEINE Standard-Ware („Nur hier!“-Chip) im Sortiment stehen.
func fenster_chip_da() -> bool:
	if _finde_sichtbaren_text("Nur 24 h") == null:
		return false
	return _finde_sichtbaren_text("Nur hier!") == null


func merke_kasse_und_fenster_inventar() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	_fenster_ids.clear()
	for ware: Dictionary in HeimkehrLogik.fenster_sortiment(gs.state(), _now_ms()):
		_fenster_ids.append(str(ware["id"]))
	if _fenster_ids.size() != 2:
		return false
	_fenster_vorher = _fenster_summe()
	return _fenster_vorher >= 0


## Fenster-Kauf verbucht: Münzen runter UND eine Fenster-Ware mehr in
## inventory.items (die HeimkehrLogik.kaufe-Pipeline, atomar).
func fenster_kauf_verbucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0 or _fenster_vorher < 0:
		return false
	if int(gs.get_value("economy.coins", 0)) >= _muenzen_vorher:
		return false
	return _fenster_summe() == _fenster_vorher + 1


## Mitte des obersten aktiven Preis-Knopfs ("{preis} ᴳ") im Sheet.
func kauf_knopf_pos() -> Vector2:
	var sicht := harness.root.get_visible_rect()
	var beste := Vector2.ZERO
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		for kind in aktuell.get_children():
			stapel.append(kind)
		if not (aktuell is Button):
			continue
		var knopf := aktuell as Button
		if knopf.disabled or not knopf.is_visible_in_tree() or not knopf.text.contains("ᴳ"):
			continue
		var mitte := knopf.get_global_rect().get_center()
		if sicht.has_point(mitte) and (beste == Vector2.ZERO or mitte.y < beste.y):
			beste = mitte
	return beste


## Uhr-Vorspulen über die INJIZIERTE GameState-Uhr (Clock.pin) — exakt der
## Testpfad, den AGENTS.md für zeitabhängige Logik vorsieht.
func uhr_25h_vorspulen() -> bool:
	var gs := game_state()
	if gs == null or not ("clock" in gs) or gs.clock == null:
		return false
	gs.clock.pin(_now_ms() + 25 * STUNDE_MS)
	return true


## Anzahl eines Items in inventory.items (-1 ohne GameState).
func _inventar_zaehler(item_id: String) -> int:
	var gs := game_state()
	if gs == null or item_id.is_empty():
		return -1
	var items: Variant = gs.get_value("inventory.items", {})
	if not (items is Dictionary):
		return -1
	return int((items as Dictionary).get(item_id, 0))


func _fenster_summe() -> int:
	var summe := 0
	for id in _fenster_ids:
		var n := _inventar_zaehler(id)
		if n < 0:
			return -1
		summe += n
	return summe


func _now_ms() -> int:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## Sichtbares Label/Button mit Teilstring finden (Chip-Wachen).
func _finde_sichtbaren_text(text: String) -> Control:
	return harness._finde_text(harness.root, text)


## Nachzügler-Wache (Muster flow_w18_reise_strand): Tour-Karte ausklingen
## lassen, damit ihr Scrim keine HUD-Taps schluckt.
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

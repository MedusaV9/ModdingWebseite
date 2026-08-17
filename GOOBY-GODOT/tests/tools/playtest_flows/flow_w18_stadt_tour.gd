extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18-Playtest (Welle 3, Stadt-Agent) — Flow „Stadt-Rundfahrt“: erst wie
## ein Spieler daheim GOOBERANDO im IGohbie bestellen (Lieferung inklusive,
## Dev-Key `debug.gooberando_prep_s` verkürzt NUR die Wartezeit), dann in
## die Stadt: POW! betreten (W18-Audit-Check: sitzt der Teddy WIRKLICH auf
## dem Regal statt zu schweben?), Tagesangebote-Sheet öffnen, raus, weiter
## zum Wochenmarkt: die Öffnungsregel „nur samstags 8–14“ wird seit W18/4
## (Fix B1) beim Betreten GEPRÜFT — der Flow pinnt die GameState-Uhr auf
## So 10:00 (Toast „schläft aus“, keine Route) und dann Sa 10:00 (rein)
## und sieht sich den Eigenstand-Tab an.
## Aufruf: tools/ci/run_playtest.sh flow_w18_stadt_tour
##
## Staging (KEINE Spielmechanik-Änderung): debug.gooberando_prep_s = 4,
## damit der Liefer-Loop in Playtest-Zeit passt (sonst 90–300 s Küche).

## Toleranzen für den Teddy-Regal-Check (Soll laut pow.gd: -4.19/1.14/-3.96).
const TEDDY_SOLL := Vector3(-4.19, 1.14, -3.96)
const TEDDY_TOLERANZ := 0.25

## Wanduhr-Zeiten für die B1-Wache: Sa 2026-01-03 / So 2026-01-04, je 10:00.
const SAMSTAG_10 := {"year": 2026, "month": 1, "day": 3, "hour": 10, "minute": 0, "second": 0}
const SONNTAG_10 := {"year": 2026, "month": 1, "day": 4, "hour": 10, "minute": 0, "second": 0}

## Münzstand vor einem Kauf (kauf_verbucht vergleicht dagegen).
var _muenzen_vorher := -1

## Scrollstand des Telefon-Inhalts vor der Wisch-Wache (B2).
var _scroll_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ritual_puffer())
	liste.append_array(_schritte_gooberando())
	liste.append_array(_schritte_pow())
	liste.append_array(_schritte_wochenmarkt())
	return liste


## ---------------------------------------------- GOOBERANDO (IGohbie, daheim)


func _schritte_gooberando() -> Array[Dictionary]:
	return [
		{
			"name": "lieferzeit_verkuerzen",
			"aktion": "tue",
			"funktion": staging_lieferzeit,
			"erwartung": "debug.gooberando_prep_s gesetzt",
		},
		{
			"name": "igohbie_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnIgohbie",
			"erwarte": {"klasse": "PhoneShell"},
			"timeout_s": 60.0,
		},
		{"name": "app_grid_ansehen", "aktion": "warte", "sekunden": 2.0},
		# Kachel-Knopf ist namenlos (Icon-Button) — Position über die
		# benannte Kachel-VBox „KachelGooberando“ ermitteln.
		{
			"name": "gooberando_app_oeffnen",
			"aktion": "tipp_pos",
			"pos_funktion": gooberando_kachel_pos,
			"erwarte": {"text": "Wo soll’s heute herkommen?"},
			"timeout_s": 30.0,
		},
		{
			"name": "restaurant_waehlen",
			"aktion": "tipp_text",
			"text": "Möhrenschmiede",
			"erwarte": {"text": "Bestellen"},
			"timeout_s": 30.0,
		},
		# W18/4 B2-Wache (Fix statt Workaround): der Bestellen-CTA ist im
		# PhoneShell-Fuß GEPINNT und liegt OHNE Scrollen komplett im Canvas
		# (vorher ~2 Viewports unter der Falz; der programmatische
		# scrolle_menue_ans_ende-Workaround ist raus).
		{
			"name": "cta_im_bild",
			"aktion": "tue",
			"funktion": pruefe_bestellen_im_bild,
			"erwartung": "Bestellen-CTA ohne Scrollen komplett im Canvas",
		},
		# W18/4 B2-Wache 2: ein MAUS-Wisch scrollt den Telefon-Inhalt jetzt
		# (eigener Pan im Scroll-gui_input, F6-Arcade-Muster) — oder der
		# Inhalt passt komplett (dann gibt es nichts zu scrollen, geloggt).
		# Die Wische sind zugleich Spieler-Staging: der Quer-Scroll ist mit
		# gepinntem Fuß kurz (~140 px bei ~470 px Überlauf, Lauf g5_stadt_v2),
		# drei lange Züge holen das LISTEN-ENDE über die Falz — dort ist das
		# letzte Gericht („Melone vom Schleifstein“) sicher komplett im Bild.
		{
			"name": "wisch_merken",
			"aktion": "tue",
			"funktion": merke_menue_scroll,
			"erwartung": "Scrollstand notiert",
		},
		{
			"name": "menue_wisch",
			"aktion": "wisch",
			"von_funktion": menue_wisch_start,
			"nach_funktion": menue_wisch_ende,
			"dauer_s": 0.6,
		},
		{
			"name": "wisch_scrollt",
			"aktion": "tue",
			"funktion": wisch_hat_gescrollt,
			"erwartung": "Maus-Wisch bewegt den Telefon-Scroll (oder Inhalt passt)",
		},
		{
			"name": "menue_wisch_2",
			"aktion": "wisch",
			"von_funktion": menue_wisch_start,
			"nach_funktion": menue_wisch_ende,
			"dauer_s": 0.6,
		},
		{
			"name": "menue_wisch_3",
			"aktion": "wisch",
			"von_funktion": menue_wisch_start,
			"nach_funktion": menue_wisch_ende,
			"dauer_s": 0.6,
		},
		{
			"name": "gericht_im_bild",
			"aktion": "tue",
			"funktion": _gericht_im_bild,
			"erwartung": "„Melone“-Knopf nach den Wischen im Scroll-Ausschnitt",
			"pflicht": false,
		},
		{
			"name": "gericht_in_den_korb",
			"aktion": "tipp_text",
			"text": "Melone",
			"erwarte": {"text": "Im Korb"},
			"timeout_s": 20.0,
		},
		{
			"name": "korb_sonde",
			"aktion": "tue",
			"funktion": korb_sonde,
			"erwartung": "Warenkorb hat 1 Gericht (Tipp hat registriert)",
			"pflicht": false,
		},
		{"name": "korb_zeile_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "kasse_merken_gooberando",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "bestellung_abschicken",
			"aktion": "tipp_text",
			"text": "Bestellen",
			"erwarte": {"bedingung": kauf_verbucht},
			"timeout_s": 20.0,
		},
		{"name": "countdown_karte_ansehen", "aktion": "warte", "sekunden": 3.0},
		# prep 4 s + Fahrer-Sim-Fahrzeit + 1-s-Tick — großzügig warten.
		{
			"name": "lieferung_abwarten",
			"aktion": "tipp_text",
			"text": "Tür öffnen",
			"timeout_s": 120.0,
		},
		{
			"name": "trinkgeld_geben",
			"aktion": "tipp_text",
			"text": "Trinkgeld",
			"timeout_s": 30.0,
		},
		{"name": "uebergabe_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "igohbie_zurueck_aufs_grid",
			"aktion": "tipp_text",
			"text": "Zurück",
			"timeout_s": 20.0,
		},
		{
			"name": "igohbie_schliessen",
			"aktion": "tipp_text",
			"text": "Zurück",
			"erwarte": {"weg_klasse": "PhoneShell"},
			"timeout_s": 20.0,
		},
	]


## ------------------------------------------------------------- POW! (Stadt)


func _schritte_pow() -> Array[Dictionary]:
	return [
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vorfahren_pow",
			"aktion": "tue",
			"funktion": fahre_vor_pow,
			"erwartung": "Auto steht am POW!-Parkplatz",
		},
		# KEINE Wartezeit vor dem Tipp: wegen des Kriech-Minimums (1.2 m/s)
		# rollt das Auto in ~10 s durchs Prompt-Fenster — sofort tippen.
		{
			"name": "pow_park_sonde",
			"aktion": "tue",
			"funktion": pow_position_sonde,
			"erwartung": "Auto binnen 7 m am POW-Parktrigger (Log: Distanz)",
			"pflicht": false,
		},
		# Befund B12: der POW-Bordstein-Trigger steckt in einem Kollider
		# (16-m-Punch im ersten Physik-Tick, pow-sonde-Lauf) — der Prompt
		# ist per Auto praktisch nicht fangbar. Kurze Sonde dokumentiert
		# das, dann Force-Enter (identisch zur B7-Umgehung am Flughafen),
		# damit das Laden-Innere (Teddy!) trotzdem geprueft wird.
		{
			"name": "pow_betreten_prompt_sonde",
			"aktion": "tipp_falls_da",
			"text": "Betreten",
			"timeout_s": 12.0,
			"pflicht": false,
		},
		{
			"name": "pow_betreten_force",
			"aktion": "tue",
			"funktion": betrete_pow_direkt,
			"erwartung": "Force-Enter POW (B12-Umgehung)",
		},
		{
			"name": "pow_betreten",
			"aktion": "warte_bis",
			"route": "city/ort/pow",
			"timeout_s": 60.0,
		},
		{"name": "pow_laden_ansehen", "aktion": "warte", "sekunden": 4.0},
		# W18-Audit-Nachprüfung: Teddy AUF der Regal-Oberkante (y≈1,14),
		# nicht mehr schwebend davor.
		{
			"name": "teddy_regal_check",
			"aktion": "tue",
			"funktion": teddy_im_regal,
			"erwartung": "bear.glb sitzt bei %s (±%.2f)" % [str(TEDDY_SOLL), TEDDY_TOLERANZ],
		},
		{
			"name": "pow_bubble_zeigen",
			"aktion": "tipp_name",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "pow_bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "pow_bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{"name": "pow_bubble_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "pow_bubble_weiter2",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{
			"name": "pow_angebote_waehlen",
			"aktion": "tipp_text",
			"text": "Was ist heute im Angebot?",
			"timeout_s": 60.0,
		},
		{"name": "pow_antwort_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "pow_antwort_zeigen",
			"aktion": "tipp_name",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "pow_antwort_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "pow_antwort_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{
			"name": "pow_sheet_offen",
			"aktion": "warte_bis",
			"klasse": "PowSheet",
			"timeout_s": 30.0,
		},
		{"name": "pow_angebote_ansehen", "aktion": "warte", "sekunden": 2.0},
		# Sheet zu per Backdrop-Tipp (Lauf-1-Lehre: Wisch im Inhalt scrollt
		# nur, und der Sheet-Scrim schluckt sonst den Raus-Tipp).
		{
			"name": "pow_sheet_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{
			"name": "pow_sheet_weg",
			"aktion": "warte_bis",
			"weg_klasse": "PowSheet",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "pow_nach_sheet", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "pow_verlassen",
			"aktion": "tipp_text",
			"text": "Raus",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
	]


## ------------------------------------------------------ Wochenmarkt (Stadt)


func _schritte_wochenmarkt() -> Array[Dictionary]:
	return [
		{"name": "wieder_auf_der_strasse", "aktion": "warte", "sekunden": 4.0},
		{
			"name": "vorfahren_wochenmarkt",
			"aktion": "tue",
			"funktion": fahre_vor_wochenmarkt,
			"erwartung": "Auto steht am Wochenmarkt-Parkplatz",
		},
		# W18/4 B1-Wache (Fix statt Sonde): das Betreten-Gate ruft jetzt
		# OrtKatalog.ist_offen mit der INJIZIERTEN GameState-Uhr. Erst auf
		# So 10:00 pinnen: „Betreten“ blockt mit dem nur_samstag-Toast,
		# die Route bleibt city. Dann auf Sa 10:00 umpinnen: rein.
		{
			"name": "uhr_sonntag_pinnen",
			"aktion": "tue",
			"funktion": pinne_uhr_sonntag,
			"erwartung": "GameState-Uhr auf So 10:00 (lokal) gepinnt",
		},
		{
			"name": "wochenmarkt_sonntags_zu",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"text": "schläft aus"},
			"timeout_s": 30.0,
		},
		{
			"name": "markt_blieb_zu_check",
			"aktion": "tue",
			"funktion": markt_blieb_zu,
			"erwartung": "So 10:00: Route bleibt city, Gate meldet zu",
		},
		{"name": "geschlossen_toast_lesen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "uhr_samstag_pinnen",
			"aktion": "tue",
			"funktion": pinne_uhr_samstag,
			"erwartung": "GameState-Uhr auf Sa 10:00 (lokal) gepinnt",
		},
		{
			"name": "wochenmarkt_betreten",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/wochenmarkt"},
			"timeout_s": 120.0,
		},
		{
			"name": "uhr_wieder_frei",
			"aktion": "tue",
			"funktion": entpinne_uhr,
			"erwartung": "GameState-Uhr wieder auf Systemzeit",
		},
		{"name": "markt_ansehen", "aktion": "warte", "sekunden": 4.0},
		{
			"name": "markt_bubble_zeigen",
			"aktion": "tipp_name",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "markt_bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "markt_bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{"name": "markt_bubble_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "markt_bubble_weiter2",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{
			"name": "markt_verkaufen_waehlen",
			"aktion": "tipp_text",
			"text": "Ich möchte Ernte verkaufen",
			"timeout_s": 60.0,
		},
		{"name": "markt_antwort_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "markt_antwort_zeigen",
			"aktion": "tipp_name",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "markt_antwort_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "markt_antwort_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{
			"name": "markt_sheet_offen",
			"aktion": "warte_bis",
			"klasse": "MarktSheet",
			"timeout_s": 30.0,
		},
		{"name": "markt_ankauf_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "eigenstand_tab_oeffnen",
			"aktion": "tipp_text",
			"text": "Mein Stand",
			"erwarte": {"klasse": "MarktStandSheet"},
			"timeout_s": 30.0,
		},
		{"name": "eigenstand_ansehen", "aktion": "warte", "sekunden": 3.0},
		# Sheet zu per Backdrop-Tipp (Lauf-1-Lehre: der Sheet-Scrim schluckt
		# sonst den Raus-Tipp — der Knopf ist sichtbar, aber nicht tippbar).
		{
			"name": "markt_sheet_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{
			"name": "markt_sheet_weg",
			"aktion": "warte_bis",
			"weg_klasse": "MarktSheet",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "markt_abschluss", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "markt_verlassen",
			"aktion": "tipp_text",
			"text": "Raus",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "tour_abschluss", "aktion": "warte", "sekunden": 3.0},
	]


## ---------------------------------------------------------------- Bausteine


func staging_lieferzeit() -> bool:
	var settings := harness.root.get_node_or_null("/root/AppSettings")
	if settings == null or not settings.has_method("set_setting"):
		return false
	settings.set_setting("debug.gooberando_prep_s", 4)
	return true


## Mitte des Kachel-KNOPFS (erstes Kind der benannten Kachel-VBox) — die
## App-Beschriftung ist ein Label UNTER dem Knopf, Text-Tipp träfe daneben.
func gooberando_kachel_pos() -> Vector2:
	var kachel := harness.root.find_child("KachelGooberando", true, false)
	if kachel == null or kachel.get_child_count() == 0:
		return Vector2.ZERO
	var knopf: Node = kachel.get_child(0)
	if knopf is Control:
		return (knopf as Control).get_global_rect().get_center()
	return Vector2.ZERO


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	return true


func kauf_verbucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	return int(gs.get_value("economy.coins", 0)) < _muenzen_vorher


func fahre_vor_pow() -> bool:
	# pow-sonde-Lehren (w18s_powsonde): (a) der Bordstein-Trigger (47,-10)
	# steckt in einem Kollider — 16-m-Punch im ersten Physik-Tick; (b) die
	# Bremse hält NIE ganz (car_feel BRAKE_MIN_SPEED 1.2 = Kriech-Minimum
	# by design) — der Prompt ist ein ~10-s-ROLLFENSTER. Also am Fahrbahn-
	# rand KURZ VOR dem Laden aufsetzen (Kriechrichtung -z, Heading 0)
	# und sofort tippen.
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	var park: Vector3 = stadt.karte.parkplatz_welt("pow")
	stadt.auto.teleport(park.x + 4.0, park.z + 5.0, 0.0)
	stadt.auto.set_brake(true)
	print("[FLOW-DIAG] teleport pow-rand auto=", stadt.auto.position)
	return true


func fahre_vor_wochenmarkt() -> bool:
	return _fahre_vor("wochenmarkt")


## Auto direkt an den Ziel-Parkplatz stellen (Fahr-Skill ist nicht
## Testziel). WICHTIG: das Auto ist ein Auto-Runner (Gas ist immer an) —
## ohne gehaltene BREMSE rollt es nach dem Teleport sofort aus dem
## 7-m-Parkradius und der Betreten-Prompt verschwindet (Lauf-1-Lehre).
## extra_zur_strasse: Meter ZUSÄTZLICH Richtung Straße (Spieler-Halt am
## Fahrbahnrand statt exakt auf dem Bordstein-Trigger-Punkt).
func _fahre_vor(ort_id: String, extra_zur_strasse := 0.0) -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	var park: Vector3 = stadt.karte.parkplatz_welt(ort_id)
	var ziel := park
	if extra_zur_strasse > 0.0:
		var eintrag: Dictionary = stadt.karte.ort(ort_id)
		var tiles: Array = eintrag.get("tiles", [])
		if not tiles.is_empty():
			var t: Array = tiles[0]
			var mitte: Vector3 = stadt.karte.tile_zu_welt(Vector2i(int(t[0]), int(t[1])))
			ziel = park + (park - mitte).normalized() * extra_zur_strasse
	stadt.auto.teleport(ziel.x, ziel.z)
	stadt.auto.set_brake(true)
	print("[FLOW-DIAG] teleport ", ort_id, " ziel=", ziel, " auto=", stadt.auto.position)
	return true


## B12-Umgehung: ruft die Prompt-Aktion der CityScene direkt auf — exakt
## der Codepfad, den der (unfangbare) Betreten-Knopf ausloest. Idempotent
## (Lauf g5_stadt_v2): trifft die Prompt-Sonde davor DOCH (der Tap ist
## fangbar, nur unzuverlässig), reist der Router schon nach pow — dann ist
## nichts zu erzwingen, sonst scheiterte der Force am „Router busy“.
func betrete_pow_direkt() -> bool:
	var router := harness.root.get_node_or_null("/root/SceneRouter")
	if router != null and str(router.get_current_target()) == "city/ort/pow":
		print("[FLOW-DIAG] pow-force: Router reist bereits — Prompt-Tap hat getroffen")
		return true
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	(szene as CityScene)._on_betreten("pow")
	return true


## Lauf-2-Diagnose (POW): steht das Auto 3 s nach Teleport+Bremse noch im
## 7-m-Prompt-Radius? Loggt Ziel, Ist-Position und Distanz für den Report.
func pow_position_sonde() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	var park: Vector3 = stadt.karte.parkplatz_welt("pow")
	var pos: Vector3 = stadt.auto.position
	var d := Vector2(pos.x, pos.z).distance_to(Vector2(park.x, park.z))
	print("[FLOW-DIAG] pow-sonde park=", park, " auto=", pos, " distanz=", d)
	return d <= 7.0


## Gooberando-App im Baum finden (fuer Scroll-/Korb-Sonden).
func _finde_gooberando() -> GooberandoApp:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is GooberandoApp:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


## Warenkorb-Sonde (B2): hat der Gericht-Tipp registriert? (Der Harness-
## Text-Check "Im Korb" prueft nur Existenz, nicht Sichtbarkeit.)
func korb_sonde() -> bool:
	var app := _finde_gooberando()
	if app == null:
		return false
	var korb: Variant = app.get("_warenkorb")
	var n := (korb as Array).size() if korb is Array else -1
	print("[FLOW-DIAG] gooberando warenkorb n=", n)
	return n >= 1


## W18/4 B2-Wache: der gepinnte Bestellen-CTA liegt OHNE Scrollen komplett
## im Canvas (vorher ~2 Viewports unter der Falz der App-Scrollliste).
func pruefe_bestellen_im_bild() -> bool:
	var app := _finde_gooberando()
	if app == null:
		print("[FLOW-DIAG] cta-check: GooberandoApp fehlt")
		return false
	var knopf: Variant = app.get("_kaufen_knopf")
	if not (knopf is Control) or not (knopf as Control).is_visible_in_tree():
		print("[FLOW-DIAG] cta-check: Bestellen-Knopf fehlt/unsichtbar")
		return false
	var sicht: Rect2 = harness.root.get_visible_rect()
	var rect := (knopf as Control).get_global_rect()
	var drin: bool = sicht.grow(2.0).encloses(rect)
	print("[FLOW-DIAG] bestellen rect=", rect, " canvas=", sicht, " drin=", drin)
	return drin


## Telefon-Inhalts-Scroll der PhoneShell (Name aus _baue_geraet).
func _telefon_scroll() -> ScrollContainer:
	return harness.root.find_child("InhaltScroll", true, false) as ScrollContainer


func merke_menue_scroll() -> bool:
	var scroll := _telefon_scroll()
	if scroll == null:
		return false
	_scroll_vorher = scroll.scroll_vertical
	return true


## Wisch-Start: unteres Drittel des Telefon-Scrolls (über den PASS-Knöpfen).
func menue_wisch_start() -> Vector2:
	var scroll := _telefon_scroll()
	if scroll == null:
		return harness.root.get_visible_rect().size * 0.5
	var rect := scroll.get_global_rect()
	return rect.get_center() + Vector2(0.0, rect.size.y * 0.3)


## Wisch-Ende WEIT über dem Scroll (fast Canvas-Oberkante): der Quer-Scroll
## ist mit gepinntem Fuß nur ~140 px hoch — ein Zug innerhalb des Rects
## bewegte nur ~80 px von ~470 px Überlauf. Der Fokus-Grab der GUI hält die
## Geste auch außerhalb des Scroll-Rects am Scroll (Maus-Capture ab Press).
func menue_wisch_ende() -> Vector2:
	var scroll := _telefon_scroll()
	if scroll == null:
		return harness.root.get_visible_rect().size * 0.5
	var rect := scroll.get_global_rect()
	return Vector2(rect.get_center().x, 30.0)


## Staging-Diagnose vor dem Gericht-Tipp: liegt der „Melone“-Knopf (letztes
## Gericht der Möhrenschmiede) nach den Wischen wirklich im sichtbaren
## Scroll-Ausschnitt? pflicht:false — liefert die Rechtecke als Befund-
## Futter, falls der tipp_text danach doch ins Leere geht.
func _gericht_im_bild() -> bool:
	var scroll := _telefon_scroll()
	if scroll == null:
		return false
	var knopf: Button = null
	for kandidat in harness.root.find_children("*", "Button", true, false):
		var b := kandidat as Button
		if b != null and b.is_visible_in_tree() and b.text.begins_with("Melone"):
			knopf = b
			break
	if knopf == null:
		print("[FLOW-DIAG] gericht_im_bild: Melone-Knopf fehlt")
		return false
	var sicht := scroll.get_global_rect()
	var rect := knopf.get_global_rect()
	var drin := sicht.grow(2.0).encloses(rect)
	print("[FLOW-DIAG] gericht rect=", rect, " scroll=", sicht, " drin=", drin)
	return drin


## W18/4 B2-Wache: der Maus-Wisch hat den Telefon-Scroll bewegt — ODER der
## Inhalt passt komplett in den Scroll (nichts zu scrollen; ehrlich geloggt).
func wisch_hat_gescrollt() -> bool:
	var scroll := _telefon_scroll()
	if scroll == null or _scroll_vorher < 0:
		return false
	var balken := scroll.get_v_scroll_bar()
	var ueberlauf := balken.max_value - balken.page
	print(
		"[FLOW-DIAG] wisch scroll vorher=",
		_scroll_vorher,
		" nachher=",
		scroll.scroll_vertical,
		" ueberlauf=",
		ueberlauf
	)
	if ueberlauf <= 0.0:
		return true
	return scroll.scroll_vertical != _scroll_vorher


## Teddy-Nachprüfung (W18-Audit): bear-Prop existiert und sitzt auf der
## Regal-Oberkante (pow.gd-Soll ±Toleranz) statt in der Luft zu schweben.
func teddy_im_regal() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var teddy := _finde_node3d_mit_namen(szene, "bear")
	if teddy == null:
		return false
	return teddy.position.distance_to(TEDDY_SOLL) <= TEDDY_TOLERANZ


## Epoch-ms, deren LOKALE Lesart (Uhr + Zeitzonen-Bias, exakt wie das
## Betreten-Gate in city_scene.ort_offen_jetzt) auf das Wanduhr-Dict fällt —
## deterministisch in jeder VM-Zeitzone.
func _lokale_ms(wanduhr: Dictionary) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return (int(Time.get_unix_time_from_datetime_dict(wanduhr)) - bias * 60) * 1000


func _pinne_uhr(wanduhr: Dictionary) -> bool:
	var gs := game_state()
	if gs == null or not ("clock" in gs) or gs.clock == null:
		return false
	gs.clock.pin(_lokale_ms(wanduhr))
	return true


func pinne_uhr_sonntag() -> bool:
	return _pinne_uhr(SONNTAG_10)


func pinne_uhr_samstag() -> bool:
	return _pinne_uhr(SAMSTAG_10)


func entpinne_uhr() -> bool:
	var gs := game_state()
	if gs == null or not ("clock" in gs) or gs.clock == null:
		return false
	gs.clock.unpin()
	return true


## B1-Wache: nach dem Sonntags-Tipp stehen wir NICHT im Markt (Route noch
## city) und das Gate meldet den Markt weiterhin zu.
func markt_blieb_zu() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		print("[FLOW-DIAG] markt-zu: Szene ist nicht CityScene: ", szene)
		return false
	var offen: bool = (szene as CityScene).ort_offen_jetzt("wochenmarkt")
	print("[FLOW-DIAG] markt-zu: route=city, gate offen=", offen)
	return not offen


func _finde_node3d_mit_namen(wurzel: Node, teil: String) -> Node3D:
	var nadel := teil.to_lower()
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Node3D and String(aktuell.name).to_lower().contains(nadel):
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


## Nachzügler-Wache: die Erste-Viertelstunde-Tour-Karte (OnboardingGuide)
## kehrt NACH der Morgen-Ritual-Sequenz zurück und blockiert mit ihrem
## Scrim alle HUD-Taps — erst ausklingen lassen, dann (falls da) das X.
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

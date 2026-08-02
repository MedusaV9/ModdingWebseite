extends "res://tests/tools/playtest_flows/flow_basis.gd"
## PT-4 Flow (b) „IGohbie-Telefon-Tour" (G7-P52-Verifikation): Telefon über
## den HUD-Knopf öffnen, JEDE App antippen (Taxi, Guber, GOOBERANDO,
## Freunde, GoobyPal, InstantGooby) und wieder zurück (HomeBalken UND
## Links-Wisch-Geste), die GESPERRTE Kamera prüfen (User-Befund 1.8.:
## „dunkler Blob" — jetzt blasses Icon + Schloss-Badge + POW-Hinweis-Toast)
## und das Telefon per Runterwischen schließen (neue Geste aus P52).
## Aufruf: tools/ci/run_playtest.sh flow_pt4_telefon

## Gesperrte Kachel: mindestens so viel Alpha muss das Icon behalten
## (P52: GESPERRT_ALPHA = 0.55 statt dunklem Multiplikations-Modulate).
const MIN_GESPERRT_ALPHA := 0.4


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "telefon_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnIgohbie",
					"erwarte": {"klasse": "PhoneShell"},
					"timeout_s": 60.0,
				},
				{"name": "app_grid_ansehen", "aktion": "warte", "sekunden": 2.5},
				{
					"name": "grid_kacheln_vollstaendig",
					"aktion": "tue",
					"funktion": grid_vollstaendig,
					"erwartung": "alle 7 App-Kacheln sichtbar (Taxi…Instant)",
				},
				{
					"name": "kamera_kachel_kein_blob",
					"aktion": "tue",
					"funktion": kamera_kachel_blass_mit_schloss,
					"erwartung": "gesperrte Kamera = blasses Icon + Schloss (kein Dunkel-Blob)",
				},
				{
					"name": "kamera_gesperrt_toast",
					"aktion": "tipp_name",
					"node": "KachelKamera",
					"erwarte": {"text": "POW"},
					"timeout_s": 20.0,
					"pflicht": false,
				},
				{
					"name": "app_taxi_oeffnen",
					"aktion": "tipp_name",
					"node": "KachelTaxi",
					"erwarte": {"bedingung": app_offen.bind("taxi")},
					"timeout_s": 30.0,
				},
				{"name": "app_taxi_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "zurueck_per_links_wisch",
					"aktion": "wisch",
					"von_funktion": geraet_links_pos,
					"nach_funktion": geraet_rechts_pos,
					"dauer_s": 0.5,
					"erwarte": {"bedingung": app_offen.bind("")},
					"timeout_s": 20.0,
				},
				{
					"name": "app_guber_oeffnen",
					"aktion": "tipp_name",
					"node": "KachelGuber",
					"erwarte": {"bedingung": app_offen.bind("guber")},
					"timeout_s": 30.0,
				},
				{"name": "app_guber_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "zurueck_home_balken_1",
					"aktion": "tipp_name",
					"node": "HomeBalken",
					"erwarte": {"bedingung": app_offen.bind("")},
					"timeout_s": 20.0,
				},
				{
					"name": "app_gooberando_oeffnen",
					"aktion": "tipp_name",
					"node": "KachelGooberando",
					"erwarte": {"bedingung": app_offen.bind("gooberando")},
					"timeout_s": 30.0,
				},
				{"name": "app_gooberando_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "zurueck_home_balken_2",
					"aktion": "tipp_name",
					"node": "HomeBalken",
					"erwarte": {"bedingung": app_offen.bind("")},
					"timeout_s": 20.0,
				},
				{
					"name": "app_freunde_oeffnen",
					"aktion": "tipp_name",
					"node": "KachelFreunde",
					"erwarte": {"bedingung": app_offen.bind("freunde")},
					"timeout_s": 30.0,
				},
				{"name": "app_freunde_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "zurueck_home_balken_3",
					"aktion": "tipp_name",
					"node": "HomeBalken",
					"erwarte": {"bedingung": app_offen.bind("")},
					"timeout_s": 20.0,
				},
				{
					"name": "app_goobypal_oeffnen",
					"aktion": "tipp_name",
					"node": "KachelGoobypal",
					"erwarte": {"bedingung": app_offen.bind("goobypal")},
					"timeout_s": 30.0,
				},
				{"name": "app_goobypal_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "zurueck_home_balken_4",
					"aktion": "tipp_name",
					"node": "HomeBalken",
					"erwarte": {"bedingung": app_offen.bind("")},
					"timeout_s": 20.0,
				},
				{
					"name": "app_instant_oeffnen",
					"aktion": "tipp_name",
					"node": "KachelInstant",
					"erwarte": {"bedingung": app_offen.bind("instant")},
					"timeout_s": 30.0,
				},
				{"name": "app_instant_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "zurueck_home_balken_5",
					"aktion": "tipp_name",
					"node": "HomeBalken",
					"erwarte": {"bedingung": app_offen.bind("")},
					"timeout_s": 20.0,
				},
				{
					"name": "telefon_runterwisch_schliesst",
					"aktion": "wisch",
					"von_funktion": geraet_mitte_oben_pos,
					"nach_funktion": geraet_unten_pos,
					"dauer_s": 0.5,
					"erwarte": {"weg_klasse": "PhoneShell"},
					"timeout_s": 20.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Die PhoneShell im Baum (null = Telefon zu).
func telefon() -> Control:
	var shell := harness.root.find_child("PhoneShell", true, false) as Control
	if shell != null and shell.is_visible_in_tree():
		return shell
	return null


## Ist gerade App `app_id` offen ("" = Grid)?
func app_offen(app_id: String) -> bool:
	var shell := telefon()
	return shell != null and str(shell.get("aktive_app")) == app_id


## Alle 7 Kacheln aus der Registry sichtbar im Grid?
func grid_vollstaendig() -> bool:
	for app_id: String in [
		"Taxi", "Guber", "Gooberando", "Kamera", "Freunde", "Goobypal", "Instant"
	]:
		var kachel := harness.root.find_child("Kachel%s" % app_id, true, false) as Control
		if kachel == null or not kachel.is_visible_in_tree():
			print("[PT4] Kachel fehlt/unsichtbar: Kachel%s" % app_id)
			return false
	return true


## Gesperrte Kamera-Kachel: Knopf bleibt hell (nur Alpha), Schloss-Badge da.
func kamera_kachel_blass_mit_schloss() -> bool:
	var kachel := harness.root.find_child("KachelKamera", true, false) as Control
	if kachel == null:
		return false
	var knopf: Button = null
	for kind in kachel.get_children():
		if kind is Button:
			knopf = kind
			break
	if knopf == null:
		return false
	var farbe := knopf.self_modulate
	var badge := kachel.find_child("SchlossBadge", true, false)
	print(
		(
			"[PT4] Kamera-Kachel self_modulate=%s badge=%s"
			% [str(farbe), "ja" if badge != null else "NEIN"]
		)
	)
	var hell := farbe.r > 0.9 and farbe.g > 0.9 and farbe.b > 0.9
	return hell and farbe.a >= MIN_GESPERRT_ALPHA and badge != null


## Wisch-Startpunkte relativ zum Telefon-Gerät (Canvas-Koordinaten).
func geraet_rect() -> Rect2:
	var geraet := harness.root.find_child("Geraet", true, false) as Control
	if geraet == null:
		var canvas := harness.root.get_visible_rect().size
		return Rect2(canvas * 0.3, canvas * 0.4)
	return geraet.get_global_rect()


func geraet_links_pos() -> Vector2:
	var rect := geraet_rect()
	return Vector2(rect.position.x + 14.0, rect.get_center().y)


func geraet_rechts_pos() -> Vector2:
	var rect := geraet_rect()
	return Vector2(rect.position.x + rect.size.x * 0.7, rect.get_center().y)


func geraet_mitte_oben_pos() -> Vector2:
	# Start in der LEEREN Fläche unterm App-Grid (VBox = PASS, bubbelt zum
	# Geraet, das den Maus-Fokus hält): Status-Zeile (ProgressBar) und
	# App-Kacheln (Buttons) sind STOP-Filter und würden den Zug schlucken —
	# genau daran scheiterte der erste Lauf (Start 18 % = GOOBERANDO-Kachel).
	var rect := geraet_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.62)


func geraet_unten_pos() -> Vector2:
	# Ziel UNTER dem Gerät: der Maus-Fokus bleibt beim Geraet, also zählt
	# der ganze Weg (> geste_schwelle() = 90 ×f) — egal was drunterliegt.
	var rect := geraet_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 1.05)

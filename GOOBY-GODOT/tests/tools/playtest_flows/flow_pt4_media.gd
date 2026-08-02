extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## PT-4 Flow „Media": RADIO + GOB.TY (Kino) im Wohnzimmer — beide Geräte
## stehen im Start-Layout (radio auf dem Regal vorne links, televisionModern
## am TV-Schrank). Im Hochformat liegt das Radio ausserhalb der Follow-
## Kamera → erst Kamera-Schwenk (Ein-Finger-Drag = Boden-Pan), dann
## antippen. Radio: Sheet öffnet als PanelSheet (W14-Einheitslook) →
## HUD weicht (P50), Dim liegt dahinter (P53), LIKE-KNOPF KOMPLETT IM
## CANVAS (P53-Fix des FB3-Altbefunds „Like läuft aus dem Canvas" —
## darum läuft dieser Flow im HOCHFORMAT 1320x2868), Einschalten →
## Nächster → Gefällt mir (Like landet im Save) → RUNTERWISCHEN schließt
## (P53-Geste). GOB.TY: Fernseher an (Bildschirm + Aus-Knopf + Blase ohne
## Wort-Abriss, P51) → Zappen → Ausschalten. GESCHICHTEN: das Bett liegt
## im Start-Lager (Erste-Male-Bauquest) — der Flow ERFÜLLT die Bauquest
## (Baumodus → Geist auf freie Zellen → Platzieren → Fertig) und öffnet
## dann am Bett die Bettzeit-Karte → „Gute-Nacht-Geschichte" → Goobys
## Bücherregal → Runterwischen schließt (P53 auch hier). Das BUCH-ÖFFNEN
## fehlt bewusst: es crasht das Spiel (Signal 11, s. flow_pt4_geschichten
## als dedizierten Repro) — dieser Flow bleibt dadurch grün wiederholbar.
## Aufruf: tools/ci/run_playtest.sh flow_pt4_media 1320x2868


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(
		[
			# ── RADIO (Regal VORNE LINKS, Zelle 0,8 → Welt ~(0.25, 4.25)).
			# HOCHFORMAT-FALLE (Lauf 1): die Follow-Kamera zeigt nur
			# ~3,6 m Sichtbreite (MIN_SICHTBREITE_HOCHKANT) um Gooby —
			# das Radio lag LINKS AUSSERHALB, tipp_3d ging ins Leere.
			# Wie ein Spieler: Ein-Finger-Drag schwenkt die Kamera
			# (Boden-Pan, HomeCameraRig). Lauf 3 zeigte: EIN Wisch reicht
			# nur, wenn Gooby zufällig nah steht (~2 m Pan-Weg pro Wisch).
			# Darum ZWEI Eck-Wische — der Pivot CLAMPT an die Raumgrenze
			# (0.8, 3.7) = vordere linke Ecke, egal wo Gooby wandert; das
			# Radio (0.25, 4.25) liegt dann sicher im Bild. Danach ZÜGIG
			# tippen: nach MANUAL_HOLD_S = 2,5 s folgt die Kamera wieder
			# Gooby und das Radio rutscht wieder raus.
			{
				"name": "kamera_zum_radio_1",
				"aktion": "wisch",
				"von_rel": Vector2(0.25, 0.66),
				"nach_rel": Vector2(0.85, 0.45),
				"dauer_s": 0.5,
			},
			{
				"name": "kamera_zum_radio_2",
				"aktion": "wisch",
				"von_rel": Vector2(0.45, 0.70),
				"nach_rel": Vector2(0.95, 0.48),
				"dauer_s": 0.5,
			},
			{"name": "kamera_beruhigen", "aktion": "warte", "sekunden": 0.4},
			{
				"name": "radio_antippen",
				"aktion": "tipp_3d",
				"finder": func() -> Node3D: return finde_moebel("radio"),
				"offset": Vector3(0.0, 0.35, 0.0),
				"erwarte": {"klasse": "RadioSheet"},
				"timeout_s": 30.0,
			},
			{"name": "radio_sheet_ansehen", "aktion": "warte", "sekunden": 2.0},
			{
				"name": "hud_weicht_dem_radio",
				"aktion": "warte_bis",
				"bedingung": hud_weicht,
				"timeout_s": 12.0,
			},
			{
				"name": "radio_dim_sichtbar",
				"aktion": "tue",
				"funktion": blatt_dim_sichtbar,
				"erwartung": "Backdrop-Dim hinter dem Radio-Blatt (P53)",
			},
			{
				"name": "like_knopf_im_canvas",
				"aktion": "tue",
				"funktion": like_im_canvas,
				"erwartung": "Like-Knopf liegt KOMPLETT im Canvas (P53-Fix FB3-Altbefund)",
			},
			{
				"name": "radio_einschalten",
				"aktion": "tipp_text",
				"text": "Einschalten",
				"erwarte": {"bedingung": radio_spielt},
				"timeout_s": 20.0,
			},
			{"name": "radio_laeuft_ansehen", "aktion": "warte", "sekunden": 2.0},
			{
				"name": "naechster_titel",
				"aktion": "tipp_text",
				"text": "Nächster Titel",
				"timeout_s": 15.0,
				"pflicht": false,
			},
			{
				"name": "titel_liken",
				"aktion": "tipp_text",
				"text": "Gefällt mir",
				"erwarte": {"text": "Gemerkt"},
				"timeout_s": 15.0,
				"pflicht": false,
			},
			{
				"name": "like_im_save",
				"aktion": "warte_bis",
				"bedingung": radio_like_da,
				"timeout_s": 10.0,
				"pflicht": false,
			},
			{
				"name": "radio_runterwischen_schliesst",
				"aktion": "wisch",
				"von_funktion": blatt_griff_pos,
				"nach_funktion": blatt_wisch_ziel,
				"dauer_s": 0.45,
				"erwarte": {"weg_klasse": "RadioSheet"},
				"timeout_s": 20.0,
			},
			{
				"name": "hud_zurueck_nach_radio",
				"aktion": "warte_bis",
				"bedingung": hud_da,
				"timeout_s": 12.0,
			},
			# ── GOB.TY (Fernseher am TV-Schrank, Rückwand, Welt-x ≈ 3.25).
			# Lauf 2: der Direkt-Tap scheiterte, weil die Follow-Kamera an
			# Goobys Wander-Position hing (TV ausserhalb der 3,6-m-Sicht).
			# Deterministisch machen: ZWEI Eck-Wische clampen den Pivot in
			# die SW-Ecke (0.8, 3.7) — egal wo Gooby steht —, der dritte
			# Wisch schiebt exakt +2,4 m nach rechts (845 px / 355 px pro m)
			# → Pivot ≈ 3.2, der TV steht mittig im Bild. Press-Punkte
			# liegen auf Boden/Sofa/Bär (KEINE TapAreas — Tür/Radio/Lampe
			# meiden, sonst öffnet der Pan versehentlich etwas).
			{
				"name": "kamera_ecke_1",
				"aktion": "wisch",
				"von_rel": Vector2(0.25, 0.66),
				"nach_rel": Vector2(0.85, 0.45),
				"dauer_s": 0.5,
			},
			{
				"name": "kamera_ecke_2",
				"aktion": "wisch",
				"von_rel": Vector2(0.45, 0.70),
				"nach_rel": Vector2(0.95, 0.48),
				"dauer_s": 0.5,
			},
			{
				"name": "kamera_zum_tv",
				"aktion": "wisch",
				"von_rel": Vector2(0.90, 0.55),
				"nach_rel": Vector2(0.24, 0.55),
				"dauer_s": 0.5,
			},
			{
				"name": "fernseher_einschalten",
				"aktion": "tipp_3d",
				"finder": func() -> Node3D: return finde_moebel("televisionModern"),
				"offset": Vector3(0.0, 0.5, 0.0),
				"erwarte": {"text": "Fernseher aus"},
				"timeout_s": 30.0,
			},
			{
				"name": "gobty_blase_ohne_wortabriss",
				"aktion": "tue",
				"funktion": blase_im_canvas,
				"erwartung": "GOB.TY-Blase komplett im Bild, Umbruch an Wortgrenzen (P51)",
				"pflicht": false,
			},
			{"name": "gobty_schauen", "aktion": "warte", "sekunden": 6.0},
			# Zappen: nach 6 s Schauen ist der Kamera-Halt abgelaufen —
			# dieselbe Eck+Korrektur-Kombo nochmal (alles pflicht=false).
			{
				"name": "kamera_ecke_zapp_1",
				"aktion": "wisch",
				"von_rel": Vector2(0.25, 0.66),
				"nach_rel": Vector2(0.85, 0.45),
				"dauer_s": 0.5,
				"pflicht": false,
			},
			{
				"name": "kamera_ecke_zapp_2",
				"aktion": "wisch",
				"von_rel": Vector2(0.45, 0.70),
				"nach_rel": Vector2(0.95, 0.48),
				"dauer_s": 0.5,
				"pflicht": false,
			},
			{
				"name": "kamera_zum_tv_zapp",
				"aktion": "wisch",
				"von_rel": Vector2(0.90, 0.55),
				"nach_rel": Vector2(0.24, 0.55),
				"dauer_s": 0.5,
				"pflicht": false,
			},
			{
				"name": "gobty_zappen",
				"aktion": "tipp_3d",
				"finder": func() -> Node3D: return finde_moebel("televisionModern"),
				"offset": Vector3(0.0, 0.5, 0.0),
				"erwarte": {"text": "Zapp"},
				"timeout_s": 20.0,
				"pflicht": false,
			},
			{"name": "gobty_weiter_schauen", "aktion": "warte", "sekunden": 3.0},
			{
				"name": "fernseher_ausschalten",
				"aktion": "tipp_text",
				"text": "Fernseher aus",
				"erwarte": {"weg_text": "Fernseher aus"},
				"timeout_s": 30.0,
			},
			{"name": "wohnzimmer_beruhigen", "aktion": "warte", "sekunden": 2.0},
			# ── GESCHICHTEN, Teil 1: Bett-Bauquest erfüllen (das Bett liegt
			# im Start-Lager; der erste Baumodus-Besuch startet den Geist
			# automatisch und „Fertig" ist bis zum Platzieren gesperrt).
			{
				"name": "baumodus_fuer_bett",
				"aktion": "tipp_name",
				"node": "BtnBau",
				"erwarte": {"text": "Fertig"},
				"timeout_s": 60.0,
			},
		]
	)
	liste.append_array(bett_platzieren_schritte())
	liste.append_array(
		[
			{"name": "bett_steht_ansehen", "aktion": "warte", "sekunden": 2.0},
			# ── GESCHICHTEN, Teil 2: Vorlesen am frisch gebauten Bett.
			{
				"name": "bett_antippen",
				"aktion": "tipp_3d",
				"finder": func() -> Node3D: return finde_moebel("bedSingle"),
				"offset": Vector3(0.0, 0.3, 0.0),
				"erwarte": {"text": "Bettzeit"},
				"timeout_s": 30.0,
			},
			{"name": "bettkarte_ansehen", "aktion": "warte", "sekunden": 1.5},
			{
				"name": "geschichte_waehlen",
				"aktion": "tipp_text",
				"text": "Gute-Nacht-Geschichte",
				"erwarte": {"text": "Bücherregal"},
				"timeout_s": 20.0,
			},
			{"name": "regal_ansehen", "aktion": "warte", "sekunden": 2.0},
			# KEIN Buch-Tap hier: das Öffnen eines Buchs CRASHT das Spiel
			# (story_time._setze_inhalt free()t die Bibliothek, während der
			# gedrückte Buch-Knopf darin noch sein pressed-Signal emittiert
			# → „freed while a signal is being emitted“ → Signal 11).
			# Dedizierter Repro-Flow: flow_pt4_geschichten. Hier prüfen wir
			# stattdessen die P53-Geste am Geschichten-Blatt.
			{
				"name": "geschichte_runterwischen",
				"aktion": "wisch",
				"von_funktion": blatt_griff_pos,
				"nach_funktion": blatt_wisch_ziel,
				"dauer_s": 0.45,
				"erwarte": {"bedingung": kein_blatt_offen},
				"timeout_s": 20.0,
			},
			{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
		]
	)
	return liste


## P53-Regressionsbeleg: der Like-Knopf (RadioSheet „Gefällt mir") liegt
## VOLLSTÄNDIG im Canvas — der FB3-Altbefund war ein Like-Knopf, der im
## Hochformat rechts aus dem Bild ragte (P=(961,1150.8) S=(352,156.3)).
func like_im_canvas() -> bool:
	var like := harness.root.find_child("Like", true, false) as Control
	if like == null or not like.is_visible_in_tree():
		print("[PT4] Like-Knopf nicht sichtbar")
		return false
	var rect := like.get_global_rect()
	var canvas := Rect2(Vector2.ZERO, harness.root.get_visible_rect().size)
	var drin := canvas.grow(1.0).encloses(rect)
	print("[PT4] Like-Knopf: %s im Canvas %s -> %s" % [str(rect), str(canvas), str(drin)])
	return drin


func radio_spielt() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	return bool(gs.get_value("radio.playing", false))


func radio_like_da() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var likes: Variant = gs.get_value("radio.likes", [])
	if likes is Array:
		return not (likes as Array).is_empty()
	if likes is Dictionary:
		return not (likes as Dictionary).is_empty()
	return false

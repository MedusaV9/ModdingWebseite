extends "res://tests/tools/playtest_flows/flow_pt4_geschichten.gd"
## VERIFY-PT R3 Nachfass-Flow (c) — gezielte B1-Crash-Nachmessung.
## Befund aus W18/R3: flow_pt4_geschichten erreichte den Story-Crash-Pfad
## (G8-B1: Startbuch-Tap segfaultete vor dem Fix) in BEIDEN Läufen nicht,
## weil schon der Bett-Tap scheiterte — tipp_3d tippt genau EINMAL, und
## in dem Moment flog die Kamera noch aus dem Baumodus zurück bzw. Gooby
## stand auf dem frisch platzierten Bett (Befund V5). Dieser Flow ersetzt
## den Einmal-Tap durch eine NACHFASSENDE Tipp-Serie: pro Versuch wird die
## Bett-Position FRISCH über die dann aktuelle Kamera projiziert; ist die
## Bettzeit-Karte schon offen, tippen Folgeversuche harmlos auf deren
## Titelzeile (nie auf den Backdrop — der würde sie schließen). Danach
## läuft der ORIGINAL-Story-Pfad über echte Eingabe-Events weiter:
## „Gute-Nacht-Geschichte“ → Startbuch „Goobys Möhrenmond-Fibel“ antippen
## (exakt der Tap, der vor dem Fix Signal 11 riss) → drei Wort-Chips →
## Gooby schläft ein, das Blatt schließt sich von selbst.
## Aufruf: tools/ci/run_playtest.sh flow_verify_r3c  (TZ tagsüber wählen,
## sonst funkt nachts das Gewitter-Angst-Event dazwischen — Befund V1).

## Kamera-Rückflug aus dem Baumodus aussitzen (llvmpipe: wenige FPS —
## die 1.5 s des Original-Flows reichten nicht immer).
const KAMERA_RUHE_S := 4.0


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append(
			{
				"name": "baumodus_fuer_bett",
				"aktion": "tipp_name",
				"node": "BtnBau",
				"erwarte": {"text": "Fertig"},
				"timeout_s": 60.0,
			}
		)
	)
	liste.append_array(bett_platzieren_schritte())
	liste.append_array(_kapitel_bett_hartnaeckig())
	liste.append_array(_kapitel_geschichte())
	return liste


# ── Kapitel: Bettzeit-Karte hartnäckig öffnen (V5-Umgehung) ──────────────────


func _kapitel_bett_hartnaeckig() -> Array[Dictionary]:
	return [
		{"name": "kamera_ruhe", "aktion": "warte", "sekunden": KAMERA_RUHE_S},
		{
			"name": "lage_peilen",
			"aktion": "tue",
			"funktion": _lage_loggen,
			"pflicht": false,
		},
		{
			"name": "bett_tipp_1",
			"aktion": "tipp_3d",
			"finder": func() -> Node3D: return finde_moebel("bedSingle"),
			"offset": Vector3(0.0, 0.3, 0.0),
			"erwarte": {"text": "Bettzeit"},
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{
			"name": "bett_tipp_2",
			"aktion": "tipp_pos",
			"pos_funktion": _bett_tipp_pos,
			"erwarte": {"text": "Bettzeit"},
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{
			"name": "bett_tipp_3",
			"aktion": "tipp_pos",
			"pos_funktion": _bett_tipp_pos,
			"erwarte": {"text": "Bettzeit"},
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{
			"name": "bettzeit_karte_da",
			"aktion": "warte_bis",
			"text": "Bettzeit",
			"timeout_s": 5.0,
		},
	]


# ── Kapitel: Original-Story-Pfad (B1-Crash-Strecke, echte Taps) ──────────────


func _kapitel_geschichte() -> Array[Dictionary]:
	return [
		{
			"name": "geschichte_waehlen",
			"aktion": "tipp_text",
			"text": "Gute-Nacht-Geschichte",
			"erwarte": {"text": "Bücherregal"},
			"timeout_s": 20.0,
		},
		{"name": "bibliothek_ansehen", "aktion": "warte", "sekunden": 1.5},
		# ── G8-B1-KERN: dieser Tap riss den Godot-Prozess vor dem Fix
		# mit Signal 11 ab — jetzt muss die Buchseite stehen.
		{
			"name": "startbuch_oeffnen",
			"aktion": "tipp_name",
			"node": "Buch_buch_moehrenmond",
			"erwarte": {"text": "Tippe ein Wort"},
			"timeout_s": 20.0,
		},
		{
			"name": "bibliothek_abgeloest",
			"aktion": "warte_bis",
			"weg_text": "Welches Buch lesen wir heute?",
			"timeout_s": 10.0,
		},
		{"name": "buchseite_ansehen", "aktion": "warte", "sekunden": 1.0},
		{"name": "wort_1_setzen", "aktion": "tipp_pos", "pos_funktion": wort_chip_pos},
		{"name": "wort_1_wirkt", "aktion": "warte", "sekunden": 0.6},
		{"name": "wort_2_setzen", "aktion": "tipp_pos", "pos_funktion": wort_chip_pos},
		{"name": "wort_2_wirkt", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "wort_3_gooby_schlaeft",
			"aktion": "tipp_pos",
			"pos_funktion": wort_chip_pos,
			"erwarte": {"text": "schöne Geschichte"},
			"timeout_s": 20.0,
		},
		{
			"name": "blatt_schliesst_von_selbst",
			"aktion": "warte_bis",
			"bedingung": kein_blatt_offen,
			"timeout_s": 20.0,
		},
		{"name": "gute_nacht_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "crash_bilanz",
			"aktion": "tue",
			"funktion": _crash_bilanz,
			"erwartung": "Prozess lebt nach dem kompletten B1-Pfad",
		},
	]


# ── Helfer ───────────────────────────────────────────────────────────────────


## Diagnose (kein Fail): Abstand Gooby ↔ frisch platziertes Bett loggen —
## Beleg-Sammlung für Befund V5 (Gooby fängt den Bett-Tap ab).
func _lage_loggen() -> bool:
	var bett := finde_moebel("bedSingle")
	var gooby := harness.root.find_child("Gooby", true, false) as Node3D
	if bett == null or gooby == null:
		print("[R3C] Lage: Bett=%s Gooby=%s" % [str(bett != null), str(gooby != null)])
		return true
	var abstand := gooby.global_position.distance_to(bett.global_position)
	print("[R3C] Gooby↔Bett Abstand: %.2f m" % abstand)
	return true


## Nachfass-Tap: Bett-Position FRISCH über die aktuelle Kamera projizieren.
## Steht die Bettzeit-Karte schon, harmlos auf ihre Titelzeile tippen
## (Panel schluckt den Tap — der Backdrop daneben würde sie SCHLIESSEN).
func _bett_tipp_pos() -> Vector2:
	var karte := harness.root.find_child("BettKarte", true, false) as Control
	if karte != null and karte.is_visible_in_tree():
		var rect := karte.get_global_rect()
		print("[R3C] Bettzeit-Karte offen — Nachfass-Tap auf die Titelzeile")
		return Vector2(rect.get_center().x, rect.position.y + 24.0)
	var bett := finde_moebel("bedSingle")
	var kamera := harness.root.get_camera_3d()
	if bett == null or kamera == null:
		print("[R3C] Nachfass-Tap: Bett/Kamera fehlt — neutraler Karten-Rand")
		return Vector2(8.0, harness.root.get_visible_rect().size.y * 0.5)
	var punkt := kamera.unproject_position(bett.global_position + Vector3(0.0, 0.3, 0.0))
	print("[R3C] Nachfass-Tap auf Bett bei %s" % str(punkt))
	return punkt


## Symbolischer Schlussstein: läuft dieser Schritt, hat der Prozess den
## kompletten B1-Pfad (Buch-Tap + 3 Wort-Chips + Blatt-Wechsel) überlebt.
func _crash_bilanz() -> bool:
	print("[R3C] B1-Pfad komplett durchlaufen — kein Signal 11, Prozess lebt")
	return true

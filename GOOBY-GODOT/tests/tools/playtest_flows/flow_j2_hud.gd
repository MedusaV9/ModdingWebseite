extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## G8/IDEA-J2-Flow „Icon-Bühne + Namensschilder" — Nachweis des STRUKTURELLEN
## B4-Fixes am Leitformat quer (2868x1320, iPhone 17 Pro Max):
## (1) Nach Login + Coachmark-„Alles klar!" läuft die Namensschild-PARADE
##     sichtbar durch und räumt sich selbst weg (einmal pro Sitzung).
##     llvmpipe-Ehrlichkeit: rendert der Software-GL die ~3-s-Parade
##     zwischen zwei Frames weg, legt die Sonde EINMAL deterministisch nach
##     (gleiche Choreografie über parade_starten) und loggt das.
## (2) Die alte B4-Sonde steht auf ERFOLG: Quer-Kacheln sind icon-only,
##     kein Label mehr abschneidbar (hud_labels_vollstaendig, Basis-Klasse).
## (3) LANGDRUCK (~0,4 s) auf der Garderoben-Kachel (B4-Postermotiv
##     „Garde…") zeigt ihr Namensschild, solange gehalten wird; der Release
##     öffnet KEINE App (Tap-Schlucker).
## (4) Ein normaler Tap auf dieselbe Kachel öffnet die Garderobe weiterhin.
## Aufruf: tools/ci/run_playtest.sh flow_j2_hud

## Fenster-px-Position des gehaltenen Fingers (für den Release).
var _langdruck_px := Vector2.ZERO
## Die Nachlege-Runde aus (1) darf höchstens einmal zünden.
var _parade_nachschlag := false


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				# ── (1) Parade nach Login/Coachmark.
				{
					"name": "parade_sichtbar",
					"aktion": "warte_bis",
					"bedingung": parade_oder_nachschlag,
					"timeout_s": 30.0,
				},
				{"name": "parade_ansehen", "aktion": "warte", "sekunden": 0.4},
				{
					"name": "parade_raeumt_sich_weg",
					"aktion": "warte_bis",
					"bedingung": kein_schild_sichtbar,
					"timeout_s": 30.0,
				},
				{
					"name": "parade_einmal_pro_sitzung",
					"aktion": "tue",
					"funktion": parade_abgehakt,
					"erwartung": "Session-Flag: Parade gilt als gezeigt",
				},
				# ── (2) B4-Sonde auf Erfolg (icon-only, nichts gekürzt).
				{
					"name": "hud_quer_ohne_kuerzungen",
					"aktion": "tue",
					"funktion": hud_labels_vollstaendig,
					"erwartung": "J2: Quer-HUD ohne abgeschnittene Kachel-Labels",
				},
				# ── (3) Langdruck: halten → Schild, Release → keine App.
				{
					"name": "langdruck_start",
					"aktion": "tue",
					"funktion": langdruck_start,
					"erwartung": "Garderoben-Kachel gefunden, Finger aufgesetzt",
				},
				{
					"name": "langdruck_schild_erscheint",
					"aktion": "warte_bis",
					"bedingung": langdruck_schild_da,
					"timeout_s": 20.0,
				},
				{"name": "langdruck_halten_ansehen", "aktion": "warte", "sekunden": 0.5},
				{
					"name": "langdruck_loslassen",
					"aktion": "tue",
					"funktion": langdruck_ende,
					"erwartung": "Finger wieder gelöst",
				},
				{
					"name": "langdruck_schild_geht_zu",
					"aktion": "warte_bis",
					"bedingung": kein_schild_sichtbar,
					"timeout_s": 15.0,
				},
				{"name": "langdruck_nachwirkung", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "langdruck_oeffnet_keine_app",
					"aktion": "tue",
					"funktion": route_ist_wohnzimmer,
					"erwartung": "Release nach Langdruck bleibt im Wohnzimmer",
				},
				# ── (4) Normaler Tap öffnet die App weiterhin.
				{
					"name": "tap_oeffnet_garderobe",
					"aktion": "tipp_name",
					"node": "BtnWardrobe",
					"erwarte": {"route": "wardrobe"},
					"timeout_s": 60.0,
				},
				{"name": "garderobe_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "zurueck_ins_wohnzimmer",
					"aktion": "tipp_text",
					"text": "Zurück",
					"erwarte": {"route": "home/living"},
					"timeout_s": 60.0,
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 1.0},
			]
		)
	)
	return liste


# ── Namensschild-Sonden ──────────────────────────────────────────────────────


## Die Icon-Bühne des lebenden HUDs (null, wenn keines da ist).
func buehne() -> HudIconBuehne:
	var wurzel := hud()
	if wurzel == null:
		return null
	return wurzel.find_child("IconBuehne", false, false) as HudIconBuehne


## Erstes sichtbares Namensschild (Gruppe hud_namensschilder) — null = keins.
func sichtbares_schild() -> Control:
	for node in harness.get_nodes_in_group(HudNamensschild.GRUPPE):
		var schild := node as Control
		if schild != null and schild.is_visible_in_tree():
			return schild
	return null


## (1): Parade-Schild sichtbar? Verpasste Parade (llvmpipe-Frame-Lücke über
## der ~3-s-Choreografie) wird EINMAL ehrlich nachgelegt — erst nachdem das
## Session-Flag beweist, dass der natürliche Auftritt gestartet war.
func parade_oder_nachschlag() -> bool:
	var wurzel := hud()
	if wurzel != null and wurzel.get("_coachmark") != null:
		# Coachmark noch offen → sichtbare Schilder wären DAUERSCHILDER (c),
		# nicht die Parade; das „Alles klar!" tippt der Onboarding-Schritt.
		return false
	var schild := sichtbares_schild()
	if schild != null:
		print("[J2] Parade sichtbar: %s" % schild.name)
		return true
	if _parade_nachschlag or not HudIconBuehne.parade_schon_gezeigt():
		return false
	var iconbuehne := buehne()
	if iconbuehne == null or iconbuehne.parade_laeuft():
		return false
	_parade_nachschlag = true
	print("[J2] Parade lief natürlich (Session-Flag), aber zwischen zwei")
	print("[J2] llvmpipe-Frames — lege EINMAL deterministisch nach.")
	HudIconBuehne.parade_reset_fuer_tests()
	iconbuehne.parade_starten()
	return false


func kein_schild_sichtbar() -> bool:
	return sichtbares_schild() == null


## Session-Flag der Bühne (Parade lief) — Beleg für „einmal pro Sitzung".
func parade_abgehakt() -> bool:
	return HudIconBuehne.parade_schon_gezeigt()


## (3): Langdruck-Schild der Garderoben-Kachel steht (Name + Text loggen).
func langdruck_schild_da() -> bool:
	var schild := sichtbares_schild()
	if schild == null or schild.name != "Langdruckschild":
		return false
	var text := str(schild.call("text_anzeige"))
	print("[J2] Langdruck-Schild zeigt: '%s'" % text)
	return text != ""


# ── Langdruck-Finger (Druck OHNE Release — die Harness-halte-Aktion würde
# vor der Schild-Sonde wieder loslassen) ─────────────────────────────────────


func langdruck_start() -> bool:
	var knopf := hud_teil("BtnWardrobe") as Button
	if knopf == null or not knopf.is_visible_in_tree():
		print("[J2] BtnWardrobe nicht sichtbar — kein Langdruck möglich")
		return false
	var canvas := knopf.get_global_rect().get_center()
	_langdruck_px = canvas * (Vector2(harness.root.size) / harness.root.get_visible_rect().size)
	_maus_bewegen(_langdruck_px)
	_maus_druck(_langdruck_px, true)
	print("[J2] Finger aufgesetzt auf BtnWardrobe @ %s" % str(_langdruck_px))
	return true


func langdruck_ende() -> bool:
	_maus_druck(_langdruck_px, false)
	print("[J2] Finger gelöst @ %s" % str(_langdruck_px))
	return true


func _maus_druck(px: Vector2, gedrueckt: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = gedrueckt
	ev.position = px
	ev.global_position = px
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if gedrueckt else 0
	Input.parse_input_event(ev)


func _maus_bewegen(px: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = px
	ev.global_position = px
	Input.parse_input_event(ev)


func route_ist_wohnzimmer() -> bool:
	var router := harness.root.get_node_or_null("/root/SceneRouter")
	if router == null:
		return false
	var route := str(router.get_current_target())
	print("[J2] Route nach Langdruck-Release: %s (busy=%s)" % [route, str(router.is_busy())])
	return route == "home/living" and not router.is_busy()

extends TestCase
## W20 P1 — OVERLAY-CHOREOGRAPHIE & HUD-DYNAMIK (Befund-Top-1/-4/-5/-9).
## Wachen:
## (a) HUD-ZUSTANDS-MATRIX des zentralen Verdeckungs-Vertrags: JEDER
##     Overlay-Kanal duckt das HUD und gibt es beim Schließen zurück —
##     manuelle Gründe (hud.verdecken/freigeben mit Zähler), FREMDE
##     PanelStack-Mitglieder ohne PanelSheet-Signale (Tagesbonus-Popup),
##     die Gruppe `hud_verdecker` (Telefon/PhoneShell) und gemischte
##     Kanäle; der Nutzer-Fall „Baumodus → Stats weg“ bleibt unangetastet
##     (Detail-Wachen weiter in test_g7_hud_dynamik).
## (b) EIN-WELCOME-OVERLAY-GARANTIE: die Guide-/Tour-Karte lag ÜBER dem
##     offenen Status-Sheet (die Lücke: das HUD-EIGENE Sheet zählt bewusst
##     NICHT als HUD-Verdeckung und der Overlay-Dirigent kennt es nicht) —
##     jetzt duckt sich die Karte, solange IRGENDEIN Panel im Stack lebt.
## (c) TOAST-LANE-KOLLISIONSFREIHEIT (Rect-Schnitt, FB3-Rechnung) in
##     BEIDEN Leitformaten: nie auf der Statuszeile, nie auf TabBars
##     (Gestalten-Tabs), nie auf `toast_hindernis`-Controls (Results-
##     Titel-Schnittstelle), nie unter dem Tiefen-Deckel. NACHFIX (FB3
##     kombi_overlap „Toast×Guide“): Guide-Tour-Karte und HUD-Coachmark
##     registrieren sich als `toast_hindernis` — Toasts rutschen unter
##     die Karte statt auf Weiter/Beenden/OK.
## (d) BLASEN-WORTBRUCH-WACHE: AcBubble/DialogBubble reservieren die volle
##     Text-Höhe (keine verschluckte Zeile, nichts endet mitten im Wort)
##     und messen NIE bei Breite ≤ 0 (W19-Lehre: Autowrap misst dann
##     Zeichen-für-Zeile). NACHFIX (FB3 kombi_overlap „10× Blase×Dock
##     hochkant“): die AcBubble meidet auch die HUD-Bodenmöblierung
##     (Hud.bubble_lane — hochkant das 10-Kachel-Dock) als Bottom-Sperre.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const BUBBLE_SCENE := preload("res://scripts/ui/dialog_bubble.tscn")
const WOHNZIMMER_SCENE := preload("res://scenes/home/wohnzimmer.tscn")

const NOW_MS := 1785448800000  # 2026-07-30 UTC
## Leitformate [Fenster-px, screen_scale, Insets in PUNKTEN l/t/r/b] —
## Rechnung wie fb3_ui_audit/test_w18_guide_karte (iPhone 17 Pro Max).
const FORMATE: Array = [
	[Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]],
	[Vector2i(1320, 2868), 3.0, [0.0, 59.0, 0.0, 34.0]],
]
## Desktop-Demo-Format des Video-Reviews (W20 P1c): kleines Fenster, f≈1,
## keine Insets — wie test_w20_bau_layout.DESKTOP_KLEIN.
const DESKTOP_KLEIN: Array = [Vector2i(1434, 660), 1.0, [0.0, 0.0, 0.0, 0.0]]
## FB3-Overlap-Toleranz: Schnitte ≤ 4×4 px gelten als Berührung.
const OVERLAP_TOLERANZ := 4.0
const LANGER_TEXT := (
	"Gooby freut sich riesig über einen außergewöhnlich langen Satz, der "
	+ "über mehrere Zeilen wickeln muss, damit die Wortbruch-Wache die "
	+ "komplette Text-Fit-Kette von Messung bis Kapselhöhe prüfen kann — "
	+ "inklusive Zeilenabstand, Innenrändern und der letzten Zeile."
)
## Worst-Case-Toast wie fb3_ui_audit.KOMBI_TOAST_TEXT: volle Breite.
const LANGER_TOAST := (
	"Abzeichen verdient! Dieser bewusst lange Wächter-Toast fährt die "
	+ "volle Breite aus und muss unter der Guide-Karte einsortiert werden."
)

var _seq := 0

# ── Helfer (Muster test_g7_hud_dynamik / test_w18_guide_karte) ───────────────


func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func _pin_format(format: Array) -> void:
	var fenster: Vector2i = format[0]
	UiScale.screen_scale_override = float(format[1])
	tree.root.size = fenster
	tree.root.size_changed.emit()
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var scale: float = format[1]
	var insets_pt: Array = format[2]
	var px_per_pt := minf(canvas.x, canvas.y) / (minf(fenster.x, fenster.y) / scale)
	var l := float(insets_pt[0]) * px_per_pt
	var t := float(insets_pt[1]) * px_per_pt
	var r := float(insets_pt[2]) * px_per_pt
	var b := float(insets_pt[3]) * px_per_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin_format(fenster_vorher: Vector2i) -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


func _hud_bauen() -> Hud:
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	return hud


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w20_choreo_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	gs.apply_onboarding_profile({"player_name": "Tester", "gooby_nickname": "Flauschi"})
	return gs


func _echter_schnitt(a: Rect2, b: Rect2) -> bool:
	var schnitt := a.intersection(b)
	return schnitt.size.x > OVERLAP_TOLERANZ and schnitt.size.y > OVERLAP_TOLERANZ


# ── (a) HUD-Zustands-Matrix ──────────────────────────────────────────────────


func test_vertrag_manuelle_gruende_mit_zaehler() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var hud := _hud_bauen()
	await wait_frames(2)
	assert_false(hud.sichtbarkeit().verdeckt(), "Startlage: HUD sichtbar")
	# Unbekannten Grund freigeben = No-op (kein Unterlauf).
	hud.freigeben(&"nie_angemeldet")
	assert_false(hud.sichtbarkeit().verdeckt(), "Fremd-Freigabe kippt nichts")
	hud.verdecken(&"tagesbonus")
	assert_true(hud.sichtbarkeit().verdeckt(), "1 Grund → HUD verdeckt")
	# Derselbe Grund doppelt: braucht zwei Freigaben (Zähler pro Grund).
	hud.verdecken(&"tagesbonus")
	hud.freigeben(&"tagesbonus")
	assert_true(hud.sichtbarkeit().verdeckt(), "Grund 2× angemeldet → 1 Freigabe reicht nicht")
	# Zweiter unabhängiger Grund: ODER-Logik über alle Gründe.
	hud.verdecken(&"reunion")
	hud.freigeben(&"tagesbonus")
	assert_true(hud.sichtbarkeit().verdeckt(), "anderer Grund lebt noch → HUD bleibt weg")
	assert_eq(hud.sichtbarkeit().grund_zaehler(), 1, "nur noch 1 aktiver Grund")
	hud.freigeben(&"reunion")
	assert_false(hud.sichtbarkeit().verdeckt(), "letzter Grund weg → HUD zurück")
	# PRIMARY-Kachel prüfen — Zweitrangiges lebt im Cockpit eingeklappt
	# hinter der Mehr-Kachel (W20-P1-Slimming) und ist bewusst unsichtbar.
	var kachel: Button = hud._buttons[&"bau"]
	assert_true(kachel.is_visible_in_tree(), "Kachel nach Rückkehr sichtbar")
	assert_false(kachel.disabled, "Kachel nach Rückkehr aktiv")
	hud.free()
	_set_reduced_motion(rm_vorher)


func test_vertrag_fremdes_panel_stack_mitglied() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var hud := _hud_bauen()
	await wait_frames(2)
	# ECHTES Tagesbonus-Popup (Befund-Top-1-Auslöser): plain Control im
	# PanelStack, KEIN PanelSheet — vor dem Vertrag sah das HUD es nicht.
	var popup := DailyBonusPopup.new()
	tree.root.add_child(popup)
	await wait_frames(2)
	assert_true(PanelStack.count() > 0, "Popup lebt im PanelStack (Vorbedingung)")
	assert_true(hud.sichtbarkeit().verdeckt(), "Tagesbonus offen → HUD verdeckt")
	assert_true((hud._buttons[&"bau"] as Button).disabled, "Kacheln gesperrt")
	popup._on_later()
	await wait_frames(2)
	assert_false(hud.sichtbarkeit().verdeckt(), "Tagesbonus zu → HUD zurück")
	assert_false((hud._buttons[&"bau"] as Button).disabled, "Kacheln wieder aktiv")
	hud.free()
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)


func test_vertrag_verdecker_gruppe_telefon() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var hud := _hud_bauen()
	await wait_frames(2)
	# PhoneShell-Kanal: Vollbild-Modal OHNE PanelStack meldet sich nur per
	# Gruppe an (1-Zeilen-Hook) — Sichtbarkeit steuert die Verdeckung.
	var telefon := Control.new()
	telefon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	telefon.add_to_group(HudSichtbarkeit.VERDECKER_GROUP)
	tree.root.add_child(telefon)
	await wait_frames(2)
	assert_true(hud.sichtbarkeit().verdeckt(), "Telefon sichtbar → HUD verdeckt")
	telefon.visible = false
	await wait_frames(2)
	assert_false(hud.sichtbarkeit().verdeckt(), "Telefon versteckt → HUD zurück")
	telefon.visible = true
	await wait_frames(2)
	assert_true(hud.sichtbarkeit().verdeckt(), "Telefon wieder da → HUD weicht erneut")
	telefon.free()
	await wait_frames(2)
	assert_false(hud.sichtbarkeit().verdeckt(), "Telefon freigegeben → HUD zurück")
	hud.free()
	_set_reduced_motion(rm_vorher)


func test_vertrag_gemischte_kanaele_und_baumodus_bleibt() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var hud := _hud_bauen()
	await wait_frames(2)
	# Nutzer-Fall „Baumodus → Stats weg“ (darf durch den Vertrag NICHT
	# schlechter werden; Detail-Wachen in test_g7_hud_dynamik).
	var bau := BuildMode.new()
	tree.root.add_child(bau)
	await wait_frames(1)
	bau.opened.emit()
	await wait_frames(1)
	assert_true(hud.sichtbarkeit().verdeckt(), "Baumodus an → HUD verdeckt")
	# Fremdes Panel WÄHREND des Baumodus: erst wenn BEIDE Kanäle frei
	# sind, kehrt das HUD zurück (Reihenfolge-Robustheit über Kanäle).
	var panel := Control.new()
	tree.root.add_child(panel)
	PanelStack.push(panel)
	await wait_frames(2)
	bau.closed.emit()
	await wait_frames(2)
	assert_true(hud.sichtbarkeit().verdeckt(), "Baumodus zu, Panel lebt → HUD bleibt weg")
	PanelStack.remove(panel)
	panel.free()
	await wait_frames(2)
	assert_false(hud.sichtbarkeit().verdeckt(), "alle Kanäle frei → HUD zurück")
	bau.free()
	hud.free()
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)


# ── (b) Ein-Welcome-Overlay-Garantie ─────────────────────────────────────────


func test_guide_karte_nie_ueber_offenem_status_sheet() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin_format(FORMATE[0])
	var rm_vorher := _set_reduced_motion(true)
	var gs := _fresh_gs()
	var hud := _hud_bauen()
	await wait_frames(2)
	# Raum-Kontext stellen, damit die Karte zeigen darf (W18-Muster).
	var router := tree.root.get_node_or_null("SceneRouter")
	var szene_vorher: Node = null
	var raum := RoomBase.new()
	if router != null:
		szene_vorher = router.get_current_scene()
		router._current_scene = raum
	var host := Node.new()
	tree.root.add_child(host)
	var guide := OnboardingGuide.attach_to(host, gs)
	assert_ne(guide, null, "frischer Save startet die Tour")
	await wait_frames(3)
	var karte: Control = guide._card
	assert_true(karte.visible, "Karte zeigt im Raum-Kontext (Vorbedingung)")
	# DIE Befund-Top-4-Lücke: das HUD-EIGENE Status-Sheet verdeckt das HUD
	# bewusst NICHT (sonst blendete es sich mitsamt Blatt aus) und der
	# Overlay-Dirigent kennt es nicht — die Karte lag darüber.
	hud.set_stats({"hunger": 50.0, "energie": 50.0, "hygiene": 50.0, "spass": 50.0})
	hud.open_status_sheet()
	await wait_frames(2)
	assert_true(PanelStack.count() > 0, "Status-Sheet lebt im PanelStack (Vorbedingung)")
	assert_false(
		hud.sichtbarkeit().verdeckt(), "Eigen-Sheet verdeckt das HUD nicht (Lücken-Nachweis)"
	)
	assert_false(karte.visible, "Karte duckt sich unter dem offenen Status-Sheet")
	hud._status_sheet.close()
	await wait_frames(3)
	assert_true(karte.visible, "Sheet zu → Karte kommt von selbst zurück")
	if router != null:
		router._current_scene = szene_vorher
	raum.free()
	host.free()
	hud.free()
	gs.get_parent().remove_child(gs)
	gs.free()
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)


# ── (c) Toast-Lane ───────────────────────────────────────────────────────────


func test_toast_lane_kollisionsfrei_in_beiden_leitformaten() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var rm_vorher := _set_reduced_motion(true)
	for format: Array in FORMATE:
		await _pin_format(format)
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var hud := _hud_bauen()
		await wait_frames(2)
		var toasts := ToastLayer.new()
		toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tree.root.add_child(toasts)
		await wait_frames(1)
		# Hindernisse DORT parken, wo der Toast natürlich landet (Lane-
		# Start): ein TabBar (Gestalten-Raum-Tabs) und ein Control der
		# Opt-in-Gruppe `toast_hindernis` (Results-Titel-Schnittstelle).
		var lane: Dictionary = hud.hint_lane()
		var tabs := TabBar.new()
		tabs.add_tab("Wohnzimmer")
		tabs.add_tab("Küche")
		tabs.add_tab("Bad")
		tabs.position = Vector2(canvas.x / 2.0 - 300.0, float(lane["top"]))
		tabs.size = Vector2(600.0, 64.0)
		tree.root.add_child(tabs)
		var titel := Panel.new()
		titel.add_to_group(ToastLayer.HINDERNIS_GROUP)
		titel.position = Vector2(canvas.x / 2.0 - 300.0, tabs.position.y + 72.0)
		titel.size = Vector2(600.0, 56.0)
		tree.root.add_child(titel)
		await wait_frames(1)
		toasts.show_toast("Quest geschafft: +40 Münzen!")
		await wait_frames(4)
		var panel := toasts.find_child("ToastPanel", true, false) as Control
		assert_true(panel != null and panel.visible, "Toast sichtbar @ %s" % format[0])
		var toast_rect := panel.get_global_rect()
		# Statuszeile/HUD-Chrome: TopBar (hochkant), Status-Spalte +
		# Cockpit-Spalte + Zahnrad (quer) — nie überlappen.
		for teil: Variant in [
			hud.get_node("TopBar"), hud._left_column, hud._landscape_column, hud._settings_button
		]:
			var chrome := teil as Control
			if chrome == null or not chrome.is_visible_in_tree():
				continue
			assert_false(
				_echter_schnitt(toast_rect, chrome.get_global_rect()),
				(
					"Toast %s überlappt HUD-Chrome %s (%s) @ %s"
					% [toast_rect, chrome.name, chrome.get_global_rect(), format[0]]
				)
			)
		assert_false(
			_echter_schnitt(toast_rect, tabs.get_global_rect()),
			"Toast %s überlappt TabBar %s @ %s" % [toast_rect, tabs.get_global_rect(), format[0]]
		)
		assert_false(
			_echter_schnitt(toast_rect, titel.get_global_rect()),
			(
				"Toast %s überlappt toast_hindernis %s @ %s"
				% [toast_rect, titel.get_global_rect(), format[0]]
			)
		)
		# Safe-Area + Tiefen-Deckel: nie hinter der Notch, nie unter der
		# MAX_TIEFE_ANTEIL-Lane (Dodge-Sturm-Schutz).
		var insets := UiScale.safe_insets_canvas(tree.root)
		assert_true(
			toast_rect.position.y >= float(insets["top"]),
			"Toast unter der Safe-Top-Kante (%.0f) @ %s" % [toast_rect.position.y, format[0]]
		)
		assert_true(
			toast_rect.position.y <= canvas.y * ToastLayer.MAX_TIEFE_ANTEIL + 1.0,
			"Toast über dem Tiefen-Deckel (%.0f) @ %s" % [toast_rect.position.y, format[0]]
		)
		titel.free()
		tabs.free()
		toasts.free()
		hud.free()
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)


func test_toast_weicht_guide_karte_aus() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var rm_vorher := _set_reduced_motion(true)
	# Registrierungs-Vertrag: auch der HUD-Coachmark meldet sich als
	# Toast-Hindernis an (gleiche FB3-Befundfamilie „Toast×Guide“).
	var coachmark := HudCoachmark.new()
	coachmark._baue(tree.root)
	assert_true(
		coachmark.is_in_group(ToastLayer.HINDERNIS_GROUP),
		"HUD-Coachmark registriert sich als toast_hindernis"
	)
	coachmark.free()
	for format: Array in FORMATE:
		await _pin_format(format)
		var gs := _fresh_gs()
		var hud := _hud_bauen()
		await wait_frames(2)
		# Raum-Kontext stellen, damit die Tour-Karte zeigen darf.
		var router := tree.root.get_node_or_null("SceneRouter")
		var szene_vorher: Node = null
		var raum := RoomBase.new()
		if router != null:
			szene_vorher = router.get_current_scene()
			router._current_scene = raum
		var host := Node.new()
		tree.root.add_child(host)
		var guide := OnboardingGuide.attach_to(host, gs)
		assert_ne(guide, null, "frischer Save startet die Tour @ %s" % format[0])
		await wait_frames(3)
		var karte: Control = guide._card
		assert_true(karte.visible, "Guide-Karte sichtbar (Vorbedingung) @ %s" % format[0])
		assert_true(
			karte.is_in_group(ToastLayer.HINDERNIS_GROUP),
			"Guide-Karte registriert sich als toast_hindernis"
		)
		var toasts := ToastLayer.new()
		toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tree.root.add_child(toasts)
		await wait_frames(1)
		toasts.show_toast(LANGER_TOAST)
		await wait_frames(4)
		var panel := toasts.find_child("ToastPanel", true, false) as Control
		assert_true(panel != null and panel.visible, "Toast sichtbar @ %s" % format[0])
		assert_false(
			_echter_schnitt(panel.get_global_rect(), karte.get_global_rect()),
			(
				"Toast %s überlappt die Guide-Karte %s @ %s"
				% [panel.get_global_rect(), karte.get_global_rect(), format[0]]
			)
		)
		if router != null:
			router._current_scene = szene_vorher
		raum.free()
		host.free()
		toasts.free()
		hud.free()
		gs.get_parent().remove_child(gs)
		gs.free()
		PanelStack.clear()
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)


# ── (d) Blasen-Wortbruch-Wache ───────────────────────────────────────────────


func test_ac_bubble_verschluckt_keine_zeile() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin_format(FORMATE[0])
	var rm_vorher := _set_reduced_motion(true)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(layer)
	await wait_frames(1)
	var bubble := AcBubble.show_bubble(layer, LANGER_TEXT, {"dauer_s": 60.0})
	await wait_frames(3)
	var label: Label = bubble._label
	assert_true(label.get_line_count() >= 2, "langer Text wickelt über mehrere Zeilen")
	assert_eq(
		label.get_visible_line_count(),
		label.get_line_count(),
		"AcBubble: JEDE Zeile sichtbar — keine verschluckte Zeile/kein Wortbruch"
	)
	# W19-Lehre: Breite ≤ 0 darf NIE gemessen werden (Zeichen-für-Zeile).
	assert_eq(bubble._wrap_hoehe(0.0), 0.0, "Breite-0-Messung ist verboten")
	assert_eq(bubble._wrap_hoehe(-10.0), 0.0, "negative Breite ist verboten")
	layer.free()
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)


func test_ac_bubble_meidet_hud_dock_hochkant() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin_format(FORMATE[1])
	var rm_vorher := _set_reduced_motion(true)
	var hud := _hud_bauen()
	await wait_frames(2)
	var dock: Control = hud._portrait_dock
	assert_true(dock != null and dock.is_visible_in_tree(), "Hochkant-Dock sichtbar (Vorbedingung)")
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(layer)
	await wait_frames(1)
	# Worst Case wie FB3-Station 24: lange Blase OHNE Sprecher landet
	# unten mittig — genau dort wohnt hochkant das 10-Kachel-Dock.
	var bubble := AcBubble.show_bubble(layer, LANGER_TEXT, {"dauer_s": 60.0})
	await wait_frames(3)
	var kapsel_rect := (bubble._kapsel as Control).get_global_rect()
	assert_false(
		_echter_schnitt(kapsel_rect, dock.get_global_rect()),
		"Blase %s überlappt das Hochkant-Dock %s" % [kapsel_rect, dock.get_global_rect()]
	)
	for id: StringName in hud._buttons:
		var btn: Button = hud._buttons[id]
		if not btn.is_visible_in_tree():
			continue
		assert_false(
			_echter_schnitt(kapsel_rect, btn.get_global_rect()),
			"Blase %s überlappt Dock-Kachel %s (%s)" % [kapsel_rect, id, btn.get_global_rect()]
		)
	layer.free()
	hud.free()
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)


func test_dialog_bubble_reserviert_volle_texthoehe() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin_format(FORMATE[0])
	var rm_vorher := _set_reduced_motion(true)
	# Beide Pfade: MIT HUD (Home, _fit_height) und OHNE (Stadt, _zeilen_fit).
	for mit_hud: bool in [true, false]:
		var hud: Hud = null
		if mit_hud:
			hud = _hud_bauen()
			await wait_frames(2)
		var bubble: DialogBubble = BUBBLE_SCENE.instantiate()
		bubble.sofort_override = 1
		tree.root.add_child(bubble)
		await wait_frames(1)
		bubble.show_lines([LANGER_TEXT])
		await wait_frames(3)
		var text: Label = bubble._text
		assert_true(text.get_line_count() >= 2, "langer Text wickelt (HUD=%s)" % mit_hud)
		assert_eq(
			text.get_visible_line_count(),
			text.get_line_count(),
			"DialogBubble: JEDE Zeile sichtbar (HUD=%s) — kein Wortbruch/Abschnitt" % mit_hud
		)
		assert_eq(bubble._text_hoehe(0.0), 0.0, "Breite-0-Messung verboten (HUD=%s)" % mit_hud)
		bubble.free()
		if hud != null:
			hud.free()
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)


# ── (e) Quest-Blase × Bau-Action-Bar (Video-Review 0:27) ─────────────────────


## Home-Save MIT aktiver Bett-Quest (Bett liegt im Lager, Flag ungesetzt) —
## Muster test_w20_bau_layout._fresh_gs(mit_bett_quest=true).
func _home_gs_mit_bett_quest() -> Node:
	_seq += 1
	var dir := "user://w20_choreo_tests/home_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	return gs


func _home_aufraeumen(room: Node, gs: Node) -> void:
	if room != null:
		room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()


func test_quest_blase_meidet_bau_action_bar() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var rm_vorher := _set_reduced_motion(true)
	for format: Array in [DESKTOP_KLEIN, FORMATE[0]]:
		await _pin_format(format)
		var gs := _home_gs_mit_bett_quest()
		var room: RoomBase = WOHNZIMMER_SCENE.instantiate()
		room.game_state_override = gs
		room.stunde_override = 13.0
		tree.root.add_child(room)
		await wait_frames(6)
		room.open_build_mode()
		await wait_frames(4)
		var build: BuildMode = room.get_node("BuildMode")
		assert_true(build._action_bar.visible, "Bett-Geist: Action-Bar sichtbar @ %s" % format[0])
		var zone := BuildUiDock.aktive_zone()
		assert_true(zone.size.y > 0.0, "aktive_zone() liefert die Dock-Zone @ %s" % format[0])
		var bubble: AcBubble = room._bubble
		assert_true(bubble != null and bubble.is_active(), "Bett-Quest-Blase lebt @ %s" % format[0])
		var kapsel_rect := (bubble._kapsel as Control).get_global_rect()
		assert_false(
			_echter_schnitt(kapsel_rect, zone),
			"Quest-Blase %s überlappt die Dock-Zone %s @ %s" % [kapsel_rect, zone, format[0]]
		)
		# Worst Case: Sprecher-Projektion mitten IN der Dock-Zone (Gooby
		# läuft unters Dock) — die Blase weicht trotzdem über die Zone aus.
		var kamera := tree.root.get_camera_3d()
		assert_ne(kamera, null, "Bau-Kamera aktiv @ %s" % format[0])
		var marker := Marker3D.new()
		room.add_child(marker)
		marker.global_position = kamera.project_position(zone.get_center(), 6.0)
		bubble.speaker_3d = marker
		await wait_frames(2)
		kapsel_rect = (bubble._kapsel as Control).get_global_rect()
		assert_false(
			_echter_schnitt(kapsel_rect, zone),
			(
				"Quest-Blase %s überlappt die Dock-Zone %s trotz Sprecher darin @ %s"
				% [kapsel_rect, zone, format[0]]
			)
		)
		# Video-Wurzel 0:27: NICHT die Kapsel, sondern der SPRECH-SCHWANZ
		# (TAIL_H unter der Kapsel, tiefer als die 8-px-dodge-Luft) ragte
		# in „Drehen/Platzieren“ — der ganze Blasen-Fußabdruck bleibt raus.
		var schwanz_rect := (bubble._tail as Control).get_global_rect()
		assert_false(
			_echter_schnitt(schwanz_rect, zone),
			"Blasen-Schwanz %s ragt in die Dock-Zone %s @ %s" % [schwanz_rect, zone, format[0]]
		)
		for knopf: Button in build._dock_ui.action_buttons:
			if not knopf.is_visible_in_tree():
				continue
			for teil_rect: Rect2 in [kapsel_rect, schwanz_rect]:
				assert_false(
					_echter_schnitt(teil_rect, knopf.get_global_rect()),
					(
						"Quest-Blase %s überlappt „%s“ (%s) @ %s"
						% [teil_rect, knopf.text, knopf.get_global_rect(), format[0]]
					)
				)
		await _home_aufraeumen(room, gs)
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)


# ── (g) Toast × Bau-Dock (W21-Playtest-Repro Baumodus) ──────────────────────


## W21-Repro: der Tagesbonus-Toast („+20 Münzen“) stand mitten auf dem
## Verkaufen-Knopf der Bau-Lager-Karte. Die Repro-Geometrie (Playtest
## w21_bau_quer_zustaende): ein Hindernis (Guide-Karte-Familie) drückte
## den Toast per Dodge unter den Tiefen-Deckel, der alte Deckel-Clamp
## NACH dem Bottom-Ausweichen zog ihn zurück IN die Dock-Zone — und beim
## Öffnen des Baumodus positionierte sich der stehende Toast nie neu.
## Zwei Wachen in BEIDEN Leitformaten:
## (1) Toast steht SCHON (tief gedodgt), dann öffnet der Baumodus → der
##     Belegungs-Beobachter (UiAnchors.beobachte) positioniert ihn neu.
## (2) Toast erscheint, WÄHREND das Dock schon offen ist → Dock-Sperrzone
##     als Bottom-Blocker + Deckel VOR dem Bottom-Dodge halten ihn raus.
func test_toast_meidet_bau_dock_vor_und_nach_dem_oeffnen() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var rm_vorher := _set_reduced_motion(true)
	for format: Array in FORMATE:
		await _pin_format(format)
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var gs := _home_gs_mit_bett_quest()
		var room: RoomBase = WOHNZIMMER_SCENE.instantiate()
		room.game_state_override = gs
		room.stunde_override = 13.0
		tree.root.add_child(room)
		await wait_frames(6)
		var toasts := ToastLayer.new()
		toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tree.root.add_child(toasts)
		# Repro-Hindernis: drückt den Toast wie die Guide-Karte per Dodge
		# unter den Tiefen-Deckel — knapp über die spätere Dock-Zone.
		var hindernis := Panel.new()
		hindernis.add_to_group(ToastLayer.HINDERNIS_GROUP)
		hindernis.position = Vector2(canvas.x / 2.0 - 300.0, canvas.y * 0.08)
		hindernis.size = Vector2(600.0, canvas.y * 0.54)
		tree.root.add_child(hindernis)
		await wait_frames(1)
		# Wache 1 (Repro-Reihenfolge): Toast ZUERST, Baumodus DANACH.
		toasts.show_toast("+20 Münzen — bis morgen!")
		await wait_frames(4)
		var panel := toasts.find_child("ToastPanel", true, false) as Control
		assert_true(
			panel != null and panel.visible, "Toast sichtbar (Vorbedingung) @ %s" % format[0]
		)
		room.open_build_mode()
		await wait_frames(4)
		var zone := BuildUiDock.aktive_zone()
		assert_true(zone.size.y > 0.0, "aktive_zone() liefert die Dock-Zone @ %s" % format[0])
		assert_false(
			_echter_schnitt(panel.get_global_rect(), zone),
			(
				"stehender Toast %s bleibt auf der Dock-Zone %s liegen @ %s"
				% [panel.get_global_rect(), zone, format[0]]
			)
		)
		# Wache 2: frischer Toast bei BEREITS offenem Dock.
		toasts.queue.clear()
		toasts.show_toast("Quest geschafft: +40 Münzen!")
		await wait_frames(4)
		assert_true(panel.visible, "Zweit-Toast sichtbar (Vorbedingung) @ %s" % format[0])
		assert_false(
			_echter_schnitt(panel.get_global_rect(), zone),
			(
				"frischer Toast %s landet in der Dock-Zone %s @ %s"
				% [panel.get_global_rect(), zone, format[0]]
			)
		)
		hindernis.free()
		toasts.free()
		await _home_aufraeumen(room, gs)
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)


# ── (f) Kein-Ellipsis-Vertrag (Video-Review 0:21 „ICH FINDE SIE NICHT U…“) ───


func test_blase_zeigt_kurze_sprueche_ganz_ohne_ellipsis() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var rm_vorher := _set_reduced_motion(true)
	var spruch := I18nService.t("events.fernbedienung.bubble")
	assert_true(spruch.length() > 40, "echter Fundstück-Spruch geladen (kein Key-Fallback)")
	assert_true(
		spruch.length() <= AcBubble.GANZTEXT_MAX_ZEICHEN,
		"Beispiel-Spruch liegt unter der dokumentierten Ganztext-Maximallänge"
	)
	for format: Array in [DESKTOP_KLEIN, FORMATE[0]]:
		await _pin_format(format)
		var layer := Control.new()
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tree.root.add_child(layer)
		await wait_frames(1)
		# BEIDE Lebenswege: frische Blase UND ersetze_text (RoomBase.say
		# ersetzt die lebende Blase — der Video-Pfad der Event-Sprüche).
		var bubble := AcBubble.show_bubble(layer, "Kurzer Auftakt.", {"dauer_s": 60.0})
		await wait_frames(2)
		assert_true(bubble.ersetze_text(spruch), "ersetze_text übernimmt den Spruch")
		await wait_frames(3)
		var label: Label = bubble._label
		assert_eq(label.visible_characters, -1, "Typewriter fertig @ %s" % format[0])
		assert_eq(
			int(label.text_overrun_behavior),
			int(TextServer.OVERRUN_NO_TRIMMING),
			"kein Ellipsis-Trimm auf Blasen-Text @ %s" % format[0]
		)
		assert_eq(
			label.get_visible_line_count(),
			label.get_line_count(),
			"JEDE Zeile des Spruchs sichtbar @ %s" % format[0]
		)
		assert_true(
			label.size.y + 0.5 >= bubble._wrap_hoehe(label.size.x),
			(
				"Label-Höhe %.1f fasst den gewickelten Text (%.1f) @ %s"
				% [label.size.y, bubble._wrap_hoehe(label.size.x), format[0]]
			)
		)
		assert_true(
			(bubble._kapsel as Control).get_global_rect().grow(1.0).encloses(
				label.get_global_rect()
			),
			"Kapsel umschließt das Label — nichts clippt @ %s" % format[0]
		)
		layer.free()
		AcBubble.warteschlange = AcBubble.Warteschlange.new()
		UiAnchors.reset_for_tests()
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)

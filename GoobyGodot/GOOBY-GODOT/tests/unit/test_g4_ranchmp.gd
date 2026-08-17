extends TestCase
## G4/P19 UI-RANCHMP — Geometrie- und Strecken-Tests: Hof-HUD (Kopfzeile
## mittig oben, Daumen-Cluster unten Mitte, Touch-Floor, Resize-Pass), der
## NEUE Ranch-MP-Einstieg (Hof-Knopf → RmpHub → PanelSheet-Strecke Menü →
## Bestenliste → Lobby → Ende), die Safe-Klemmung der MP-Panels, der
## RcompHud-UiScale-Pass (Kopf CENTER_TOP statt Ecke), der 44-pt-Fangradius
## der Ranch-Event-Requisiten und der Turnier-UI-Pass (Fertig mittig,
## Mitte-Panel-Höhendeckel). Geometrie-Tests pinnen das Fenster VOR dem
## Bau auf Vector2i(1280, 720) (Muster test_g3_wardrobe: headless übernimmt
## Window-Größen erst im Folge-Frame) und setzen es am Testende zurück.

const HOF_SZENE := "res://scenes/ranch/ranch_hof.tscn"
const TURNIER_SKRIPT := "res://scripts/minigames/games/ranch_turnier/turnier_game.gd"

var _saved_root_size := Vector2i.ZERO


## GameState-Double (Muster test_g4_media): dotted get/set — reicht für
## RanchState.ist_gekauft/pferde (beides fällt auf die Fallbacks zurück).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## Trägerszene für Hub-/Event-Tests: sammelt Toast-Meldungen (Hof-Vertrag
## zeige_meldung) und liefert den Event-Anker vor der Kamera.
class TraegerSzene:
	extends Node3D
	var meldungen: Array[String] = []

	func zeige_meldung(text: String) -> void:
		meldungen.append(text)

	func event_anker() -> Vector3:
		return Vector3(0.0, 0.0, -30.0)


# ------------------------------------------------------------ Fenster-Helfer


func _pin(size: Vector2i) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.insets_override = Rect2()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		_saved_root_size = Vector2i.ZERO
	tree.root.size_changed.emit()
	await wait_frames(2)


# ------------------------------------------------------------------ Strings


## Die neuen additiven Keys existieren DE+EN (Parität sichert test_rmp_ui,
## hier: die G4-Einträge dürfen nicht wieder verschwinden).
func test_strings_neue_g4_keys_de_en() -> void:
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var keys: Array[String] = [
		"ranch_mp.menu.hof_knopf",
		"ranch_mp.lobby.beendet",
		"ranch_mp.besten.geist_ok",
	]
	for key in keys:
		assert_true(str(de.get(key, "")).length() > 0, "DE fehlt: %s" % key)
		assert_true(str(en.get(key, "")).length() > 0, "EN fehlt: %s" % key)


# ------------------------------------------------------------------ Hof-HUD


## G1 §1.6: Kopfzeile (Titel + Stadt-Chip) mittig OBEN unter der Safe-Area,
## Daumen-Cluster (Ausreiten · Galopp · Mehrspieler · Karte, W19) mittig
## UNTEN über dem Home-Indicator — SquishButtons mit Touch-Floor,
## Resize-Pass zieht nach.
func test_hof_hud_kopf_oben_cluster_unten_mitte() -> void:
	await _pin(Vector2i(1280, 720))
	# Notch-Simulation: top 24 px, bottom 34 px (Home-Indicator).
	UiScale.insets_override = Rect2(0.0, 24.0, 1280.0, 662.0)
	var gs := FakeGameState.new()
	var szene: RanchHofScene = (load(HOF_SZENE) as PackedScene).instantiate()
	szene.game_state_override = gs
	szene.stunde_override = 13.0
	tree.root.add_child(szene)
	await wait_frames(4)
	var hud: Control = szene.get_node("HudLayer/HofHud")
	var m := ScreenShell.metrics(hud.get_viewport())
	var f: float = m["f"]
	var floor_px: float = m["floor_px"]
	var kopf: VBoxContainer = hud.get_node("KopfBox")
	assert_almost(kopf.anchor_left, 0.5, 1e-4, "Kopfzeile ankert mittig")
	assert_almost(kopf.anchor_top, 0.0, 1e-4, "…an der Oberkante")
	assert_almost(kopf.offset_top, 24.0 + ScreenShell.EDGE_Y * f, 0.5, "…unter der Notch")
	assert_eq(kopf.get_child_count(), 2, "Titel + Stadt-Chip")
	var fuss: HBoxContainer = hud.get_node("FussBox")
	assert_almost(fuss.anchor_left, 0.5, 1e-4, "Cluster ankert mittig")
	assert_almost(fuss.anchor_bottom, 1.0, 1e-4, "…an der Unterkante")
	assert_almost(fuss.offset_bottom, -(34.0 + 16.0 * f), 0.5, "…über dem Home-Indicator")
	# W19: die Entdecker-Karte ist der vierte Cluster-Knopf (gewollt).
	assert_eq(fuss.get_child_count(), 4, "Ausreiten · Galopp · Mehrspieler · Karte")
	await wait_frames(1)
	assert_almost(fuss.global_position.x + fuss.size.x / 2.0, 640.0, 2.0, "Cluster mittig")
	assert_almost(kopf.global_position.x + kopf.size.x / 2.0, 640.0, 2.0, "Kopfzeile mittig")
	var knoepfe: Array[Button] = [
		szene._stadt_knopf,
		szene._ausritt_knopf,
		szene._galopp_knopf,
		szene._mp_knopf,
		szene._karte_knopf,
	]
	for knopf in knoepfe:
		assert_true(knopf is SquishButton, "%s squisht (Audio-Grammatik)" % knopf.text)
		assert_true(
			knopf.custom_minimum_size.x >= floor_px - 0.5, "'%s' erreicht Floor-X" % knopf.text
		)
		assert_true(
			knopf.custom_minimum_size.y >= floor_px - 0.5, "'%s' erreicht Floor-Y" % knopf.text
		)
	assert_eq(
		szene._mp_knopf.text,
		I18nService.t("ranch_mp.menu.hof_knopf"),
		"MP-Einstieg trägt den neuen String"
	)
	assert_eq(szene._karte_knopf.get_parent(), fuss, "Karte-Knopf gehört zum Daumen-Cluster")
	assert_eq(
		szene._karte_knopf.text,
		I18nService.t("rkarte.knopf"),
		"Karten-Einstieg trägt den rkarte-String"
	)
	# Rotation hoch: der Resize-Pass rechnet Insets/Floor/f neu (ohne Notch).
	# Das Projekt-Stretch (canvas_items+expand) hält die Canvas-Kurzkante
	# bei ≥ 1280 — die Mitte kommt darum aus der ECHTEN Canvas, nicht 720/2.
	UiScale.insets_override = Rect2()
	tree.root.size = Vector2i(720, 1280)
	tree.root.size_changed.emit()
	await wait_frames(2)
	var m2 := ScreenShell.metrics(hud.get_viewport())
	var canvas2: Vector2 = m2["canvas"]
	assert_almost(fuss.offset_bottom, -16.0 * float(m2["f"]), 0.5, "Resize-Pass zieht nach")
	await wait_frames(1)
	assert_almost(
		fuss.global_position.x + fuss.size.x / 2.0, canvas2.x / 2.0, 2.0, "Cluster bleibt mittig"
	)
	szene.queue_free()
	await _unpin()


## G1 §1.7 [hoch] „kein Spiel-Einstieg vorhanden“: der Mehrspieler-Knopf am
## Hof öffnet den Hub als PanelSheet (offline höflich, Dienst unter /root).
func test_hof_mp_knopf_oeffnet_hub_sheet() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	var szene: RanchHofScene = (load(HOF_SZENE) as PackedScene).instantiate()
	szene.game_state_override = gs
	szene.stunde_override = 13.0
	tree.root.add_child(szene)
	await wait_frames(4)
	assert_true(szene.get_node_or_null("RmpHub") == null, "Hub lädt LAZY (erst auf Tipp)")
	szene._mp_knopf.pressed.emit()
	await wait_frames(2)
	var hub: RmpHub = szene.get_node_or_null("RmpHub")
	assert_true(hub != null, "Hub hängt nach dem Tipp an der Hof-Szene")
	var sheet := hub.offenes_sheet()
	assert_true(sheet != null and sheet.is_open(), "Menü-Sheet ist offen")
	assert_true(
		_enthaelt(_alle_labels(sheet), I18nService.t("ranch_mp.menu.title")), "Hub-Titel sichtbar"
	)
	assert_true(
		_enthaelt(_alle_labels(sheet), I18nService.t("ranch_mp.menu.offline_hint")),
		"offline höflich erklärt"
	)
	PanelStack.clear()
	szene.queue_free()
	var dienst := tree.root.get_node_or_null("RanchMpDienst")
	if dienst != null:
		dienst.queue_free()
	await _unpin()


# ------------------------------------------------------------ RmpHub-Strecke


## Die PanelSheet-Strecke des Hubs: Menü → Bestenliste (Knopf) → Lobby
## (session_ready) → Ende (session_ended schließt + meldet ehrlich).
func test_rmp_hub_strecke_menu_bestenliste_lobby_ende() -> void:
	await _pin(Vector2i(1280, 720))
	var szene := TraegerSzene.new()
	tree.root.add_child(szene)
	var hub := RmpHub.attach_to(szene)
	await wait_frames(1)
	assert_eq(RmpHub.attach_to(szene), hub, "attach_to ist idempotent")
	var service := RmpHub.dienst(tree)
	assert_eq(RmpHub.dienst(tree), service, "EIN geteilter Dienst unter /root")
	hub.oeffne()
	await wait_frames(2)
	var menu_sheet := hub.offenes_sheet()
	assert_true(menu_sheet != null and menu_sheet.is_open(), "oeffne() zeigt das Menü-Sheet")
	var menu := _finde_menu(menu_sheet)
	assert_true(menu != null, "RmpMenuPanel liegt im Sheet")
	menu.leaderboard_pressed.emit()
	await wait_frames(2)
	var besten_sheet := hub.offenes_sheet()
	assert_true(
		besten_sheet != null and besten_sheet != menu_sheet, "Bestenliste übernimmt den Platz"
	)
	assert_true(
		_enthaelt(_alle_labels(besten_sheet), I18nService.t("ranch_mp.besten.titel")),
		"Bestenlisten-Titel sichtbar"
	)
	assert_true(
		_enthaelt(_alle_labels(besten_sheet), I18nService.t("ranch_mp.menu.offline_hint")),
		"offline: höflicher Hinweis statt Fehler"
	)
	service.session_ready.emit({})
	await wait_frames(2)
	var lobby_sheet := hub.offenes_sheet()
	assert_true(lobby_sheet != null and lobby_sheet != besten_sheet, "Lobby übernimmt den Platz")
	assert_true(_enthaelt(_alle_labels(lobby_sheet), "Lobby"), "Lobby-Titel sichtbar")
	service.session_ended.emit({})
	await wait_frames(2)
	assert_true(hub.offenes_sheet() == null, "Ende schließt alle Sheets")
	assert_true(
		szene.meldungen.has(I18nService.t("ranch_mp.lobby.beendet")), "Ende wird ehrlich gemeldet"
	)
	PanelStack.clear()
	szene.queue_free()
	service.queue_free()
	await _unpin()


## G4-Klemmung: die MP-Panels ersetzen ihre Fixbreiten (440/420/460 px)
## durch card_width/card_max_height. Getestet im schmalen SubViewport —
## das Projekt-Stretch hält die ROOT-Canvas-Kurzkante bei ≥ 1280, dort
## klemmt nie; in kleinen Viewports (Minigame-Host o. Ä.) muss es klemmen.
func test_mp_panels_klemmen_in_schmalen_viewports() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 640)
	tree.root.add_child(vp)
	await wait_frames(1)
	var m := ScreenShell.metrics(vp)
	var deckel := 360.0 - 2.0 * PanelSheetLayout.MARGIN * float(m["f"])
	var panels: Array[Control] = [RmpMenuPanel.new(), RmpLobbyPanel.new(), RmpBesuchPanel.new()]
	for panel in panels:
		vp.add_child(panel)
		await wait_frames(1)
		assert_true(
			panel.custom_minimum_size.x <= deckel + 0.5,
			"Panel klemmt auf die Safe-Breite (%.0f px)" % panel.custom_minimum_size.x
		)
		assert_true(panel.custom_minimum_size.x > 200.0, "…bleibt aber brauchbar breit")
		panel.queue_free()
	var besten := RmpLeaderboardPanel.new()
	vp.add_child(besten)
	await wait_frames(1)
	assert_true(besten.custom_minimum_size.x <= deckel + 0.5, "Bestenliste klemmt die Breite")
	assert_true(
		besten.custom_minimum_size.y <= ScreenShell.card_max_height(m) + 0.5,
		"…und deckelt die Höhe"
	)
	besten.queue_free()
	vp.queue_free()


# ----------------------------------------------------------------- RcompHud


## G1 §1.3 [hoch]: Kopf-Panel MITTIG OBEN (statt Ecke), Schriften/Offsets
## skalieren zentral über UiScale — auch nach Rotation/Retina-Simulation.
func test_comp_hud_kopf_center_top_und_uiscale_pass() -> void:
	await _pin(Vector2i(1280, 720))
	var hud := RcompHud.new()
	tree.root.add_child(hud)
	await wait_frames(1)
	var f := UiScale.for_viewport(hud.get_viewport())
	var kopf: PanelContainer = hud._kopf_panel
	assert_almost(kopf.anchor_left, 0.5, 1e-4, "Kopf-Panel ankert CENTER_TOP (nicht Ecke)")
	assert_almost(kopf.anchor_right, 0.5, 1e-4)
	assert_almost(kopf.anchor_bottom, 0.0, 1e-4)
	assert_almost(kopf.position.y, 12.0 * f, 0.5, "skalierter Kopf-Abstand")
	await wait_frames(1)
	assert_almost(kopf.global_position.x + kopf.size.x / 2.0, 640.0, 2.0, "Kopf-Panel mittig")
	assert_eq(hud._zeit_label.get_theme_font_size("font_size"), int(22.0 * f), "Zeit-Schrift ×f")
	# Schau-Kür-Elemente nachrüsten (Disziplin „schau“) + Skalierungs-Pass.
	hud._baue_schau()
	hud._wende_skalierung_an()
	await wait_frames(1)
	var btn: Button = hud._schau_btn
	assert_true(btn is SquishButton, "Jetzt!-Knopf squisht (Audio-Grammatik)")
	assert_eq(btn.custom_minimum_size, Vector2(190.0, 84.0) * f, "große Tippfläche ×f")
	assert_almost(btn.anchor_top, 1.0, 1e-4, "Jetzt!-Knopf ankert unten")
	assert_almost(btn.anchor_left, 0.5, 1e-4, "…mittig (Daumenzone)")
	assert_almost(btn.position.y + btn.size.y, 720.0 - 130.0 * f, 2.0, "…über der Unterkante")
	assert_almost(btn.position.x + btn.size.x / 2.0, 640.0, 2.0, "…horizontal zentriert")
	# Retina-Simulation ×2 + Rotation hoch: alles zieht mit f nach.
	UiScale.screen_scale_override = 2.0
	tree.root.size = Vector2i(720, 1280)
	tree.root.size_changed.emit()
	await wait_frames(2)
	var f2 := UiScale.for_viewport(hud.get_viewport())
	assert_true(f2 > 1.5, "Retina-Faktor greift (f=%.2f)" % f2)
	assert_eq(
		hud._zeit_label.get_theme_font_size("font_size"), int(22.0 * f2), "Schrift skaliert nach"
	)
	assert_eq(btn.custom_minimum_size, Vector2(190.0, 84.0) * f2, "Tippfläche skaliert nach")
	assert_almost(kopf.position.y, 12.0 * f2, 0.5, "Offset skaliert nach")
	UiScale.screen_scale_override = 0.0
	hud.queue_free()
	await _unpin()


# --------------------------------------------------------------- Event-Props


## G1 §1.2 [hoch]: Requisiten-Tipps fangen im physischen 44-pt-Radius
## (Screen-Space) — ein Vorbei-Tipp trifft, pro Frame höchstens EIN Fang,
## außerhalb des Radius passiert nichts.
func test_event_requisiten_fangen_im_44pt_radius() -> void:
	await _pin(Vector2i(1280, 720))
	var szene := TraegerSzene.new()
	tree.root.add_child(szene)
	var cam := Camera3D.new()
	szene.add_child(cam)
	cam.look_at_from_position(
		Vector3(0.0, 1.4, 0.0), szene.event_anker() + Vector3(0.0, 1.4, 0.0), Vector3.UP
	)
	cam.current = true
	var host := RanchEventHost.new()
	host.game_state_override = FakeGameState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	host.rng_override = rng
	szene.add_child(host)
	host.setup(szene)
	host.start({"id": "heudieb", "szene_setup": "ranch_heudieb", "props": 2})
	await wait_frames(2)
	assert_eq(host._tap_handler.size(), 2, "zwei Krähen stehen auf dem Heu")
	var kraehen: Array = host._tap_handler.keys()
	var s0 := cam.unproject_position((kraehen[0] as Node3D).global_position)
	var s1 := cam.unproject_position((kraehen[1] as Node3D).global_position)
	var radius := RanchEventHost.TAP_RADIUS_PT * UiScale.touch_px_per_pt(host.get_viewport())
	# Vorbei-Tipp: 60 % des Radius NEBEN Krähe 0 (von Krähe 1 weg gerichtet).
	host._unhandled_input(_klick(s0 + (s0 - s1).normalized() * radius * 0.6))
	assert_eq(host._tap_handler.size(), 1, "Fangradius fängt den Vorbei-Tipp")
	assert_true(szene.meldungen.has(I18nService.t("revents.heudieb.kraah")), "Krähe kräht")
	# Frame-Dedupe (Maus-Emulation liefert Klick UND Touch): gleicher Frame
	# fängt kein zweites Mal — auch nicht bei Direkt-Treffer.
	var rest: Node3D = host._tap_handler.keys()[0]
	var s_rest := cam.unproject_position(rest.global_position)
	host._unhandled_input(_klick(s_rest))
	assert_eq(host._tap_handler.size(), 1, "höchstens EIN Fang pro Frame")
	await wait_frames(1)
	host._unhandled_input(_klick(s_rest + Vector2(0.0, radius * 2.0)))
	assert_eq(host._tap_handler.size(), 1, "außerhalb des Radius passiert nichts")
	host._clear_props()
	szene.queue_free()
	await _unpin()


# ------------------------------------------------------------------- Turnier


## G1 §1.4: der „Fertig“-Knopf des Turnier-Menüs sitzt mittig (Daumenzone,
## SquishButton) statt rechts außen am Rand.
func test_turnier_fertig_knopf_mittig() -> void:
	var game: Variant = (load(TURNIER_SKRIPT) as GDScript).new()
	var spalte := VBoxContainer.new()
	tree.root.add_child(spalte)
	game._menu_fuss(spalte)
	var fertig: Button = spalte.get_child(0)
	assert_true(fertig is SquishButton, "Fertig squisht (Audio-Grammatik)")
	assert_eq(
		fertig.size_flags_horizontal,
		Control.SIZE_SHRINK_CENTER,
		"Fertig sitzt mittig in der Spalte"
	)
	assert_true(fertig.custom_minimum_size.y >= 44.0, "Touch-Floor in Design-px")
	spalte.queue_free()
	game.free()


## G1 §1.4: das Mitte-Panel (Einweisung/Ergebnis) deckelt auf 80 % der
## Sicht — Überschuss scrollt; der Deckel folgt jeder Drehung (apply_view).
func test_turnier_mitte_panel_deckelt_und_scrollt() -> void:
	var game: Variant = (load(TURNIER_SKRIPT) as GDScript).new()
	var wurzel := Control.new()
	tree.root.add_child(wurzel)
	game.view_size = Vector2(720.0, 1280.0)
	var spalte: VBoxContainer = game._mitte_panel(wurzel)
	for i in 60:
		var zeile := Label.new()
		zeile.text = "Zeile %d" % i
		spalte.add_child(zeile)
	await wait_frames(2)
	var scroll: ScrollContainer = game._mitte_scroll
	var deckel := 1280.0 * 0.8 - 32.0
	assert_true(
		spalte.get_combined_minimum_size().y > deckel, "Testaufbau: Inhalt sprengt den Deckel"
	)
	assert_almost(scroll.custom_minimum_size.y, deckel, 1.0, "Scroll-Fenster deckelt auf 80 %")
	game.apply_view(Vector2(1280.0, 720.0))
	assert_almost(scroll.custom_minimum_size.y, 720.0 * 0.8 - 32.0, 1.0, "Deckel folgt der Drehung")
	wurzel.queue_free()
	game.free()


# ---------------------------------------------------------------- Helfer


func _klick(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


func _finde_menu(wurzel: Node) -> RmpMenuPanel:
	if wurzel is RmpMenuPanel:
		return wurzel
	for kind in wurzel.get_children():
		var gefunden := _finde_menu(kind)
		if gefunden != null:
			return gefunden
	return null


func _alle_labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node is Label:
		out.append((node as Label).text)
	for kind in node.get_children():
		out.append_array(_alle_labels(kind))
	return out


func _enthaelt(texte: Array[String], teil: String) -> bool:
	for text in texte:
		if text.contains(teil):
			return true
	return false

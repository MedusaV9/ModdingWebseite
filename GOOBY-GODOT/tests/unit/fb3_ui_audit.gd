extends SceneTree
## FB3-UI-Audit (KEIN Test — kein test_-Präfix): bootet das ECHTE Spiel
## (home_entry inkl. Autoloads/Router/HUD), öffnet JEDEN Haupt-Screen/
## Panel/Overlay in 4 Geräteformaten (iPhone quer ×2, iPhone hoch, iPad
## quer) MIT simulierter Notch/Home-Indicator (UiScale.insets_override)
## und prüft automatisiert:
##   - safe_area: ragt ein Bedienelement aus dem sicheren Bereich?
##   - tap: Tippfläche ≥ 44 pt (physisch, über screen_scale_override)?
##   - overlap: überlappen sich Bedienelemente?
##   - offscreen: läuft ein Element aus dem Canvas?
## Befunde → FB3_OUT/befunde.md (+ .json), Screenshots pro Screen/Format.
## Braucht einen echten Renderer:
##   FB3_OUT=/tmp/gooby-godot/artifacts/FB3/audit xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/fb3_ui_audit.gd

const OUT_ENV := "FB3_OUT"
## Optional: Nur bestimmte Formate prüfen (kommagetrennte Labels) — für
## schnelle Nach-Fix-Verifikation eines einzelnen Formats.
const FORMATS_ENV := "FB3_FORMATS"
const DEFAULT_OUT := "/tmp/gooby-godot/artifacts/FB3/audit"
const SETTLE_FRAMES := 20
const TRAVEL_TIMEOUT_MS := 20_000
## Tippflächen-Minimum in Punkten (Apple HIG).
const MIN_TAP_PT := 44.0
const TAP_TOLERANCE_PT := 0.5

## [label, Fenster-px, screen_scale, insets in PUNKTEN {l,t,r,b}]
const SIZES: Array = [
	["quer_2556x1179", Vector2i(2556, 1179), 3.0, [59.0, 0.0, 59.0, 21.0]],
	["quer_1792x828", Vector2i(1792, 828), 2.0, [48.0, 0.0, 48.0, 21.0]],
	["hoch_1179x2556", Vector2i(1179, 2556), 3.0, [0.0, 59.0, 0.0, 34.0]],
	["ipad_2360x1640", Vector2i(2360, 1640), 2.0, [0.0, 24.0, 0.0, 20.0]],
]

## Screens mit EIGENER Spalten-Basisbreite (Grid-/Zweispalten-Layouts der
## W16-Welle 2): der content_mitte-Breiten-Deckel muss deren base statt
## AcTokens.CONTENT_MAX_WIDTH ansetzen. Die Werte kommen DIREKT aus den
## Screen-Konstanten (kein Drift). content_width klemmt ohnehin härter
## (Safe − 2×PanelSheetLayout.MARGIN×f, 24 > CONTENT_EDGE_X 16) — bleibt
## ein Breiten-Befund, ist es ein ECHTER Inhalts-Überlauf der Spalte.
const COLUMN_BASE_BY_SCREEN := {
	"05_arcade": ArcadeScreen.CONTENT_BASE_WIDTH,
	"05_album": AlbumScreen.SPALTE_BASIS,
	"05_wardrobe": WardrobeScreen.SPALTE_BASIS,
	"05_ikea": IkeaScreen.GRID_BASE,
	"05_gestalten": CustomizeScreen.SPALTE_BASIS,
}

var _out_dir := DEFAULT_OUT
var _router: Node
var _entry: Node
var _hud: Control
var _findings: Array[Dictionary] = []
var _screens_checked := 0
var _formats_run := 0
## Aktueller Format-Kontext.
var _label := ""
var _canvas := Vector2.ZERO
var _safe_rect := Rect2()
var _px_per_pt := 1.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment(OUT_ENV)
	if env != "":
		_out_dir = env
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var gs := root.get_node("/root/GameState")
	gs.set_value("onboarding.done", true)
	var app := root.get_node_or_null("/root/AppSettings")
	if app != null and app.has_method("set_setting"):
		app.set_setting("hints.hud_actions_seen", true)
	_router = root.get_node("/root/SceneRouter")
	_entry = (load("res://scenes/home/home_entry.tscn") as PackedScene).instantiate()
	root.add_child(_entry)
	await _wait_travel_done()
	_hud = _find_hud()
	if _hud == null:
		print("FB3-Audit: HUD nicht gefunden — Abbruch.")
		quit(1)
		return
	var only := OS.get_environment(FORMATS_ENV)
	for size_info: Array in SIZES:
		if only != "" and not String(size_info[0]) in only.split(","):
			continue
		await _audit_size(size_info)
	_write_report()
	print(
		(
			"FB3-Audit fertig: %d Screens geprüft, %d Befunde -> %s"
			% [_screens_checked, _findings.size(), _out_dir]
		)
	)
	quit(0)


func _audit_size(size_info: Array) -> void:
	_formats_run += 1
	_label = String(size_info[0])
	var win_size: Vector2i = size_info[1]
	var scale: float = size_info[2]
	var insets_pt: Array = size_info[3]
	UiScale.screen_scale_override = scale
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(
		Vector2i(maxi((screen.x - win_size.x) / 2, 0), maxi((screen.y - win_size.y) / 2, 0))
	)
	DisplayServer.window_set_size(win_size)
	root.size = win_size
	await _settle()
	_canvas = Vector2(root.get_visible_rect().size)
	var pt_short := minf(float(win_size.x), float(win_size.y)) / scale
	_px_per_pt = minf(_canvas.x, _canvas.y) / pt_short
	var l := float(insets_pt[0]) * _px_per_pt
	var t := float(insets_pt[1]) * _px_per_pt
	var r := float(insets_pt[2]) * _px_per_pt
	var b := float(insets_pt[3]) * _px_per_pt
	_safe_rect = Rect2(l, t, _canvas.x - l - r, _canvas.y - t - b)
	UiScale.insets_override = Rect2(_safe_rect)
	# Nachtreten: Screens hören auf size_changed — Insets kamen NACH dem
	# Resize, also einmal manuell neu layouten lassen.
	root.size_changed.emit()
	await _settle()

	await _goto_home()
	await _snap_and_check("01_home_hud")
	await _audit_status_sheet()
	await _audit_settings()
	for screen_info: Array in [
		["arcade", &"arcade"],
		["album", &"album"],
		# W14/UISCREENS-A: „profil“ zeigte den SOCIAL-Screen (Stand vor der
		# REST-1-Fehlrouten-Korrektur) — jetzt den echten Profil-Screen
		# auditieren; Social bleibt als eigener Eintrag abgedeckt.
		["profil", &"profil"],
		["social", &"social"],
		["friends", &"friends"],
		["wardrobe", &"wardrobe"],
		["ikea", &"ikea"],
		["gestalten", &"gestalten"],
		# W16/G4: Routen-Lücke des Spalten-Rollouts (G2-Bericht §4.5) — die
		# in G2 umgestellten Screens erfolge/galerie/postkarten/codes/dlc
		# lagen bisher NICHT in den Audit-Routen und waren nur durch den
		# Quelltext-Scan gesichert; content_mitte prüft sie jetzt live.
		["erfolge", &"erfolge"],
		["galerie", &"galerie"],
		["postkarten", &"postkarten"],
		["codes", &"codes"],
		["dlc", &"dlc"],
	]:
		await _audit_route(String(screen_info[0]), screen_info[1])
	await _audit_minigame_flow()
	await _goto_home()
	UiScale.insets_override = Rect2()


func _audit_status_sheet() -> void:
	if _hud.has_method("open_status_sheet"):
		_hud.open_status_sheet()
		await _settle()
		await _snap_and_check("02_status_sheet")
		var sheet: Variant = _hud.get("_status_sheet")
		if sheet is Node and (sheet as Node).has_method("close"):
			sheet.close()
		await _settle()


func _audit_settings() -> void:
	_hud.emit_signal("settings_pressed")
	await _settle()
	await _snap_and_check("03_settings")
	var settings: Variant = _entry.get("_settings")
	if settings is Node:
		var news_btn := _find_button_by_name(settings as Node, "NewsButton")
		if news_btn != null:
			news_btn.pressed.emit()
			await _settle()
			await _snap_and_check("04_patchnotes")
			var news_panel: Variant = (settings as Node).get("_news_panel")
			if news_panel is Node and (news_panel as Node).has_method("close"):
				news_panel.close()
		var back := _find_button_by_name(settings as Node, "BackButton")
		if back != null:
			back.pressed.emit()
		await _settle()


func _audit_route(label: String, target: StringName) -> void:
	_register_all_routes()
	_router.goto(target, {})
	await _wait_travel_done()
	await _snap_and_check("05_%s" % label)


## Minigame-Kette: Pregame → Host (Countdown → laufendes Spiel → Pause-
## Modal → Weiter-Countdown → erzwungenes Rundenende → Results).
func _audit_minigame_flow() -> void:
	_refill_energy()
	_register_all_routes()
	_router.goto(&"mg_pregame", {"game_id": "teaParty"})
	await _wait_travel_done()
	await _snap_and_check("06_pregame")
	_router.goto(&"mg_host", {"game_id": "teaParty", "seed": 7})
	await _wait_travel_done()
	var host: Node = _router.get_current_scene()
	if host == null or not (host is MinigameHost):
		_add_finding("mg_host", "flow", "-", "Host nicht erreicht")
		return
	var ok := await _wait_for(
		func() -> bool: return not (host.get("_pause_button") as Button).disabled, 8000
	)
	if not ok:
		_add_finding("mg_host", "flow", "-", "Countdown wurde nie fertig (GO fehlt)")
		return
	await _snap_and_check("07_mg_running")
	host.call("_on_pause_pressed")
	await _settle()
	await _snap_and_check("08_mg_pause_modal")
	var modal: Variant = host.get("_pause_modal")
	if modal is MinigamePauseModal:
		_check_pause_compact(modal as MinigamePauseModal)
	host.set("resume_step_sec", 0.05)
	host.call("_on_resume_pressed")
	await _wait_for(func() -> bool: return not (host.get("_pause_button") as Button).disabled, 6000)
	var game: Variant = host.get("_game")
	if game is MinigameBase and (game as MinigameBase).ctx != null:
		(game as MinigameBase).ctx.report_end({"score": 123})
	var results: Variant = host.get("_results")
	await _wait_for(
		func() -> bool: return results is Control and (results as Control).visible, 6000
	)
	await _settle()
	await _snap_and_check("09_mg_results")


## Das Pause-Modal muss KOMPAKT und MITTIG sein (nie Vollfläche).
func _check_pause_compact(modal: MinigamePauseModal) -> void:
	var card: Variant = modal.get("_card")
	if not (card is Control):
		_add_finding("mg_pause", "pause", "-", "Karte fehlt")
		return
	var rect := (card as Control).get_global_rect()
	if rect.size.x > _canvas.x * 0.62:
		_add_finding(
			"mg_pause",
			"pause",
			"PauseCard",
			"Karte zu breit: %.0f px (> 62%% von %.0f)" % [rect.size.x, _canvas.x]
		)
	var center := rect.get_center()
	var safe_center := _safe_rect.get_center()
	if center.distance_to(safe_center) > _canvas.y * 0.08:
		_add_finding(
			"mg_pause",
			"pause",
			"PauseCard",
			"Karte nicht mittig: Zentrum %s vs. Safe-Zentrum %s" % [center, safe_center]
		)


func _register_all_routes() -> void:
	ArcadeScreen.register_routes()
	AlbumScreen.register_routes()
	ProfilScreen.register_routes()
	SocialScreen.register_routes()
	FriendsScreen.register_routes()
	WardrobeScreen.register_routes()
	IkeaScreen.register_routes()
	CustomizeScreen.register_routes()
	AchievementsScreen.register_routes()
	GalerieScreen.register_routes()
	PostkartenScreen.register_routes()
	CodesScreen.register_routes()
	DlcScreen.register_routes()


func _goto_home() -> void:
	PanelStack.clear()
	var routes: Variant = _router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		_router.goto(&"home", {})
		await _wait_travel_done()


func _refill_energy() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("update"):
		return
	gs.update(
		func(state: Dictionary) -> void:
			var gooby: Variant = state.get("gooby")
			if gooby is Dictionary and (gooby as Dictionary).get("stats") is Dictionary:
				((gooby as Dictionary)["stats"] as Dictionary)["energy"] = 100.0
	)


## ---- Checks -------------------------------------------------------------


func _snap_and_check(screen: String) -> void:
	await _settle()
	_screens_checked += 1
	await _snap("%s_%s.png" % [_label, screen])
	_run_checks(screen)


func _run_checks(screen: String) -> void:
	var controls := _interactive_controls()
	for ctl in controls:
		var rect := _effective_rect(ctl)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var name := _describe(ctl)
		var canvas_rect := Rect2(Vector2.ZERO, _canvas)
		if not canvas_rect.grow(1.0).encloses(rect):
			_add_finding(screen, "offscreen", name, "läuft aus dem Canvas: %s" % rect)
		elif not _safe_rect.grow(2.0).encloses(rect):
			_add_finding(screen, "safe_area", name, "ragt aus dem sicheren Bereich: %s" % rect)
		if ctl is Button and not (ctl as Button).disabled:
			# Tippfläche = ECHTE Knopfgröße (ungeclippt): teilweise aus dem
			# Scroll-Fenster gescrollte Kacheln sind kein Größen-Verstoß.
			var own := ctl.get_global_rect()
			var short_pt := minf(own.size.x, own.size.y) / _px_per_pt
			if short_pt < MIN_TAP_PT - TAP_TOLERANCE_PT:
				_add_finding(
					screen, "tap", name, "Tippfläche %.1f pt < %d pt" % [short_pt, MIN_TAP_PT]
				)
	for i in controls.size():
		if not (controls[i] is Button):
			continue
		for j in range(i + 1, controls.size()):
			if not (controls[j] is Button):
				continue
			if _is_related(controls[i], controls[j]):
				continue
			var a := _effective_rect(controls[i])
			var b := _effective_rect(controls[j])
			var overlap := a.intersection(b)
			if overlap.size.x > 4.0 and overlap.size.y > 4.0:
				_add_finding(
					screen,
					"overlap",
					"%s × %s" % [_describe(controls[i]), _describe(controls[j])],
					"Überlappung %s" % overlap
				)
	_check_content_column(screen, controls)


## Inhaltsspalte W16, Kategorie content_mitte: markierte Spalten-Container
## (Meta ScreenShell.META_CONTENT_COLUMN) müssen mittig im SAFE-Rechteck
## sitzen (±2 px) und den Breiten-Deckel einhalten; jeder sichtbare Button
## des Screens (außer HUD-/Toast-/Bubble-/PanelSheet-Ebenen) muss in einer
## Spalte grow(4) liegen. Screens OHNE Meta-Flag überspringen die Kategorie
## (HUD-Cockpit, Sheets und Minigames zentrieren bewusst nicht).
func _check_content_column(screen: String, controls: Array[Control]) -> void:
	var columns := _content_columns()
	if columns.is_empty():
		return
	var f := UiScale.for_viewport(root)
	var base := float(COLUMN_BASE_BY_SCREEN.get(screen, AcTokens.CONTENT_MAX_WIDTH))
	var max_w := minf(base * f, _safe_rect.size.x - 2.0 * AcTokens.CONTENT_EDGE_X * f)
	for col in columns:
		var rect := col.get_global_rect()
		var delta := absf(rect.get_center().x - _safe_rect.get_center().x)
		if delta > 2.0:
			_add_finding(
				screen,
				"content_mitte",
				_describe(col),
				"Spalte nicht im Safe-Zentrum: Abweichung %.1f px" % delta
			)
		if rect.size.x > max_w + 2.0:
			_add_finding(
				screen,
				"content_mitte",
				_describe(col),
				"Spalte zu breit: %.0f px (Deckel %.0f px)" % [rect.size.x, max_w]
			)
	for ctl in controls:
		if not (ctl is Button) or _in_overlay_layer(ctl):
			continue
		var rect := _effective_rect(ctl)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var drin := false
		for col in columns:
			if col.get_global_rect().grow(4.0).encloses(rect):
				drin = true
				break
		if not drin:
			_add_finding(
				screen, "content_mitte", _describe(ctl), "Button außerhalb der Spalte: %s" % rect
			)


## Sichtbare Container mit dem W16-Spalten-Meta-Flag (Hauptviewport).
func _content_columns() -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is SubViewport and node != root:
			continue
		stack.append_array(node.get_children())
		if not (node is Control):
			continue
		var ctl := node as Control
		if ctl.is_visible_in_tree() and ctl.has_meta(ScreenShell.META_CONTENT_COLUMN):
			out.append(ctl)
	return out


## Overlay-Ebenen, deren Knöpfe NICHT in die Spalte gehören (HUD-Daumen-
## Kanten, Toasts, Sprechblasen, Bottom-Sheets, Hinweis-Karten der
## HUD-Kopf-Zone — W14-/REST-2-Verträge).
func _in_overlay_layer(ctl: Control) -> bool:
	var node: Node = ctl
	while node != null:
		var overlay := (
			node is Hud
			or node is ToastLayer
			or node is AcBubble
			or node is PanelSheet
			or node is OnboardingGuide
			or node is WhatsNextHint
		)
		if overlay:
			return true
		node = node.get_parent()
	return false


## Sichtbare Bedienelemente des HAUPT-Viewports (SubViewport-Inhalte haben
## eigene Koordinatenräume und gehören den Spielen, nicht dem UI-Audit).
func _interactive_controls() -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is SubViewport and node != root:
			continue
		stack.append_array(node.get_children())
		if not (node is Control):
			continue
		var ctl := node as Control
		if not ctl.is_visible_in_tree():
			continue
		if ctl is Button or ctl is LineEdit:
			out.append(ctl)
	return out


## Rect nach Clipping durch Ahnen (ScrollContainer/clip_contents) — gescrollte
## Inhalte unterhalb der Falte sind KEIN Safe-Area-Befund.
func _effective_rect(ctl: Control) -> Rect2:
	var rect := ctl.get_global_rect()
	var node: Node = ctl.get_parent()
	while node != null and node is Control:
		var parent := node as Control
		if parent.clip_contents or parent is ScrollContainer:
			rect = rect.intersection(parent.get_global_rect())
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				return Rect2()
		node = parent.get_parent()
	return rect


func _is_related(a: Node, b: Node) -> bool:
	return a.is_ancestor_of(b) or b.is_ancestor_of(a)


func _describe(node: Node) -> String:
	var label := node.name
	if node is Button and not (node as Button).text.is_empty():
		label = "%s(%s)" % [node.name, (node as Button).text.left(18)]
	return String(label)


func _add_finding(screen: String, check: String, node: String, detail: String) -> void:
	_findings.append(
		{"format": _label, "screen": screen, "check": check, "node": node, "detail": detail}
	)


func _write_report() -> void:
	var json := FileAccess.open("%s/befunde.json" % _out_dir, FileAccess.WRITE)
	json.store_string(JSON.stringify(_findings, "\t"))
	json.close()
	var md := FileAccess.open("%s/befunde.md" % _out_dir, FileAccess.WRITE)
	md.store_line("# FB3-UI-Audit — Befunde")
	md.store_line("")
	# Durch die ECHTE Formatzahl teilen — FB3_FORMATS-Subset-Läufe (schnelle
	# Nach-Fix-Verifikation) bekämen sonst eine falsche Screens-Zahl.
	md.store_line(
		(
			"Screens geprüft: %d × %d Formate — Befunde: %d"
			% [_screens_checked / maxi(_formats_run, 1), _formats_run, _findings.size()]
		)
	)
	md.store_line("")
	md.store_line("| Format | Screen | Check | Element | Detail |")
	md.store_line("|---|---|---|---|---|")
	for f in _findings:
		md.store_line(
			(
				"| %s | %s | %s | %s | %s |"
				% [f["format"], f["screen"], f["check"], f["node"], f["detail"]]
			)
		)
	md.close()


## ---- Helfer (Muster aus screenshot_fix1.gd) ------------------------------


func _wait_travel_done() -> void:
	var deadline := Time.get_ticks_msec() + TRAVEL_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _router != null and not _router.is_busy() and _router.get_current_scene() != null:
			break
	await _settle()


func _wait_for(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false


func _find_hud() -> Control:
	var huds := root.find_children("*", "Control", true, false).filter(
		func(node: Node) -> bool: return node is Hud
	)
	return huds[0] if not huds.is_empty() else null


func _find_button_by_name(from: Node, btn_name: String) -> Button:
	var found := from.find_children(btn_name, "Button", true, false)
	return found[0] if not found.is_empty() else null


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame


func _snap(file: String) -> void:
	for node: Control in root.find_children("SafeModeBanner", "Control", true, false):
		node.visible = false
	# Spontane Gooby-Gesprächs-Chips (SeeleRunner würfelt Betreten-Momente,
	# gooby_gespraech.gd) sind transiente Dialog-Overlays, keine Screen-UI —
	# sichtbar machten sie Läufe nichtdeterministisch rot (Overlap-/Spalten-
	# Befunde je nach Würfelglück). Ausblenden wie den SafeModeBanner; die
	# Checks laufen NACH dem Snap und sehen nur Sichtbares.
	for node: Control in root.find_children("GoobyGespraechChips", "Control", true, false):
		node.visible = false
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, file])
	print("  gespeichert: %s" % file)

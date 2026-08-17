extends SceneTree
## FB3-UI-Audit (KEIN Test — kein test_-Präfix): bootet das ECHTE Spiel
## (home_entry inkl. Autoloads/Router/HUD), öffnet JEDEN Haupt-Screen/
## Panel/Overlay in 6 Geräteformaten (iPhone quer ×3, iPhone hoch ×2,
## iPad quer — Leitformat: iPhone 17 Pro Max quer, G7/P57 User-Wunsch)
## MIT simulierter Notch/Home-Indicator (UiScale.insets_override)
## — seit W17/G5 P33 auch die G4-Domänen ohne Router-Route (Baumodus-
## Dock, IGohbie-Telefon, Radio-Sheet, Ranch-MP-Hub, Reise-App,
## Onboarding, Level-Selects; 34 Zustände je Format) — und prüft
## automatisiert:
##   - safe_area: ragt ein Bedienelement aus dem sicheren Bereich?
##   - tap: Tippfläche ≥ 44 pt (physisch, über screen_scale_override)?
##   - overlap: überlappen sich Bedienelemente?
##   - offscreen: läuft ein Element aus dem Canvas?
## Seit W20/P4 (UI-Rework) zusätzlich — Checks in fb3_audit_extra.gd:
##   - falz: Unter-der-Falz-Wache — jedes interaktive Element erreichbar
##     (sichtbar oder scrollbar; weggeclippte Knöpfe ohne Scroller = tot)?
##   - stretch: Vollbreite-Balken >85 % Canvas ohne Inhaltsspalte;
##     Cover-Verzerrung (TextureRect-Anzeige-Aspekt ≠ Quell-Aspekt)?
##   - kombi_overlap: provozierte Kombinationen Toast×Topbar (Station 23)
##     und Gooby-Blase×Dock (Station 24) — misst die UiAnchors-Verträge live.
##   - Leerflächen-Metrik (REPORT, kein Gate): Anteil Safe-Fläche ohne UI.
## Befunde → FB3_OUT/befunde.md (+ .json), Screenshots pro Screen/Format.
## Braucht einen echten Renderer:
##   FB3_OUT=/tmp/gooby-godot/artifacts/FB3/audit xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/fb3_ui_audit.gd

## W20/P4: ausgelagerte Zusatz-Checks (Falz/Stretch/Leerflächen) — eigene
## Datei, damit das Audit unter dem max-file-lines-Deckel bleibt.
const Extra := preload("res://tests/unit/fb3_audit_extra.gd")

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

## W20/P4 Kombinations-Checks: bewusst LANGE Texte, damit Toast/Blase ihre
## maximale Breite ausfahren (der Worst Case der W14-Zonen-Verträge).
const KOMBI_TOAST_TEXT := (
	"Abzeichen verdient! Dieser bewusst lange Audit-Toast fährt die volle "
	+ "Breite aus und prüft die Kopfzeilen-Zone über den Status-Pills."
)
const KOMBI_BLASE_TEXT := (
	"Ohh, was für ein wunderbar langer Audit-Spruch! Diese Blase prüft, ob "
	+ "Goobys Worte je über das Daumen-Dock oder die Bodenzeile wandern."
)

## [label, Fenster-px, screen_scale, insets in PUNKTEN {l,t,r,b}]
## G7/P57 Leitformat ZUERST (User-Wunsch „iPhone 17 Pro Max, Querformat"):
## 2868×1320 physisch @3x = 956×440 pt (6,9", wie 16 Pro Max). Safe-Area
## wie die Dynamic-Island-Klasse 2556×1179: quer 59 pt links/rechts +
## 21 pt Home-Indicator, hoch 59 pt oben + 34 pt unten.
const SIZES: Array = [
	["quer_2868x1320", Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]],
	["quer_2556x1179", Vector2i(2556, 1179), 3.0, [59.0, 0.0, 59.0, 21.0]],
	["quer_1792x828", Vector2i(1792, 828), 2.0, [48.0, 0.0, 48.0, 21.0]],
	["hoch_1320x2868", Vector2i(1320, 2868), 3.0, [0.0, 59.0, 0.0, 34.0]],
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
	# W17/G5 P33: G4-Domänen OHNE content_frame — die zentrierten Haupt-
	# Karten/-Docks (card_width-Muster) tragen das Spalten-Meta selbst
	# nicht; der Audit markiert sie beim Öffnen (_markiere_spalte) und
	# misst mit der Screen-eigenen Design-Basis (Konstante, kein Drift).
	# W18/G7 P57: die Telefon-Stationen (11–13) stehen NICHT mehr hier —
	# ihre Basis folgt der Orientierung (G7/P52: quer die breite 640er-
	# GERAET_QUER-Basis) und kommt live aus PhoneShell.basis_groesse
	# (_spalten_basis), sonst meldet der Deckel das bewusst breite
	# Quer-Gerät als „Spalte zu breit" (falsch positiv).
	"10_bau_dock": BuildUiDock.DOCK_BASIS,
	"18_onboarding_welcome": OnboardingFlow.CARD_BASE_WIDTH,
	"19_onboarding_editor": OnboardingFlow.EDITOR_CARD_BASE_WIDTH,
	# W20/P4 Nachfix: Pregame-Karte + GvZ-Select tragen das Spalten-Meta
	# jetzt selbst (Stretch-Befunde 06/20). Das GvZ-Select deckelt auf
	# content_width und nutzt darum den CONTENT_MAX_WIDTH-Default (kein
	# Eintrag nötig). Die Pregame-Basis folgt seit W21/P4 (d) der
	# Orientierung und kommt darum LIVE aus MinigamePregame.karten_basis
	# (_spalten_basis) statt aus dieser Konstanten-Tabelle.
}
## Telefon-Stationen mit orientierungsbewusster Spalten-Basis (P57).
const PHONE_SCREENS: Array[String] = ["11_phone_grid", "12_phone_taxi", "13_phone_gooberando"]

## W17/G5 P33 Rauschfilter: bewusste RAND-Elemente NEBEN der markierten
## Spalte — die Kamera-Chips des Baumodus sitzen per Design rechts mittig
## am Rand (G4/P15 FIX-3: „weit weg von Dock und Action-Bar", Daumenzone)
## und gehören NICHT ins Dock. Safe-Area-/Tap-/Overlap-/Offscreen-Checks
## gelten für sie unverändert; nur die Spalten-Zugehörigkeit entfällt.
const SPALTEN_RAND_ELTERN: Array[String] = ["KameraLeiste"]

var _out_dir := DEFAULT_OUT
var _router: Node
var _entry: Node
var _hud: Control
var _findings: Array[Dictionary] = []
## W20/P4 Leerflächen-Metrik (Report, kein Gate): "format|screen" → Prozent.
var _leerflaechen: Dictionary = {}
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
	await _audit_kombis()
	for screen_info: Array in [
		["arcade", &"arcade"],
		["album", &"album"],
		# W14/UISCREENS-A: „profil“ zeigte den SOCIAL-Screen (Stand vor der
		# REST-1-Fehlrouten-Korrektur) — jetzt den echten Profil-Screen
		# auditieren; Social bleibt als eigener Eintrag abgedeckt.
		["profil", &"profil"],
		["social", &"social"],
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
	# W17/G5 P33: Stationen der G4-Domänen — Overlays/Kontext-Flächen, die
	# NICHT über den Router laufen (Mount-Weg siehe Funktions-Doku).
	await _audit_bau_dock()
	await _audit_phone()
	await _audit_radio_sheet()
	await _audit_rmp_hub()
	await _audit_reise_app()
	await _audit_onboarding()
	await _audit_level_selects()
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


## W20/P4 Kombinations-Checks (Stationen 23+24): die W14-Zonen-Verträge
## (UiAnchors) versprechen überlappungsfreie Randzonen — der Audit
## PROVOZIERT beide Kombinationen jetzt live auf dem Home-HUD (langer
## Toast über der Kopfzeile, lange Gooby-Blase über dem Dock) und misst
## echte Rect-Schnitte gegen ALLE Bedienelemente (Check `kombi_overlap`).
func _audit_kombis() -> void:
	ToastLayer.zeige(_hud, KOMBI_TOAST_TEXT)
	# NICHT _settle(): der Toast lebt nur HOLD 2,2 s (Echtzeit) — 20 Frames
	# unter llvmpipe im Leitformat dauern länger, die Messung käme zu spät.
	# Auf Sichtbarkeit warten, Reposition (2 awaitete Frames) nachziehen.
	await _wait_for(_toast_sichtbar, 6000)
	await process_frame
	await process_frame
	await process_frame
	_kombi_check("23_kombi_toast", _toast_panel_rect(), "Toast")
	_screens_checked += 1
	await _snap("%s_23_kombi_toast.png" % _label)
	await _warte_toast_weg()
	var blase := AcBubble.show_bubble(_entry.get_node("UiLayer"), KOMBI_BLASE_TEXT, {})
	await _settle()
	var kapsel: Variant = blase.get("_kapsel")
	if kapsel is Control:
		_kombi_check("24_kombi_blase", (kapsel as Control).get_global_rect(), "Blase")
	else:
		_add_finding("24_kombi_blase", "kombi_overlap", "Blase", "Kapsel fehlt — nicht messbar")
	_screens_checked += 1
	await _snap("%s_24_kombi_blase.png" % _label)
	blase.dismiss()
	await _settle()


## Rect-Schnitt des provozierten Elements gegen alle Bedienelemente.
func _kombi_check(screen: String, rect: Rect2, was: String) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_add_finding(screen, "kombi_overlap", was, "Element nicht sichtbar — nicht messbar")
		return
	for ctl in _interactive_controls():
		var schnitt := rect.intersection(_effective_rect(ctl))
		if schnitt.size.x > 4.0 and schnitt.size.y > 4.0:
			_add_finding(
				screen,
				"kombi_overlap",
				"%s × %s" % [was, _describe(ctl)],
				"Überlappung %s" % schnitt
			)


func _toast_sichtbar() -> bool:
	return _toast_panel_rect().size.x > 0.0


func _toast_panel_rect() -> Rect2:
	for node: Node in get_nodes_in_group(ToastLayer.GROUP):
		if node is ToastLayer and (node as ToastLayer).is_showing():
			var panel: Variant = node.get("_panel")
			if panel is Control and (panel as Control).visible:
				return (panel as Control).get_global_rect()
	return Rect2()


## Toast ausklingen lassen (HOLD + FADE laufen in Echtzeit), damit er die
## Blasen-Messung und die Folge-Stationen nicht verunreinigt.
func _warte_toast_weg() -> void:
	await _wait_for(
		func() -> bool:
			for node: Node in get_nodes_in_group(ToastLayer.GROUP):
				if node is ToastLayer and (node as ToastLayer).is_showing():
					return false
			return true,
		8000
	)
	await _settle()


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


## ---- G4-Domänen (W17/G5 P33) ---------------------------------------------
## Kein Router-Ziel: Die folgenden Flächen mounten wie im echten Spiel
## (HUD-Aktion, Möbel-Tap, Hof-Knopf, Erststart) — der Audit ruft dieselben
## Einstiege auf und misst mit der UNVERÄNDERTEN Check-Logik.


## Baumodus (G4/P15): läuft IM Raum — Mount wie der HUD-Bau-Knopf
## (home_entry._on_hud_action → room.open_build_mode()). Der Bett-Quest-
## Ghost würde close() blockieren (Bauquest Doc D §3.1), darum markiert
## der Audit das Bett vorab als gebaut (reiner Audit-Save, kein Screen-
## Eingriff). HUD bleibt AN — im echten Baumodus ist es sichtbar.
func _audit_bau_dock() -> void:
	var room: Variant = _router.get_current_scene()
	if room == null or not (room as Node).has_method("open_build_mode"):
		_add_finding("10_bau_dock", "flow", "-", "Raum nicht erreicht")
		return
	HomeState.set_flag(root.get_node("/root/GameState"), HomeState.FLAG_BED_PLACED, true)
	room.open_build_mode()
	await _settle()
	_markiere_spalte("BauDock")
	await _snap_and_check("10_bau_dock")
	var bau: Variant = (room as Node).get_node_or_null("BuildMode")
	if bau is BuildMode:
		(bau as BuildMode).close()
	await _settle()


## IGohbie-Telefon (G4/P18): Vollbild-Overlay ÜBER dem Raum (eigener
## CanvasLayer). Im Spiel bleibt das HUD zwar visible, aber der Voll-
## flächen-Scrim (MOUSE_FILTER_STOP) macht es unbedienbar — Button-Paare
## über die Modal-Ebene hinweg sind KEIN Bedien-Konflikt. Der Audit
## blendet das HUD daher für die Messung aus (HUD-Geometrie: Station 01).
## Grid + 2 Apps: Taxi (Fahrdienst-Formular) und GOOBERANDO (dichtestes
## App-UI, bis P34 noch auf 420er-City-Bausteinen).
func _audit_phone() -> void:
	_hud.visible = false
	var shell := PhoneShell.oeffne(_entry, root.get_node("/root/GameState"))
	await _settle()
	_markiere_spalte("Geraet")
	await _snap_and_check("11_phone_grid")
	shell.oeffne_app("taxi")
	await _settle()
	await _snap_and_check("12_phone_taxi")
	shell.oeffne_app("gooberando")
	await _settle()
	await _snap_and_check("13_phone_gooberando")
	shell.schliesse()
	await _settle()
	_hud.visible = true


## Radio (G4/P17): PanelSheet-Inhalt — Mount wie RadioGeraet._open_panel
## (Sheet ohne Titelzeile, RadioSheet bringt die eigene Kopfzeile mit).
## Das PanelSheet ist modal (Backdrop fängt Eingaben) — HUD unterm
## Backdrop ist unbedienbar, darum wie beim Telefon fürs Messen aus.
## Spalten-Kategorie entfällt (PanelSheet).
func _audit_radio_sheet() -> void:
	_hud.visible = false
	var layer := CanvasLayer.new()
	layer.name = "AuditRadioLayer"
	layer.layer = 30
	root.add_child(layer)
	var panel: PanelSheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
	panel.theme = ThemeService.theme()
	layer.add_child(panel)
	panel.set_title("")
	var sheet := RadioSheet.new()
	sheet.gs = root.get_node("/root/GameState")
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_content(sheet)
	panel.open()
	await _settle()
	await _snap_and_check("14_radio_sheet")
	panel.close()
	await _settle()
	layer.queue_free()
	await _settle()
	_hud.visible = true


## Ranch-MP (G4/P19): Hub-Sheets Menü → Lobby — Mount wie der Hof-Knopf
## (RmpHub.attach_to + oeffne; ohne Session zeigt oeffne das Menü, die
## Lobby läuft leer/offline — RW-6-Vertrag). Im echten Hof-Kontext ist
## das Home-HUD aus (Hof ist kein RoomBase) — der Audit stellt das nach.
func _audit_rmp_hub() -> void:
	_hud.visible = false
	var hub := RmpHub.attach_to(_entry)
	await _settle()
	hub.oeffne()
	await _settle()
	await _snap_and_check("15_rmp_menu")
	hub.call("_zeige_lobby")
	await _settle()
	await _snap_and_check("16_rmp_lobby")
	hub.call("_schliesse_sheets")
	await _settle()
	_hud.visible = true


## Reise-App (G4/P16): PanelSheet über der Trägerszene — Mount wie
## ReiseApp.oeffne. Echter Kontext ist die Stadt (kein RoomBase, Home-HUD
## aus) — der Audit stellt das nach; Spalten-Kategorie entfällt (Sheet).
func _audit_reise_app() -> void:
	_hud.visible = false
	var app := ReiseApp.oeffne(_entry, root.get_node("/root/GameState"))
	await _settle()
	await _snap_and_check("17_reise_app")
	app.sheet.close()
	await _settle()
	_hud.visible = true


## Onboarding (G4/P23): läuft beim Erststart VOR dem HUD
## (home_entry._show_onboarding, HUD disabled) — der Audit stellt das
## nach. Steps schalten SYNCHRON (Sichtbarkeits-Vertrag
## test_ui_onboarding) — der Audit fährt den ECHTEN Flow über die
## Weiter-Handler (Name → Spitzname → Editor) statt _show_step zu forcen.
func _audit_onboarding() -> void:
	_hud.visible = false
	var flow: OnboardingFlow = (
		(load("res://scripts/ui/onboarding/onboarding_flow.tscn") as PackedScene).instantiate()
	)
	_entry.get_node("UiLayer").add_child(flow)
	await _settle()
	_markiere_spalte("StepWelcome")
	await _snap_and_check("18_onboarding_welcome")
	(flow.get_node("%NameEdit") as LineEdit).text = "Audit-Gooby"
	flow.call("_on_welcome_next")
	flow.call("_on_nickname_next")
	await _settle()
	_markiere_spalte("StepEditor")
	await _snap_and_check("19_onboarding_editor")
	flow.queue_free()
	await _settle()
	_hud.visible = true


## Level-Selects (G4/P20): leben im Spiel im Arcade-SubViewport — der
## Audit misst aber nur den HAUPT-Viewport (SubViewports haben eigene
## Koordinatenräume, s. _interactive_controls). Eigener Mount-Weg:
## Vollbild direkt am Root (die Selects binden sich selbst an den
## Viewport, B11-Muster). Echter Kontext = Minigame-Route → Home-HUD
## aus, und der Host letterboxt den SubViewport INNERHALB der Safe-Area
## (_layout_stage) — Notch-Insets existieren für die Selects in-game
## NICHT. Der Root-Mount misst darum ohne Insets (Safe = Canvas);
## Tap-/Overlap-/Offscreen-Checks bleiben unverändert scharf. Vor der
## Messung muss die Blätter-Animation fertig sein (Kacheln skalieren
## von 0 — Zwischenzustände wären Overlap-/Tap-Rauschen).
func _audit_level_selects() -> void:
	_hud.visible = false
	var safe_vorher := Rect2(_safe_rect)
	_safe_rect = Rect2(Vector2.ZERO, _canvas)
	UiScale.insets_override = Rect2(_safe_rect)
	var gs := root.get_node("/root/GameState")
	for eintrag: Array in [
		["20_select_gvz", GvzLevelSelect.new()],
		["21_select_gobnom", GobnomLevelSelect.new()],
		["22_select_comp", RcompLevelSelect.new()],
	]:
		var select: Control = eintrag[1]
		select.set("game_state", gs)
		root.add_child(select)
		await _settle()
		await _warte_bis_buttons_ruhig(select)
		await _snap_and_check(String(eintrag[0]))
		select.queue_free()
		await _settle()
	_safe_rect = safe_vorher
	UiScale.insets_override = Rect2(_safe_rect)
	_hud.visible = true


## W17/G5 P33: Deckel-Messung OHNE Screen-Eingriff — G4-Karten/Docks
## zentrieren über ScreenShell.card_width, tragen aber (kein
## content_frame-Screen) kein Spalten-Meta. Der Audit markiert den
## sichtbaren Haupt-Container selbst, damit _check_content_column die
## BESTEHENDE Messung (Safe-Zentrierung ±2 px + Breiten-Deckel aus
## COLUMN_BASE_BY_SCREEN) anwenden kann.
func _markiere_spalte(node_name: String) -> void:
	for node: Control in root.find_children(node_name, "Control", true, false):
		if node.is_visible_in_tree():
			node.set_meta(ScreenShell.META_CONTENT_COLUMN, true)


## Blätter-/Einfeder-Animationen abwarten: alle sichtbaren Buttons des
## Teilbaums wieder auf Scale 1 (Level-Selects klappen Kacheln von 0 auf).
func _warte_bis_buttons_ruhig(wurzel: Node) -> void:
	await _wait_for(
		func() -> bool:
			for node: Control in wurzel.find_children("*", "Button", true, false):
				if not node.scale.is_equal_approx(Vector2.ONE):
					return false
			return true,
		6000
	)
	await _settle()


func _register_all_routes() -> void:
	ArcadeScreen.register_routes()
	AlbumScreen.register_routes()
	ProfilScreen.register_routes()
	SocialScreen.register_routes()
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
	# W20/P4: Falz-/Stretch-Wache + Leerflächen-Metrik (fb3_audit_extra.gd).
	var extra: Array[Dictionary] = Extra.falz_befunde(controls, _canvas)
	extra.append_array(Extra.stretch_befunde(root, _canvas, _content_columns(), _in_overlay_layer))
	for befund: Dictionary in extra:
		_add_finding(
			screen, String(befund["check"]), String(befund["node"]), String(befund["detail"])
		)
	_leerflaechen["%s|%s" % [_label, screen]] = Extra.leerflaeche_prozent(root, _safe_rect)


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
	var base := _spalten_basis(screen)
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
		if not (ctl is Button) or _in_overlay_layer(ctl) or _in_spalten_rand(ctl):
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


## W18/G7 P57: Spalten-Basis eines Screens. Die Telefon-Stationen folgen
## der Geräte-Orientierung (PhoneShell.basis_groesse — quer seit G7/P52
## die breite GERAET_QUER-Basis), alle anderen kommen aus
## COLUMN_BASE_BY_SCREEN bzw. dem CONTENT_MAX_WIDTH-Default.
func _spalten_basis(screen: String) -> float:
	if screen in PHONE_SCREENS:
		return PhoneShell.basis_groesse(ScreenShell.metrics(root)).x
	# W21/P4 (d): die Pregame-Karte ist quer die breite Zwei-Spalten-Karte
	# (Cover links, Zeilen rechts) — Basis live je Orientierung.
	if screen == "06_pregame":
		return MinigamePregame.karten_basis(ScreenShell.metrics(root))
	return float(COLUMN_BASE_BY_SCREEN.get(screen, AcTokens.CONTENT_MAX_WIDTH))


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


## W17/G5 P33: Rand-Elemente aus SPALTEN_RAND_ELTERN (bewusst NEBEN der
## markierten Spalte platziert) von der Spalten-Zugehörigkeit ausnehmen.
func _in_spalten_rand(ctl: Control) -> bool:
	var node: Node = ctl
	while node != null:
		if String(node.name) in SPALTEN_RAND_ELTERN:
			return true
		node = node.get_parent()
	return false


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
	_write_leerflaechen(md)
	md.close()


## W20/P4 Leerflächen-Metrik als Report-Abschnitt (KEIN Gate): Anteil der
## Safe-Fläche ohne zeichnende UI. Home-/Raum-/Spiel-Stationen haben die
## 3D-/SubViewport-Kulisse dahinter — dort ist ein hoher Wert erwartbar.
func _write_leerflaechen(md: FileAccess) -> void:
	if _leerflaechen.is_empty():
		return
	var formate: Array[String] = []
	var screens: Array[String] = []
	for key: String in _leerflaechen:
		var teile := key.split("|")
		if not teile[0] in formate:
			formate.append(teile[0])
		if not teile[1] in screens:
			screens.append(teile[1])
	screens.sort()
	md.store_line("")
	md.store_line("## Leerflächen-Metrik (Report, kein Gate)")
	md.store_line("")
	md.store_line("Anteil der Safe-Fläche OHNE zeichnende UI (24×12-Raster; Kulissen")
	md.store_line("≥80 % Safe zählen nicht als Inhalt; 3D-Stationen: nur relativ deuten).")
	md.store_line("")
	md.store_line("| Screen | %s |" % " | ".join(formate))
	md.store_line("|---|%s" % "---|".repeat(formate.size()))
	for screen: String in screens:
		var zellen: Array[String] = []
		for format: String in formate:
			var wert: Variant = _leerflaechen.get("%s|%s" % [format, screen])
			zellen.append(("%.0f %%" % float(wert)) if wert != null else "—")
		md.store_line("| %s | %s |" % [screen, " | ".join(zellen)])


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
	# W17/G5 P33: gleiche Rauschquelle Nr. 2 — die Choice-Karte der
	# Zufalls-Events (EventRunner/EventProps.show_choice, z. B. Herbert
	# der Wurm) spawnt per RNG beim Start und bleibt offen, bis jemand
	# wählt; ihre 2 Knöpfe wanderten sonst als Overlap-/Spalten-Befunde
	# durch ALLE folgenden Stationen des Laufs.
	for node: Control in root.find_children("EventChoice", "Control", true, false):
		node.visible = false
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, file])
	print("  gespeichert: %s" % file)

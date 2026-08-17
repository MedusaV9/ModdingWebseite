extends W1cTestCase
## REST-1 UI-Prüfung (W1c-Runner): Profil-Screen, Erfolgs-Screen und das
## Tagesbonus-Popup in 4 Geräteformaten (Notch/Home-Indicator simuliert wie
## im FB3-Audit) — kein Bedienelement ragt aus der Safe-Area, Popup-Knöpfe
## halten den Touch-Floor, und der Claim-Fluss zahlt genau einmal.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1_750_000_000_000
## [Label, Fenster-px, Insets in Canvas-px {l,t,r,b}] — FB3-Formate.
const FORMATE: Array = [
	["quer_2556x1179", Vector2i(2556, 1179), Rect2(177, 0, 2556 - 354, 1179 - 63)],
	["quer_1792x828", Vector2i(1792, 828), Rect2(96, 0, 1792 - 192, 828 - 42)],
	["hoch_1179x2556", Vector2i(1179, 2556), Rect2(0, 177, 1179, 2556 - 279)],
	["ipad_2360x1640", Vector2i(2360, 1640), Rect2(0, 48, 2360, 1640 - 88)],
]

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://rest1_tests/ui_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("onboarding.done", true)
	return gs


func _buttons_von(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		stack.append_array(current.get_children())
		if current is Button and (current as Button).is_visible_in_tree():
			out.append(current)
	return out


## Rect nach Clipping durch Scroll-Ahnen (FB3-Regel: Gescrolltes unter der
## Falte ist KEIN Safe-Area-Befund).
func _effective_rect(ctl: Control) -> Rect2:
	var rect := ctl.get_global_rect()
	var node: Node = ctl.get_parent()
	while node is Control:
		var parent := node as Control
		if parent.clip_contents or parent is ScrollContainer:
			rect = rect.intersection(parent.get_global_rect())
		node = parent.get_parent()
	return rect


func _check_safe_area(screen_name: String, root_node: Node, safe: Rect2, label: String) -> void:
	for btn in _buttons_von(root_node):
		var rect := _effective_rect(btn)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		check(
			safe.grow(2.0).encloses(rect),
			(
				"%s/%s: %s ragt aus der Safe-Area (%s vs %s)"
				% [label, screen_name, btn.name, rect, safe]
			)
		)


func test_profil_und_erfolge_safe_area_in_4_formaten() -> void:
	var gs := _fresh_gs()
	mount(gs)
	for format: Array in FORMATE:
		var label := str(format[0])
		tree.root.size = format[1]
		UiScale.insets_override = format[2]
		await tree.process_frame
		var profil := ProfilScreen.new()
		profil.auto_navigate = false
		profil.gs_override = gs
		mount(profil)
		await tree.process_frame
		await tree.process_frame
		var safe := _safe_rect(format[2])
		_check_safe_area("profil", profil, safe, label)
		unmount(profil)
		var erfolge := AchievementsScreen.new()
		erfolge.auto_navigate = false
		erfolge.gs_override = gs
		mount(erfolge)
		await tree.process_frame
		await tree.process_frame
		_check_safe_area("erfolge", erfolge, safe, label)
		unmount(erfolge)
	UiScale.insets_override = Rect2()
	tree.root.size = Vector2i(1280, 720)
	unmount(gs)


func test_daily_popup_safe_area_und_touch_floor_in_4_formaten() -> void:
	var gs := _fresh_gs()
	mount(gs)
	for format: Array in FORMATE:
		var label := str(format[0])
		tree.root.size = format[1]
		UiScale.insets_override = format[2]
		await tree.process_frame
		PanelStack.clear()
		var popup := DailyBonusPopup.new()
		popup.theme = ThemeService.theme()
		popup.setup(gs)
		mount(popup)
		await tree.process_frame
		await tree.process_frame
		var safe := _safe_rect(format[2])
		_check_safe_area("daily", popup, safe, label)
		var m := ScreenShell.metrics(popup.get_viewport())
		var floor_px: float = m["floor_px"]
		for btn in _buttons_von(popup):
			var side := minf(btn.get_global_rect().size.x, btn.get_global_rect().size.y)
			check(
				side >= floor_px - 0.5,
				(
					"%s: %s unterschreitet den Touch-Floor (%.1f < %.1f)"
					% [label, btn.name, side, floor_px]
				)
			)
		unmount(popup)
	UiScale.insets_override = Rect2()
	tree.root.size = Vector2i(1280, 720)
	unmount(gs)


func test_daily_popup_claim_fluss_zahlt_einmal() -> void:
	PanelStack.clear()
	var gs := _fresh_gs()
	mount(gs)
	var day := str(gs.clock.local_day())
	check(DailyBonusPopup.should_offer(gs, day), "frischer Tag → Angebot")
	var popup := DailyBonusPopup.new()
	popup.theme = ThemeService.theme()
	popup.setup(gs)
	var rewards: Array = []
	popup.claimed.connect(func(reward: Dictionary) -> void: rewards.append(reward))
	mount(popup)
	await tree.process_frame
	var coins_before := int(gs.get_value("economy.coins", 0))
	popup._on_claim()
	await tree.process_frame
	check_eq(rewards.size(), 1, "claimed-Signal genau einmal")
	check_eq(int(gs.get_value("economy.coins", 0)), coins_before + 20, "Tag 1 zahlt 20")
	check_eq(str(gs.get_value("daily.lastClaimDay", "")), day, "Tag gestempelt")
	check_eq(int(gs.get_value("daily.streak", 0)), 1, "Serie startet bei 1")
	check(not DailyBonusPopup.should_offer(gs, day), "heute kein zweites Angebot")
	await tree.process_frame
	unmount(gs)


func test_daily_popup_weicht_anderen_panels() -> void:
	PanelStack.clear()
	var gs := _fresh_gs()
	mount(gs)
	var popup := DailyBonusPopup.new()
	popup.theme = ThemeService.theme()
	popup.setup(gs)
	var dismissed_count := [0]
	popup.dismissed.connect(func() -> void: dismissed_count[0] += 1)
	mount(popup)
	await tree.process_frame
	check(PanelStack.is_top(popup), "Popup ist oberstes Panel")
	# Ein anderes Panel geht darüber auf (Status-Sheet-Fall) → „Später“.
	var fremd := Control.new()
	mount(fremd)
	PanelStack.push(fremd)
	await tree.process_frame
	await tree.process_frame
	check_eq(dismissed_count[0], 1, "Popup räumt das Feld (Später-Semantik)")
	check(
		str(gs.get_value("daily.lastClaimDay", "")) != str(gs.clock.local_day()),
		"NICHT geclaimt — Bonus bleibt abholbar"
	)
	PanelStack.remove(fremd)
	unmount(fremd)
	await tree.process_frame
	unmount(gs)


## W21-Wächter („nichts hat die gleiche Größe“): die Erfolgs-Zeilen entstehen
## NACH _apply_metrics (_show_category) — Schriften und Balkenhöhe müssen
## trotzdem mit dem UiScale-Faktor skalieren, nicht in Basis-px bleiben.
func test_erfolge_zeilen_skalieren_mit_uiscale() -> void:
	var gs := _fresh_gs()
	mount(gs)
	UiScale.screen_scale_override = 3.0
	await tree.process_frame
	var erfolge := AchievementsScreen.new()
	erfolge.auto_navigate = false
	erfolge.gs_override = gs
	mount(erfolge)
	await tree.process_frame
	await tree.process_frame
	var f := float(ScreenShell.metrics(tree.root)["f"])
	check(f > 1.5, "Simulation skaliert (f=%.2f)" % f)
	var desc := erfolge.find_child("Desc", true, false) as Label
	check(desc != null, "Erfolgs-Zeile hat eine Beschreibung")
	check_eq(
		desc.get_theme_font_size("font_size"),
		int(maxf(roundf(AcTokens.FONT_SIZE_BODY * f), 10.0)),
		"Zeilen-Beschreibung (SoftLabel) skaliert mit f"
	)
	var bar := erfolge.find_child("Fortschritt", true, false) as ProgressBar
	check(bar != null, "Erfolgs-Zeile hat einen Fortschrittsbalken")
	check_eq(int(bar.custom_minimum_size.y), int(roundf(10.0 * f)), "Balkenhöhe skaliert mit f")
	unmount(erfolge)
	UiScale.screen_scale_override = 0.0
	unmount(gs)


func _safe_rect(insets: Rect2) -> Rect2:
	return insets

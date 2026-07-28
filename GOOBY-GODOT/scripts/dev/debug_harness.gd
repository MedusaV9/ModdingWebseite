extends SceneTree
## Minimaler Debug-Harness ohne Theme-Import (nur Pure-Logic + Datei-Analyse).

const Sleep := preload("res://scripts/logic/sleep.gd")
const AgentDebugScript := preload("res://scripts/dev/agent_debug.gd")
const UiScaleScript := preload("res://scripts/ui/ui_scale.gd")
const HudLayoutScript := preload("res://scripts/ui/hud_layout_logic.gd")
const AcTokensScript := preload("res://themes/tokens.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_h1_settings_scroll()
	_h2_hud_sizes()
	_h3_build_wander_code()
	_h4_arcade_back()
	_h5_sleep_cancel()
	_h6_sleep_pose_order()
	print("AGENT_DEBUG_DONE")
	quit(0)


func _h1_settings_scroll() -> void:
	var tscn := FileAccess.get_file_as_string("res://scripts/ui/settings_screen.tscn")
	(
		AgentDebugScript
		. log(
			"S1",
			"debug_harness.gd:h1",
			"settings_scroll_structure",
			{
				"has_center_container": tscn.contains('type="CenterContainer"'),
				"has_scroll_center_node": tscn.contains("ScrollCenter"),
				"sections_under_scroll": tscn.contains('parent="Margin/Layout/Scroll"'),
				"sections_shrink_begin": tscn.contains("size_flags_vertical = 0"),
				"has_scroll_container": tscn.contains('type="ScrollContainer"'),
				"mentions_scroll_deadzone": tscn.contains("scroll_deadzone"),
				"run": "post-fix",
			}
		)
	)
	var sheet := FileAccess.get_file_as_string("res://scripts/ui/panel_sheet.tscn")
	(
		AgentDebugScript
		. log(
			"S1",
			"debug_harness.gd:h1",
			"panel_sheet_scroll_body",
			{
				"sheet_body_expand_fill": sheet.contains("size_flags_vertical = 3"),
				"sheet_body_shrink": sheet.contains("size_flags_vertical = 0"),
			}
		)
	)
	var cam := FileAccess.get_file_as_string("res://scripts/home/camera_rig.gd")
	(
		AgentDebugScript
		. log(
			"C1",
			"debug_harness.gd:h1",
			"camera_free_pan",
			{
				"has_unhandled_input": cam.contains("func _unhandled_input"),
				"has_pan_screen": cam.contains("func _pan_screen"),
				"has_manual_hold": cam.contains("MANUAL_HOLD_S"),
			}
		)
	)


func _h2_hud_sizes() -> void:
	UiScaleScript.screen_scale_override = 2.0
	var canvas := Vector2(1558, 720)
	var window_px := Vector2(2556, 1179)
	var f_canvas := UiScaleScript.for_canvas(canvas)
	var f_phys := UiScaleScript.physical_factor(canvas, window_px, 2.0)
	var f := maxf(f_canvas, f_phys)
	var floor_px := maxf(
		HudLayoutScript.touch_floor_canvas(canvas),
		float(AcTokensScript.TOUCH_FLOOR) * (canvas.y / (window_px.y / 2.0))
	)
	var btn := maxf(HudLayoutScript.LANDSCAPE_BTN * f, floor_px)
	var bar_w := 80.0 * f
	(
		AgentDebugScript
		. log(
			"H2",
			"debug_harness.gd:h2",
			"hud_landscape_sizes",
			{
				"ui_scale_f": f,
				"floor_px": floor_px,
				"action_btn_design": HudLayoutScript.LANDSCAPE_BTN,
				"icon_design": HudLayoutScript.LANDSCAPE_ICON,
				"computed_btn": btn,
				"stat_bar_w": bar_w,
				"chip_min": floor_px,
				"oversized_btn": btn > 72.0,
				"oversized_bar": bar_w > 160.0,
			}
		)
	)
	UiScaleScript.screen_scale_override = 0.0


func _h3_build_wander_code() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/home/room_base.gd")
	# Nach Fix: Wander bleibt an; sit-Clip nicht mehr in _on_build_opened.
	var opened_freeze := false
	var opened_idx := src.find("func _on_build_opened")
	if opened_idx >= 0:
		var chunk := src.substr(opened_idx, 500)
		opened_freeze = chunk.contains("set_wander_enabled(false)")
	(
		AgentDebugScript
		. log(
			"H3",
			"debug_harness.gd:h3",
			"build_mode_freezes_gooby",
			{
				"has_freeze_in_on_build_opened": opened_freeze,
				"forces_sit_clip":
				(
					src.find('play_clip("sit")') > opened_idx
					and opened_idx >= 0
					and src.find('play_clip("sit")') < opened_idx + 500
				),
				"keeps_wandering": src.contains("set_wander_enabled(true)"),
			}
		)
	)


func _h4_arcade_back() -> void:
	var router_src := FileAccess.get_file_as_string("res://scripts/core/scene_router.gd")
	var arcade_src := FileAccess.get_file_as_string("res://scripts/minigames/arcade_screen.gd")
	(
		AgentDebugScript
		. log(
			"H4",
			"debug_harness.gd:h4",
			"arcade_back_path",
			{
				"arcade_avoids_busy_swallow": not arcade_src.contains("router.handle_back_request"),
				"router_busy_returns_false":
				router_src.contains("if _busy:") and router_src.contains("return false"),
				"router_has_home_alias": router_src.contains("HOME_ALIAS"),
				"panelstack_close_top_first": arcade_src.contains("PanelStack.close_top()"),
			}
		)
	)


func _h5_sleep_cancel() -> void:
	var state := {
		"stats": {"energy": 40.0, "hunger": 50.0, "hygiene": 50.0, "fun": 50.0},
		"sleep": {"sleeping": true, "startedAt": 0, "wakeAt": 600000},
		"grumpyUntil": 0,
	}
	(
		AgentDebugScript
		. log(
			"H5",
			"debug_harness.gd:h5",
			"sleep_cancel_gate",
			{
				"early_wake_after_min": Sleep.EARLY_WAKE_AFTER_MIN,
				"can_wake_after_1min": Sleep.can_wake_early(state, 60_000),
				"can_wake_after_6min": Sleep.can_wake_early(state, 6 * 60_000),
				"blocked_for_user": not Sleep.can_wake_early(state, 60_000),
			}
		)
	)


func _h6_sleep_pose_order() -> void:
	var bett := FileAccess.get_file_as_string("res://scripts/home/interactables/bett.gd")
	var pflege := FileAccess.get_file_as_string("res://scripts/home/sleep/pflege_runner.gd")
	var home := FileAccess.get_file_as_string("res://scripts/home/gooby_home.gd")
	var start_i := bett.find("start_sleep_state")
	var walk_i := bett.find("walk_to")
	var lie_i := bett.find("lie_on_bed")
	(
		AgentDebugScript
		. log(
			"H6",
			"debug_harness.gd:h6",
			"sleep_pose_order",
			{
				"sleep_state_after_walk": start_i > walk_i and walk_i >= 0,
				"lie_before_state": lie_i >= 0 and lie_i < start_i,
				"snaps_gooby_onto_bed": home.contains("func lie_on_bed"),
				"aligns_yaw_to_furniture": home.contains("PI / 2.0"),
				"pflege_snaps_bed": pflege.contains("lie_on_bed"),
			}
		)
	)

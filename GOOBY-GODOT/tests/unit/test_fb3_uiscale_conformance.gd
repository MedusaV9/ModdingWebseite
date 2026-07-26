extends TestCase
## FB3 — Konformitäts-Wächter: Screens/Panels MÜSSEN die zentralen
## Bausteine benutzen (UiScale/ScreenShell/HudLayoutLogic-Touch-Floor)
## statt eigener Festpixel-Regeln (P0 „skaliert nicht mit der
## Gerätegröße“). Reiner Quelltext-Scan — schnell und headless.

## Vollbild-Screens + Overlays: mindestens EINE zentrale Regel referenzieren.
const MUST_USE_SCALE: Array[String] = [
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/panel_sheet.gd",
	"res://scripts/ui/toast.gd",
	"res://scripts/ui/hud_status_sheet.gd",
	"res://scripts/ui/news_50_panel.gd",
	"res://scripts/ui/friends/friends_screen.gd",
	"res://scripts/ui/album/album_screen.gd",
	"res://scripts/ui/social/social_screen.gd",
	"res://scripts/ui/settings_screen.gd",
	"res://scripts/minigames/arcade_screen.gd",
	"res://scripts/minigames/pregame.gd",
	"res://scripts/minigames/results.gd",
	"res://scripts/minigames/minigame_host.gd",
	"res://scripts/minigames/ui/pause_modal.gd",
]
const SCALE_MARKERS: Array[String] = ["UiScale.", "ScreenShell.", "touch_floor_canvas"]
## Safe-Area-Pflicht für VOLLBILD-Screens/Overlays (Sheet-INHALTE wie
## hud_status_sheet/news_50_panel erben die Safe-Area vom PanelSheet).
const MUST_USE_SAFE_AREA: Array[String] = [
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/panel_sheet.gd",
	"res://scripts/ui/toast.gd",
	"res://scripts/ui/friends/friends_screen.gd",
	"res://scripts/ui/album/album_screen.gd",
	"res://scripts/ui/social/social_screen.gd",
	"res://scripts/ui/settings_screen.gd",
	"res://scripts/minigames/arcade_screen.gd",
	"res://scripts/minigames/pregame.gd",
	"res://scripts/minigames/results.gd",
	"res://scripts/minigames/minigame_host.gd",
	"res://scripts/minigames/ui/pause_modal.gd",
]
const SAFE_MARKERS: Array[String] = ["safe_insets_canvas", "ScreenShell.metrics", "_safe_insets"]


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func test_screens_nutzen_die_zentrale_skalierung() -> void:
	for path in MUST_USE_SCALE:
		var src := _source(path)
		assert_true(not src.is_empty(), "%s lesbar" % path)
		var found := false
		for marker in SCALE_MARKERS:
			if src.contains(marker):
				found = true
				break
		assert_true(found, "%s nutzt UiScale/ScreenShell/Touch-Floor" % path)


func test_screens_respektieren_die_safe_area() -> void:
	for path in MUST_USE_SAFE_AREA:
		var src := _source(path)
		var found := false
		for marker in SAFE_MARKERS:
			if src.contains(marker):
				found = true
				break
		assert_true(found, "%s zieht die Safe-Area-Insets" % path)


func test_pause_modal_bleibt_kompakt_konfiguriert() -> void:
	# Wächter gegen Rückbau: Karte deutlich schmaler als die Design-Basis
	# 720 (PanelSheetLayout.MAX_WIDTH) und ein Dim-Backdrop existiert.
	assert_true(
		MinigamePauseModal.CARD_BASE_WIDTH <= PanelSheetLayout.MAX_WIDTH * 0.6,
		"Pause-Karte bleibt kompakt (Basis %d)" % int(MinigamePauseModal.CARD_BASE_WIDTH)
	)
	assert_true(MinigamePauseModal.DIM_COLOR.a >= 0.35, "Abdunkelung vorhanden")

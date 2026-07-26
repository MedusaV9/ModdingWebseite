extends TestCase
## UICOZY: AcWallpaper-Kontext-API — Aliasse, Stimmungs-Werte (1:1 aus dem
## Web-V6/A2-Themenblock), Guardrails und Reduced-Motion-Stopp.

const PATTERN_DIR := "res://assets/ui/patterns/"


func test_kontext_aufloesung_und_aliasse() -> void:
	assert_eq(AcWallpaper.resolve_context("laden"), "shop", "deutscher Alias")
	assert_eq(AcWallpaper.resolve_context("  Spielhalle "), "arcade", "trim + lowercase")
	assert_eq(AcWallpaper.resolve_context("einstellungen"), "settings", "Settings-Alias")
	assert_eq(AcWallpaper.resolve_context("voellig-unbekannt"), "default", "weicher Fallback")
	assert_eq(AcWallpaper.resolve_context("garden"), "garten", "englischer Alias")


func test_for_context_liefert_gestimmten_hintergrund() -> void:
	var wp := AcWallpaper.for_context("shop")
	tree.root.add_child(wp)
	await tree.process_frame
	assert_eq(wp.context, "shop", "Kontext gemerkt")
	assert_eq(wp.pattern, "shop", "Laden-Pattern aktiv")
	assert_almost(wp.pattern_opacity, AcTokens.PATTERN_OPACITY_THEMED, 0.001, "Themen-Deckkraft")
	assert_eq(wp.wash.to_html(false), Color("#EEF4FB").to_html(false), "Web --thm-bg Laden-Blau")
	assert_eq(wp.mouse_filter, Control.MOUSE_FILTER_IGNORE, "frisst keine Taps")
	assert_true(wp.anchor_right == 1.0 and wp.anchor_bottom == 1.0, "Full-Rect-Anchors gesetzt")
	wp.free()


func test_alle_kontexte_pattern_vorhanden_und_guardrails() -> void:
	for key: String in AcWallpaper.CONTEXTS:
		var info: Dictionary = AcWallpaper.CONTEXTS[key]
		var path := "%spattern_%s.png" % [PATTERN_DIR, info["pattern"]]
		assert_true(ResourceLoader.exists(path), "Pattern-Datei existiert (%s → %s)" % [key, path])
		var dur := float(info["dur"])
		assert_true(dur >= 80.0 and dur <= 120.0, "Drift-Guardrail 80–120 s/Kachel (%s)" % key)
		var op := float(info["opacity"])
		assert_true(op > 0.0 and op <= 0.85, "Layer-Deckkraft 0–0.85 (%s)" % key)
		for trio_key in ["accent", "accent_dark", "soft"]:
			assert_true(info.has(trio_key), "Akzent-Trio komplett (%s.%s)" % [key, trio_key])


func test_apply_context_faerbt_live_um() -> void:
	var wp := AcWallpaper.for_context("default")
	tree.root.add_child(wp)
	await tree.process_frame
	wp.apply_context("arcade")
	assert_eq(wp.context, "arcade", "Kontext-Wechsel")
	assert_eq(wp.pattern, "arcade", "Pattern zieht mit")
	assert_true(wp.drift.x > 0.0, "Arcade driftet bewusst nach rechts (Web ↗︎)")
	wp.free()


func test_reduced_motion_stoppt_drift() -> void:
	var wp := AcWallpaper.for_context("default")
	tree.root.add_child(wp)
	await tree.process_frame
	var mat := wp.material as ShaderMaterial
	assert_true(mat != null, "ShaderMaterial aktiv")
	wp._on_reduced_motion_changed(true)
	assert_almost(float(mat.get_shader_parameter("motion_scale")), 0.0, 0.001, "Drift steht")
	wp._on_reduced_motion_changed(false)
	assert_almost(float(mat.get_shader_parameter("motion_scale")), 1.0, 0.001, "Drift läuft")
	wp.free()


func test_context_accent_trio() -> void:
	var acc := AcWallpaper.context_accent("laden")
	assert_eq(
		(acc["accent"] as Color).to_html(false),
		Color("#6F9BD6").to_html(false),
		"Shop-Akzent aus dem Web-Themenblock"
	)
	assert_true(acc.has("accent_dark") and acc.has("soft"), "Trio komplett")

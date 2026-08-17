extends W1cTestCase
## Inhaltsspalte W16 (Scout-Entwurf ui-architektur §6.1): pure Geometrie-
## Tests für ScreenShell.content_width/content_frame — Breiten-Deckel,
## Zentrierung im SAFE-Rechteck (asymmetrische Insets!), Hochformat ≈
## Vollbreite und die Klemmung bei großem Benutzer-ui_scale. Läuft komplett
## ohne Viewport: das metrics-Dictionary wird direkt gebaut.


func _m(canvas: Vector2, f: float, l := 0.0, t := 0.0, r := 0.0, b := 0.0) -> Dictionary:
	return {
		"f": f,
		"canvas": canvas,
		"insets": {"left": l, "top": t, "right": r, "bottom": b},
		"floor_px": 48.0,
	}


func test_breiten_deckel_quer() -> void:
	# iPhone quer (Fenster 1792×828 → Canvas ≈1558×720, f≈1.74): genug
	# Platz — die Spalte bleibt exakt bei CONTENT_MAX_WIDTH × f.
	var m := _m(Vector2(1558.0, 720.0), 1.74, 83.5, 0.0, 83.5, 36.5)
	check_approx(
		ScreenShell.content_width(m),
		AcTokens.CONTENT_MAX_WIDTH * 1.74,
		"Breiten-Deckel 660 × f greift im Querformat"
	)


func test_eigene_basisbreite() -> void:
	# Grid-Screens (Welle G3) dürfen eine eigene base-Breite mitgeben.
	var m := _m(Vector2(2000.0, 720.0), 1.0)
	check_approx(ScreenShell.content_width(m, 880.0), 880.0, "eigene base-Breite wirkt")


func test_safe_zentrierung_bei_asymmetrischen_insets() -> void:
	# Insets links 100 / rechts 20 (Notch-Simulation): die Spalte muss im
	# SAFE-Zentrum sitzen, NICHT im Canvas-Zentrum (Entwurf-Risiko 3).
	var m := _m(Vector2(1280.0, 720.0), 1.0, 100.0, 10.0, 20.0, 30.0)
	var rows := Control.new()
	ScreenShell.content_frame(rows, m)
	var w := ScreenShell.content_width(m)
	var links := rows.offset_left
	var rechts := 1280.0 + rows.offset_right  # offset_right ist negativ.
	check_approx(rechts - links, w, "Offsets spannen exakt die Spaltenbreite auf")
	var safe_zentrum := (100.0 + (1280.0 - 20.0)) / 2.0
	check_approx((links + rechts) / 2.0, safe_zentrum, "Spalten-Zentrum = SAFE-Zentrum")
	check(rows.has_meta(ScreenShell.META_CONTENT_COLUMN), "Meta-Flag w16_content_column gesetzt")
	check_eq(rows.anchor_left, 0.0, "FULL_RECT-Anker links (wie frame)")
	check_eq(rows.anchor_right, 1.0, "FULL_RECT-Anker rechts (wie frame)")
	check_approx(rows.offset_top, 10.0 + ScreenShell.EDGE_Y, "oben: Inset + EDGE_Y × f")
	check_approx(rows.offset_bottom, -(30.0 + ScreenShell.EDGE_Y), "unten: −Inset − EDGE_Y × f")
	rows.free()


func test_hochformat_praktisch_vollbreite() -> void:
	# iPhone hoch (1179×2556 → Canvas 1280×2775, f=3.0, Insets nur
	# oben/unten): 660×3 = 1980 > Safe-Breite → Klemmung auf
	# Safe-Breite − 2 × PanelSheetLayout.MARGIN × f (wie card_width).
	var m := _m(Vector2(1280.0, 2775.0), 3.0, 0.0, 177.0, 0.0, 102.0)
	var w := ScreenShell.content_width(m)
	check_approx(
		w,
		1280.0 - 2.0 * PanelSheetLayout.MARGIN * 3.0,
		"Hochformat: Spalte klemmt auf Safe-Breite minus Kartenränder"
	)
	check(w >= 0.85 * 1280.0, "Hochformat bleibt praktisch Vollbreite (≥ 85 %)")
	var rows := Control.new()
	ScreenShell.content_frame(rows, m)
	check_approx(rows.offset_left, (1280.0 - w) / 2.0, "Hochformat: Spalte mittig")
	rows.free()


func test_user_ui_scale_klemmung() -> void:
	# Benutzerfaktor 1.6 treibt f über den Platz hinaus (Entwurf-Risiko 6):
	# 660 × 2.784 ≈ 1837 > Safe-Breite — content_width muss klemmen.
	var f := 1.74 * 1.6
	var m := _m(Vector2(1558.0, 720.0), f, 83.5, 0.0, 83.5, 0.0)
	var w := ScreenShell.content_width(m)
	var avail := 1558.0 - 167.0 - 2.0 * PanelSheetLayout.MARGIN * f
	check_approx(w, avail, "Spalte klemmt auf die verfügbare Safe-Breite")
	check(w <= 1558.0 - 167.0, "Spalte nie breiter als die Safe-Area")
	# Extremfall absurd schmaler Rest: nie negativ.
	var eng := _m(Vector2(200.0, 720.0), 3.0, 90.0, 0.0, 90.0, 0.0)
	check(ScreenShell.content_width(eng) >= 0.0, "Breite nie negativ")

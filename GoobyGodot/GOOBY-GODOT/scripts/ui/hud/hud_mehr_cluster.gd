class_name HudMehrCluster
extends RefCounted
## W20 P1 — Slimming (Befund-Top-10 „3-Spalten-Knopfwand mit 12 Kacheln“):
## Bausteine der „Mehr“-Kachel, hinter der das Zweitrangige der Cockpit-
## Wand eingeklappt lebt (Reihenfolge-Logik in HudButtonOrder.cockpit_order,
## Zustand `_mehr_offen` besitzt das HUD). Ausgelagert, damit hud.gd unter
## der 1000-Zeilen-Lint-Schranke bleibt.

const ICON_DIR := "res://assets/ui/icons/"


## „Mehr“-Umschalter bauen (nur Querformat sichtbar; das Hochkant-Dock
## bleibt 5+5). W21 P1: AcnhKit.icon_button-Sprache wie die Kacheln,
## Pfeil in Ink-Soft statt Identitätsfarbe.
static func baue_knopf(on_pressed: Callable) -> Button:
	var knopf := AcnhKit.icon_button(load(ICON_DIR + "arrow_left.svg"), 1.0, true)
	knopf.name = "BtnMehr"
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		knopf.add_theme_color_override(state, AcTokens.INK_SOFT)
	knopf.tooltip_text = I18nService.t("hud.mehr")
	knopf.visible = false
	knopf.pressed.connect(on_pressed)
	return knopf


## Kachel-Titel: die Mehr-Kachel wechselt ihren Titel mit dem Cluster-
## Zustand („Mehr“ ↔ „Weniger“), alle anderen bleiben `hud.<id>`.
static func titel(id: StringName, mehr_offen: bool) -> String:
	if id == HudButtonOrder.MEHR:
		return I18nService.t("hud.weniger" if mehr_offen else "hud.mehr")
	return I18nService.t("hud." + String(id))


## Pfeil-Icon + Tooltip an den Cluster-Zustand angleichen (auf/zu).
static func zustand_anwenden(knopf: Button, mehr_offen: bool) -> void:
	knopf.icon = load(ICON_DIR + ("arrow_right.svg" if mehr_offen else "arrow_left.svg"))
	knopf.tooltip_text = I18nService.t("hud.weniger" if mehr_offen else "hud.mehr")


## Befund E9 „Kachel-Labels unterschiedlich groß“: EIN gemeinsames
## Schriftmaß für die ganze Wand — das Minimum der Einzel-Fits.
## Schrumpfen bricht nie einen Fit (kleiner = schmaler).
static func vereinheitliche_labels(kacheln: Array[Button]) -> void:
	var gemeinsam := 999
	for kachel: Button in kacheln:
		gemeinsam = mini(gemeinsam, kachel.get_theme_font_size("font_size"))
	for kachel: Button in kacheln:
		kachel.add_theme_font_size_override("font_size", gemeinsam)


## Befund B8 (Level-Pille): linker+rechter Innenrand einer Status-Kapsel —
## der Ring-Füll-Pass zieht ihn von der Pillen-Zielbreite ab.
static func innenrand_x(chip: Control) -> float:
	if chip == null:
		return 0.0
	var style := chip.get_theme_stylebox("panel")
	if style == null:
		return 0.0
	return style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)


## W18/E6: Kurzform-Fallback einer Kachel (vollständiges Wort, z. B.
## „Outfit“ für „Garderobe“) — leer, wenn kein `hud.<id>_kurz`-Key existiert.
static func kurzform(id: StringName) -> String:
	var key := "hud.%s_kurz" % String(id)
	return I18nService.t(key) if I18nService.has_key(key) else ""


## Für Text nutzbare Breite einer Kachel: ECHTE Knopf-Mindestbreite minus
## der Innenränder der Theme-StyleBox (HudIconButton: 14 px je Seite).
## W18/E6: get_combined_minimum_size statt custom_minimum_size — das
## Theme-Minimum (Kreis-StyleBox + Icon) kann die Kachel-Vorgabe übersteigen;
## die alte Messung stufte exakt passende Titel fälschlich als zu breit ein.
static func label_breite(btn: Button) -> float:
	return maxf(btn.get_combined_minimum_size().x - label_seitenraender(btn), 1.0)


## Linker+rechter Innenrand der Kachel-StyleBox (Textfläche = Breite minus das).
static func label_seitenraender(btn: Button) -> float:
	var style := btn.get_theme_stylebox("normal")
	if style == null:
		return 0.0
	return style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)


## W21/ACNH P1 — „Wo ist mein Gooby?“ pro Layout stylen (aus hud.gd hierher,
## 1000-Zeilen-Schranke): Hochkant bleibt der Text-Chip (Bodenzeile hat
## Platz); quer wird er ein runder Lupen-Knopf in der EINEN Kompakt-Größe
## (Name im Tooltip) — der breite Text-Chip sprengte sonst das
## Ruhe-Flächen-Budget (258×79 px ≈ 1,8 % Canvas).
static func gooby_chip_stil(
	chip: Button, portrait: bool, f: float, einheit: float, floor_px: float
) -> void:
	chip.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	chip.tooltip_text = I18nService.t("hud.wo_ist_gooby")
	if portrait:
		chip.theme_type_variation = "AcChip"
		chip.icon = null
		chip.text = I18nService.t("hud.wo_ist_gooby")
		chip.add_theme_font_size_override(
			"font_size", int(maxf(float(AcTokens.SIZE_CAPTION) * f, 10.0))
		)
		# G7-P50: Mindestbreite aus der ECHTEN Textbreite (Font × f) plus
		# Chip-Chrome — der Text wurde sonst in engen Zuständen gestaucht.
		chip.custom_minimum_size = Vector2(gooby_chip_breite(chip, f), floor_px)
	else:
		chip.theme_type_variation = "HudIconButton"
		chip.icon = load(ICON_DIR + "lupe.svg")
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
			chip.add_theme_color_override(state, AcTokens.LEAF)
		chip.text = ""
		# Icon-Deckel wie Hud._scale_icon_button (ICON_L × f, min 16).
		chip.add_theme_constant_override(
			"icon_max_width", maxi(AcTokens.px(float(AcTokens.ICON_L), f), 16)
		)
		chip.custom_minimum_size = Vector2.ONE * einheit


## Mindestbreite des „Wo ist mein Gooby?“-Text-Chips (Hochkant): gemessene
## Textbreite bei SIZE_CAPTION × f plus Chip-Innenränder (G7-P50: der Text
## wurde sonst in engen Zuständen zu „Wo ist mein Goo…“ gestaucht).
static func gooby_chip_breite(chip: Button, f: float) -> float:
	var breite := HudLabelFit.text_breite(
		chip.get_theme_font("font"), chip.text, AcTokens.font_px(float(AcTokens.SIZE_CAPTION), f)
	)
	var style := chip.get_theme_stylebox("normal")
	if style != null:
		breite += style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
	return ceilf(breite)

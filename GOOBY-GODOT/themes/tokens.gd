class_name AcTokens
extends RefCounted
## AC-2.0 Design-Tokens — EINZIGE Farb-/Maß-Quelle des Godot-Ports.
## Werte 1:1 aus der Web-Referenz `GOOBY/src/ui/styles.css` (Token-Block Z. 15–147).
## KEIN Agent definiert eigene Farben/Fonts — immer über diese Konstanten
## bzw. über das daraus gebaute `res://themes/ac_theme.tres` gehen.

# ── Grundfarben (styles.css :root) ──────────────────────────────────────────
const BG_CREAM := Color("#FFF6EC")  # --bg-cream: Screen-Wash / ClearColor
const PAPER := Color("#FFFAF2")  # --paper: warme Karten-Fläche
const PAPER_SHADE := Color("#F6EAD8")  # --paper-shade: Inset-/Well-Fläche
const WHITE := Color("#FFFFFF")  # --white

const PINK := Color("#FF7BA9")  # --pink: Primär-Button
const PINK_DARK := Color("#E05F8D")  # --pink-dark
const TEAL := Color("#59C9B9")  # --teal: Sekundär-Button
const TEAL_DARK := Color("#3FA89A")  # --teal-dark
const YELLOW := Color("#FFD166")  # --yellow: Akzent/Coins
const YELLOW_DARK := Color("#E0B04A")  # --yellow-dark
const LEAF := Color("#8FD06C")  # --leaf: CTA / aktiver Tab
const LEAF_DARK := Color("#6DB54E")  # --leaf-dark
const SKY_SOFT := Color("#CFE9F5")  # --sky-soft
const GOLD := Color("#FFD34D")  # --gold: Belohnung
const DANGER := Color("#E0655F")  # --danger: destruktiv

# ── Tinte (Text) — --brown + abgeleitete Alphas ─────────────────────────────
const INK := Color("#4A3B36")  # --brown: Haupttext
const INK_SOFT := Color(0.2902, 0.2314, 0.2118, 0.72)  # --ink-soft
const INK_FAINT := Color(0.2902, 0.2314, 0.2118, 0.55)  # --ink-faint
const TRACK_SOFT := Color(0.2902, 0.2314, 0.2118, 0.10)  # --track-soft
const OUTLINE_SOFT := Color(0.2902, 0.2314, 0.2118, 0.08)  # --outline-soft
const VEIL := Color(0.2902, 0.2314, 0.2118, 0.35)  # --veil: Sheet-Scrim
const VEIL_DEEP := Color(0.1804, 0.1412, 0.1255, 0.92)  # --veil-deep
const FROST := Color(1.0, 1.0, 1.0, 0.92)  # --frost: Chips überm 3D-Raum

# ── Stat-Farben (ProgressBar-Fills) ─────────────────────────────────────────
const STAT_HUNGER := Color("#FF9F5A")  # --stat-hunger
const STAT_ENERGY := Color("#FFD166")  # --stat-energy
const STAT_HYGIENE := Color("#6EC6FF")  # --stat-hygiene
const STAT_FUN := Color("#FF7BA9")  # --stat-fun

# ── Radien (px bei Basis-Auflösung 1280×720) ────────────────────────────────
# W21/ACNH: DIE Radien-Skala — GENAU drei Stufen + Pill-Sentinel. Jede neue
# StyleBox-Rundung kommt aus RADIUS_SKALA (Wächter: test_w21_acnh_skalen).
const RADIUS_CARD := 28  # --card-radius 1.25rem→Web-20px; H §1.1 fixiert 28
const RADIUS_CARD_LG := 36  # --card-radius-lg 1.75rem
const RADIUS_ROW := 14  # --radius-row 0.875rem
const RADIUS_PILL := 999  # Pill-Sentinel (StyleBox clampt auf Halbhöhe)
const RADIUS_SKALA: Array[int] = [RADIUS_ROW, RADIUS_CARD, RADIUS_CARD_LG]

# ── W21/ACNH Spacing-Grid (Design-px, ×f) ───────────────────────────────────
# EIN Abstands-Raster: Basis 4 px, benannte Stufen 4/8/16/24/32. Jeder
# Abstand/Innenrand ist ein Vielfaches von SPACE_GRID (UI-DESIGN-ACNH §3).
const SPACE_GRID := 4
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 16
const SPACE_L := 24
const SPACE_XL := 32

# ── W21/ACNH Knopf-System (Design-px, ×f) ───────────────────────────────────
# GENAU zwei Knopf-Höhen: Primär (Hero-CTA, max. 1 pro Ansicht) und Kompakt
# (alles andere; = Touch-Floor). Löst die 6 gemessenen Höhen (79–95) ab.
const BTN_H_PRIMAER := 56
const BTN_H_KOMPAKT := 48

# ── W21/ACNH Balken-Standard (Design-px, ×f) ────────────────────────────────
# EINE Balkenhöhe für alle Fortschritts-/Stat-Balken (Pill-Radius,
# TRACK_SOFT-Spur) — löst die drei Standards 10 fix/12 fix/10×f ab.
const BAR_H := 10

# ── W21/ACNH Icon-Größen-Set (Design-px, ×f) ────────────────────────────────
const ICON_S := 16  # Inline-Glyphen in Chips/Zeilen
const ICON_M := 20  # Stat-/Listen-Icons, Münze
const ICON_L := 24  # Kachel-/Dock-Icons
const ICON_XL := 44  # Hero-Icons (Auge, große Rund-Buttons)

# ── Inhaltsspalte W16 (Rework „Inhalte in die Mitte“) ───────────────────────
const CONTENT_MAX_WIDTH := 660.0  # Design-px; = geeichte Settings-Sektionsbreite
const CONTENT_EDGE_X := 16.0  # Mindest-Seitenrand in der Safe-Area (ScreenShell.EDGE_X)

# ── Schatten ────────────────────────────────────────────────────────────────
const SHADOW_COLOR := Color(0.2902, 0.2314, 0.2118, 0.18)  # --shadow-pop
const SHADOW_SIZE := 10
const SHADOW_OFFSET_Y := 6.0
const SHADOW_PRESS_COLOR := Color(0.2902, 0.2314, 0.2118, 0.16)  # --shadow-press
const SHADOW_PRESS_SIZE := 3
# UICOZY (Web-Parität): weiche Zusatz-Schatten aus styles.css.
# --shadow-soft: 0 6px 24px rgba(74,59,54,.14) → Frost-Pills/Dock-Buttons.
const SHADOW_SOFT_COLOR := Color(0.2902, 0.2314, 0.2118, 0.14)
const SHADOW_SOFT_SIZE := 10
const SHADOW_SOFT_OFFSET_Y := 5.0
# .btn Drop-Shadow: 0 3px 10px rgba(74,59,54,.12) (zusätzlich zur Lippe).
const SHADOW_BTN_COLOR := Color(0.2902, 0.2314, 0.2118, 0.12)
const SHADOW_BTN_SIZE := 5
const SHADOW_BTN_OFFSET_Y := 3.0
# .btn-leaf FARBIGER Glow: 0 3px 10px rgba(109,181,78,.35) — statt grau.
const SHADOW_LEAF_GLOW := Color(0.4275, 0.7098, 0.3059, 0.35)
# Dock-Button-Lippe (Web .g5-hud-btn border-bottom: 4px rgba(74,59,54,.14)).
const HUD_BTN_LIP := Color(0.2902, 0.2314, 0.2118, 0.14)

# ── Motion (Sekunden) ───────────────────────────────────────────────────────
const DUR_POP := 0.18  # --dur-pop
const DUR_SHEET := 0.24  # --dur-sheet
# W14/UIKERN: satterer Squish. Web `.btn:active` = scale(.96) + translateY(2px)
# — den 2-px-Sink kann der reine Scale-Tween nicht abbilden, 0.94 gleicht die
# fehlende Versatz-Tiefe optisch aus (User-Feedback: Press war kaum spürbar).
const PRESS_SCALE := 0.94  # SquishButton-Zieldruck
# Release-Overshoot: --ease-spring cubic-bezier(0.34,1.56,0.64,1) schießt im
# Web sichtbar ÜBER die Ruhelage — SquishButton fährt erst hierhin, dann
# federnd (TRANS_BACK/EASE_OUT) zurück auf 1.0.
const SQUISH_OVERSHOOT := 1.04

# ── Wallpaper-Drift (H §1.2 Guardrails) ─────────────────────────────────────
const DRIFT_TILES_PER_SEC := Vector2(-0.010, 0.007)  # ~100 s/Kachel, schräg
const DRIFT_OPACITY := 0.06  # Guardrail: EFFEKTIVER Glyph-Kontrast ≤ 6 %
# UICOZY (Web-Parität, styles.css .screen::before + V6/A2-Themes): die
# LAYER-Deckkraft ist im Web 0.45 (Leaf-Kachel, ~13 % Delta → ~5,9 % effektiv)
# bzw. 0.85 für die Themen-Kacheln (die backen ≤ 6 % Luminanz-Delta ein).
# 0.06 als Layer-Deckkraft war eine Fehl-Lesart — Patterns waren unsichtbar.
const PATTERN_OPACITY_SCREEN := 0.45  # Web .screen::before opacity
const PATTERN_OPACITY_THEMED := 0.85  # Web --thm-pattern-opacity

# ── Typo ────────────────────────────────────────────────────────────────────
# W21/ACNH: DIE Typo-Skala — GENAU fünf Stufen (×f, round()-Konvention über
# `font_px()`). Sonderfall darunter: HUD-Mikro-Labels (9/12, autoshrink) —
# nur unter Icons, nie für Fließtext (UI-DESIGN-ACNH §3).
const FONT_PATH := "res://assets/fonts/baloo2-latin-var.woff2"  # SIL OFL 1.1
const SIZE_CAPTION := 15  # Meta/Hinweise (Ink-Faint)
const SIZE_BODY := 20  # Fließtext, 600er-Gewicht
const SIZE_BUTTON := 22  # Knopf-Text, 700
const SIZE_TITLE := 28  # Blatt-/Screen-Titel, 800
const SIZE_HEADLINE := 34  # EINE Hero-Zahl/-Zeile pro Ansicht, 800
const TYPO_SKALA: Array[int] = [SIZE_CAPTION, SIZE_BODY, SIZE_BUTTON, SIZE_TITLE, SIZE_HEADLINE]
# Alt-Namen (Bestands-Call-Sites) — bewusst reine Aliasse auf die Skala.
const FONT_SIZE_BODY := SIZE_BODY
const FONT_SIZE_BUTTON := SIZE_BUTTON
const FONT_SIZE_TITLE := SIZE_TITLE
const FONT_SIZE_HEADLINE := SIZE_HEADLINE
const FONT_SIZE_CAPTION := SIZE_CAPTION

# ── Touch ───────────────────────────────────────────────────────────────────
const TOUCH_FLOOR := 48  # überall custom_minimum_size ≥ 48×48 (Web-Regel)

# ── W21/ACNH Themen-Stimmungen (leise Farbwelt pro Bereich) ─────────────────
# Wash = Screen-Grundton, accent/accent_dark/soft = Akzent-Trio für Tabs/
# Ribbons/CTAs des Bereichs. Die Kern-Bereiche spiegeln AcWallpaper.CONTEXTS
# (Wächter: test_w21_acnh_skalen hält beide Quellen deckungsgleich); die
# DLC-Stimmungen bekommen ihre Wallpaper-Kontexte im jeweiligen DLC-Paket.
const MOODS := {
	"home":
	{
		"wash": Color("#FFF6EC"),
		"accent": Color("#8FD06C"),
		"accent_dark": Color("#6DB54E"),
		"soft": Color(0.4275, 0.7098, 0.3059, 0.3),
	},
	"ranch":
	{
		"wash": Color("#F1F8E9"),
		"accent": Color("#7BBF5E"),
		"accent_dark": Color("#5FA344"),
		"soft": Color(0.4824, 0.749, 0.3686, 0.3),
	},
	"stadt":
	{
		"wash": Color("#EFF4FB"),
		"accent": Color("#6F9BD6"),
		"accent_dark": Color("#557FB8"),
		"soft": Color(0.4353, 0.6078, 0.8392, 0.3),
	},
	"arcade":
	{
		"wash": Color("#F3EFFA"),
		"accent": Color("#9B7FD6"),
		"accent_dark": Color("#7E63B8"),
		"soft": Color(0.6078, 0.498, 0.8392, 0.3),
	},
	"dlc_gooundbye":
	{
		"wash": Color("#EFF9F3"),
		"accent": Color("#4FB58B"),
		"accent_dark": Color("#3C9671"),
		"soft": Color(0.3098, 0.7098, 0.5451, 0.3),
	},
	"dlc_mcgooby":
	{
		"wash": Color("#FDF2E7"),
		"accent": Color("#E28B4A"),
		"accent_dark": Color("#C26F32"),
		"soft": Color(0.8863, 0.5451, 0.2902, 0.3),
	},
}

## Alle Farb-Tokens als Name→Color (für Tests + ThemeService.color()).
const COLORS := {
	"BG_CREAM": BG_CREAM,
	"PAPER": PAPER,
	"PAPER_SHADE": PAPER_SHADE,
	"WHITE": WHITE,
	"PINK": PINK,
	"PINK_DARK": PINK_DARK,
	"TEAL": TEAL,
	"TEAL_DARK": TEAL_DARK,
	"YELLOW": YELLOW,
	"YELLOW_DARK": YELLOW_DARK,
	"LEAF": LEAF,
	"LEAF_DARK": LEAF_DARK,
	"SKY_SOFT": SKY_SOFT,
	"GOLD": GOLD,
	"DANGER": DANGER,
	"INK": INK,
	"INK_SOFT": INK_SOFT,
	"INK_FAINT": INK_FAINT,
	"TRACK_SOFT": TRACK_SOFT,
	"OUTLINE_SOFT": OUTLINE_SOFT,
	"VEIL": VEIL,
	"VEIL_DEEP": VEIL_DEEP,
	"FROST": FROST,
	"STAT_HUNGER": STAT_HUNGER,
	"STAT_ENERGY": STAT_ENERGY,
	"STAT_HYGIENE": STAT_HYGIENE,
	"STAT_FUN": STAT_FUN,
}


## Boden-Lippen-Farbe eines Pill-Buttons. W14/UIKERN Web-Eichung: die Lippe
## ist im Web KEIN abgedunkelter Fill, sondern brauner Ink ÜBER dem Fill
## (`.btn` inset-shadow `rgba(74,59,54,.18)`) — Blend Richtung INK statt
## ×0.82 macht den Rand wärmer und sichtbarer („dickerer Outline-Look“).
static func lip_color(fill: Color) -> Color:
	var blended := Color(fill.r, fill.g, fill.b, 1.0).lerp(INK, 0.18)
	return Color(blended.r, blended.g, blended.b, fill.a)


## W21/ACNH — DIE Rundungs-Konvention für skalierte Maße: round() statt
## int()-Trunkierung (Befund „TitleLabel 45 vs. 46“: zwei Konventionen).
static func px(design: float, f: float) -> int:
	return int(roundf(design * f))


## Skalierte Schriftgröße mit Lesbarkeits-Boden (Typo-Skala × f, round()).
static func font_px(design: float, f: float) -> int:
	return maxi(px(design, f), 10)

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
const RADIUS_CARD := 28  # --card-radius 1.25rem→Web-20px; H §1.1 fixiert 28
const RADIUS_CARD_LG := 36  # --card-radius-lg 1.75rem
const RADIUS_ROW := 14  # --radius-row 0.875rem
const RADIUS_PILL := 999  # Pill-Sentinel (StyleBox clampt auf Halbhöhe)

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
const FONT_PATH := "res://assets/fonts/baloo2-latin-var.woff2"  # SIL OFL 1.1
const FONT_SIZE_BODY := 20  # 600er-Gewicht
const FONT_SIZE_BUTTON := 22  # 700
const FONT_SIZE_TITLE := 28  # 800
const FONT_SIZE_HEADLINE := 34  # 800
const FONT_SIZE_CAPTION := 15

# ── Touch ───────────────────────────────────────────────────────────────────
const TOUCH_FLOOR := 48  # überall custom_minimum_size ≥ 48×48 (Web-Regel)

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

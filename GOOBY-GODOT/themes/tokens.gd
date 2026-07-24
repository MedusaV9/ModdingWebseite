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

# ── Schatten ────────────────────────────────────────────────────────────────
const SHADOW_COLOR := Color(0.2902, 0.2314, 0.2118, 0.18)  # --shadow-pop
const SHADOW_SIZE := 10
const SHADOW_OFFSET_Y := 6.0
const SHADOW_PRESS_COLOR := Color(0.2902, 0.2314, 0.2118, 0.16)  # --shadow-press
const SHADOW_PRESS_SIZE := 3

# ── Motion (Sekunden) ───────────────────────────────────────────────────────
const DUR_POP := 0.18  # --dur-pop
const DUR_SHEET := 0.24  # --dur-sheet
const PRESS_SCALE := 0.96  # SquishButton-Zieldruck
# --ease-spring cubic-bezier(0.34,1.56,0.64,1) → Tween.TRANS_BACK/EASE_OUT

# ── Wallpaper-Drift (H §1.2 Guardrails) ─────────────────────────────────────
const DRIFT_TILES_PER_SEC := Vector2(-0.010, 0.007)  # ~100 s/Kachel, schräg
const DRIFT_OPACITY := 0.06  # Web-Guardrail ≤ 6 %

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


## Boden-Lippen-Farbe eines Pill-Buttons: Fill × 0.82 (H §1.1).
static func lip_color(fill: Color) -> Color:
	return Color(fill.r * 0.82, fill.g * 0.82, fill.b * 0.82, fill.a)

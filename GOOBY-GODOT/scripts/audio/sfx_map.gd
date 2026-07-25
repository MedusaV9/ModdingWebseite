class_name SfxMap
extends RefCounted
## Zentrale SFX-Landkarte (W4-P1): semantische Sound-Id → OGG unter
## assets/audio/sfx/ (Kenney CC0, s. LICENSE-kenney-cc0.txt dort).
## Einzige Quelle der Wahrheit für AudioDirector.play(id) — neue Sounds
## HIER eintragen, nirgends Pfade hartkodieren. volume_db mischt die oft
## unterschiedlich lauten Kenney-Quellen aufeinander ein; pitch_jitter
## (± um 1.0) nimmt häufigen Sounds die Monotonie.

const BASE_DIR := "res://assets/audio/sfx"

## id → {file, volume_db (Default 0.0), pitch_jitter (Default 0.0)}.
const SOUNDS := {
	# ── UI (Buttons/Panels/Toggles — Verdrahtung P2/P3 via Handoff) ──
	"ui_click": {"file": "click_001.ogg", "volume_db": -6.0},
	"ui_chip": {"file": "click_003.ogg", "volume_db": -8.0},
	"ui_back": {"file": "back_002.ogg", "volume_db": -6.0},
	"ui_confirm": {"file": "confirmation_002.ogg", "volume_db": -5.0},
	"ui_error": {"file": "error_004.ogg", "volume_db": -6.0},
	"ui_open": {"file": "open_001.ogg", "volume_db": -6.0},
	"ui_close": {"file": "close_001.ogg", "volume_db": -6.0},
	"ui_toggle": {"file": "switch_002.ogg", "volume_db": -7.0},
	"ui_tick": {"file": "tick_002.ogg", "volume_db": -6.0},
	# ── Minigame-Framework (Countdown/Ergebnis) ──
	"mg_go": {"file": "confirmation_001.ogg", "volume_db": -4.0},
	"mg_win": {"file": "confirmation_003.ogg", "volume_db": -3.0},
	"mg_lose": {"file": "error_008.ogg", "volume_db": -5.0},
	# ── teaParty / carrotCatch ──
	"mg_perfect": {"file": "glass_005.ogg", "volume_db": -4.0, "pitch_jitter": 0.04},
	"mg_good": {"file": "drop_002.ogg", "volume_db": -6.0, "pitch_jitter": 0.08},
	"mg_golden": {"file": "glass_006.ogg", "volume_db": -3.0},
	"mg_combo": {"file": "pluck_002.ogg", "volume_db": -5.0},
	"mg_spill": {"file": "impactPlate_medium_000.ogg", "volume_db": -8.0, "pitch_jitter": 0.06},
	"mg_junk": {"file": "impactMetal_light_002.ogg", "volume_db": -8.0, "pitch_jitter": 0.06},
	# ── GvZ (Gefechts-Momente) ──
	"gvz_place": {"file": "impactPlank_medium_000.ogg", "volume_db": -7.0, "pitch_jitter": 0.08},
	"gvz_shovel": {"file": "impactMining_002.ogg", "volume_db": -7.0},
	"gvz_boom": {"file": "impactPlate_heavy_002.ogg", "volume_db": -4.0, "pitch_jitter": 0.05},
	"gvz_mower": {"file": "impactMetal_heavy_001.ogg", "volume_db": -5.0},
	"gvz_pop": {"file": "impactGeneric_light_001.ogg", "volume_db": -9.0, "pitch_jitter": 0.1},
	"gvz_balloon": {"file": "impactGlass_light_001.ogg", "volume_db": -8.0, "pitch_jitter": 0.08},
	"gvz_collect": {"file": "glass_004.ogg", "volume_db": -7.0, "pitch_jitter": 0.06},
	"gvz_wave": {"file": "impactBell_heavy_002.ogg", "volume_db": -7.0},
	"gvz_boss": {"file": "impactBell_heavy_004.ogg", "volume_db": -4.0},
	# ── Haus/Türen/Baumodus (Verdrahtung P3 via Handoff) ──
	"door_knock": {"file": "impactPlank_medium_003.ogg", "volume_db": -6.0, "pitch_jitter": 0.1},
	"build_hammer": {"file": "impactPlank_medium_001.ogg", "volume_db": -6.0, "pitch_jitter": 0.1},
}


## Eintrag zu einer Id ({} = unbekannt).
static func entry(id: String) -> Dictionary:
	return SOUNDS.get(id, {})


## Ressourcen-Pfad zu einer Id ("" = unbekannt).
static func path(id: String) -> String:
	var row: Dictionary = SOUNDS.get(id, {})
	if row.is_empty():
		return ""
	return "%s/%s" % [BASE_DIR, row["file"]]


## Alle bekannten Ids (für Tests/Preload).
static func ids() -> Array:
	return SOUNDS.keys()

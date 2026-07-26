class_name SfxMap
extends RefCounted
## Zentrale SFX-Landkarte (W4-P1; FIX-4 UI-Neuvertonung): semantische
## Sound-Id → OGG unter assets/audio/sfx/. Einzige Quelle der Wahrheit für
## AudioDirector.play(id) — neue Sounds HIER eintragen, nirgends Pfade
## hartkodieren. volume_db mischt unterschiedlich laute Quellen aufeinander
## ein; pitch_jitter (± um 1.0) nimmt häufigen Sounds die Monotonie.
##
## FIX-4: Die UI-Familie klingt jetzt nach dem weichen, runden
## Animal-Crossing-Gefühl — gestimmte Sinus-/Glocken-Plucks mit weichem
## Attack, KEINE harten Klicks (assets/audio/sfx/soft/, generiert per
## tools-Skript; CC0, selbst erzeugt). Die Kenney-Samples bleiben für
## Minigame-/Impact-Momente (LICENSE-kenney-cc0.txt).

const BASE_DIR := "res://assets/audio/sfx"

## Pflicht-UI-Ids (FIX-4-Kontrakt — Tests prüfen Existenz + Dateien):
## jedes UI-Element im Spiel soll eine dieser Ids feuern.
const UI_REQUIRED_IDS: Array[String] = [
	"ui_click",
	"ui_chip",
	"ui_back",
	"ui_confirm",
	"ui_error",
	"ui_open",
	"ui_close",
	"ui_toggle",
	"ui_tick",
	"ui_buy",
	"ui_coins",
	"ui_levelup",
	"ui_sticker",
	"ui_toast",
]

## id → {file, volume_db (Default 0.0), pitch_jitter (Default 0.0)}.
const SOUNDS := {
	# ── UI (FIX-4: weiche, gestimmte Plucks — Referenz Animal Crossing) ──
	"ui_click": {"file": "soft/soft_tap.ogg", "volume_db": -4.0, "pitch_jitter": 0.02},
	"ui_chip": {"file": "soft/soft_chip.ogg", "volume_db": -6.0, "pitch_jitter": 0.02},
	"ui_back": {"file": "soft/soft_back.ogg", "volume_db": -4.0},
	"ui_confirm": {"file": "soft/soft_confirm.ogg", "volume_db": -3.0},
	"ui_error": {"file": "soft/soft_error.ogg", "volume_db": -4.0},
	"ui_open": {"file": "soft/soft_open.ogg", "volume_db": -6.0},
	"ui_close": {"file": "soft/soft_close.ogg", "volume_db": -6.0},
	"ui_toggle": {"file": "soft/soft_toggle.ogg", "volume_db": -5.0},
	"ui_tick": {"file": "soft/soft_tick.ogg", "volume_db": -7.0},
	"ui_buy": {"file": "soft/soft_buy.ogg", "volume_db": -3.0},
	"ui_coins": {"file": "soft/soft_coins.ogg", "volume_db": -4.0, "pitch_jitter": 0.03},
	"ui_levelup": {"file": "soft/soft_levelup.ogg", "volume_db": -2.0},
	"ui_sticker": {"file": "soft/soft_sticker.ogg", "volume_db": -4.0},
	"ui_toast": {"file": "soft/soft_toast.ogg", "volume_db": -6.0},
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

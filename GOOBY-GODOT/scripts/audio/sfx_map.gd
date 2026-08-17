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
##
## RW-8: Die Ranch-Familie (`ranch_*`) mappt ALLE 23 DLC-Sounds aus
## assets/ranch/audio/sfx/ (Quellen/Lizenzen: License-audio.md dort).
## file-Einträge dürfen dafür absolute res://-Pfade sein — path() reicht
## sie unverändert durch. Trigger-Logik (Untergrund→Huf, Reaktionen,
## Ambience-Mix) lebt in RanchAudio (scripts/audio/ranch_audio.gd).
##
## EF-2 (EVAL-1 S1/S4 + Abdeckungslücken 2.5): Quelldateien sind auf
## Peak ≤ −1 dBFS normalisiert, die volume_db-Trims auf eine gemeinsame
## Effekt-Ebene (~−22 dBFS eff.) eingemessen — tools/audio/ef2_gen_sfx.py
## + ef2_apply_sfx_trims.py, Wache: tests/unit/test_ef2_audio_levels.gd.
## NEU für die stummen Interaktionen (Wiring: Besitzer der jeweiligen
## Szene, Sound-Ids sind hier fertig gemappt):
##   care_wasser (Dusch-Loop, via Audio.start_loop/stop_loop),
##   care_buersten (Zahnputz-Loop), care_spuelung (Klo/Abfluss),
##   care_erfolg (Pflege-Abschluss-Pluck, D6),
##   pet_squish (Streichel-Squish pro Tap, D5),
##   step_tap (Gooby-Schritte, D4/F8), nom_nom (Füttern/Kauen, D1),
##   travel_whoosh_auf/_zu (Reise-Veil statt ui_open/close, F9).
## gvz_collect klingt jetzt nach weichem 1,2-kHz-Pluck (S4), mg_win nach
## Dur-Dreiklang (S6) — beide aus der soft/-Synthese.

const BASE_DIR := "res://assets/audio/sfx"
const RANCH_DIR := "res://assets/ranch/audio/sfx"

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
	"mg_go": {"file": "confirmation_001.ogg", "volume_db": -6.5},
	"mg_win": {"file": "soft/soft_win.ogg", "volume_db": -3.5},
	"mg_lose": {"file": "error_008.ogg", "volume_db": -1.5},
	# ── teaParty / carrotCatch ──
	"mg_perfect": {"file": "glass_005.ogg", "volume_db": -2.0, "pitch_jitter": 0.04},
	"mg_good": {"file": "drop_002.ogg", "volume_db": -2.5, "pitch_jitter": 0.08},
	"mg_golden": {"file": "glass_006.ogg", "volume_db": -1.5},
	"mg_combo": {"file": "pluck_002.ogg", "volume_db": -1.5},
	"mg_spill": {"file": "impactPlate_medium_000.ogg", "volume_db": -0.5, "pitch_jitter": 0.06},
	"mg_junk": {"file": "impactMetal_light_002.ogg", "volume_db": -3.0, "pitch_jitter": 0.06},
	# ── GvZ (Gefechts-Momente) ──
	"gvz_place": {"file": "impactPlank_medium_000.ogg", "volume_db": -2.0, "pitch_jitter": 0.08},
	"gvz_shovel": {"file": "impactMining_002.ogg", "volume_db": -1.0},
	"gvz_boom": {"file": "impactPlate_heavy_002.ogg", "volume_db": -1.5, "pitch_jitter": 0.05},
	"gvz_mower": {"file": "impactMetal_heavy_001.ogg", "volume_db": -0.5},
	"gvz_pop": {"file": "impactGeneric_light_001.ogg", "volume_db": -4.0, "pitch_jitter": 0.1},
	"gvz_balloon": {"file": "impactGlass_light_001.ogg", "volume_db": -1.5, "pitch_jitter": 0.08},
	"gvz_collect": {"file": "soft/soft_collect.ogg", "volume_db": -4.0, "pitch_jitter": 0.06},
	"gvz_wave": {"file": "impactBell_heavy_002.ogg", "volume_db": -1.5},
	"gvz_boss": {"file": "impactBell_heavy_004.ogg", "volume_db": 0.0},
	# ── Haus/Türen/Baumodus (Verdrahtung P3 via Handoff) ──
	"door_knock": {"file": "impactPlank_medium_003.ogg", "volume_db": -4.0, "pitch_jitter": 0.1},
	"build_hammer": {"file": "impactPlank_medium_001.ogg", "volume_db": -5.0, "pitch_jitter": 0.1},
	# ── Pflege (EVAL-1 D6/F7 — Dusche/Zähne/Klo klingen jetzt) ──
	"care_wasser": {"file": "foley/care_wasser.ogg", "volume_db": -6.0},
	"care_buersten": {"file": "foley/care_buersten.ogg", "volume_db": -1.0},
	"care_spuelung": {"file": "foley/care_spuelung.ogg", "volume_db": -4.0},
	"care_erfolg": {"file": "soft/soft_care_erfolg.ogg", "volume_db": -4.5},
	# ── Gooby-Interaktion (D1/D4/D5/F8) ──
	"pet_squish": {"file": "foley/pet_squish.ogg", "volume_db": -7.0, "pitch_jitter": 0.05},
	"step_tap": {"file": "foley/step_tap.ogg", "volume_db": -12.0, "pitch_jitter": 0.1},
	"nom_nom": {"file": "foley/nom_nom.ogg", "volume_db": -5.5, "pitch_jitter": 0.1},
	# ── Reise-Whoosh (F9 — Veil-Reisen statt ui_open/ui_close) ──
	"travel_whoosh_auf": {"file": "foley/travel_whoosh_auf.ogg", "volume_db": -3.0},
	"travel_whoosh_zu": {"file": "foley/travel_whoosh_zu.ogg", "volume_db": -4.0},
	# ── Ranch-DLC (RW-8): Hufschlag je Untergrund (Einzelschritt + Loops) ──
	"ranch_huf_gras":
	{"file": RANCH_DIR + "/huf_gras.ogg", "volume_db": -6.0, "pitch_jitter": 0.06},
	"ranch_huf_sand":
	{"file": RANCH_DIR + "/huf_sand.ogg", "volume_db": -5.0, "pitch_jitter": 0.06},
	"ranch_huf_holz":
	{"file": RANCH_DIR + "/huf_holz.ogg", "volume_db": -5.5, "pitch_jitter": 0.05},
	"ranch_huf_stein":
	{"file": RANCH_DIR + "/huf_stein.ogg", "volume_db": -4.0, "pitch_jitter": 0.05},
	"ranch_huf_trab": {"file": RANCH_DIR + "/huf_trab_loop.ogg", "volume_db": -8.0},
	"ranch_huf_galopp": {"file": RANCH_DIR + "/huf_galopp_loop.ogg", "volume_db": -5.0},
	# ── Pferdelaute (Reaktionen: Begrüßung/Bindung/Erschöpfung) ──
	"ranch_wiehern_a":
	{"file": RANCH_DIR + "/pferd_wiehern_a.ogg", "volume_db": -5.0, "pitch_jitter": 0.04},
	"ranch_wiehern_b":
	{"file": RANCH_DIR + "/pferd_wiehern_b.ogg", "volume_db": -5.0, "pitch_jitter": 0.04},
	"ranch_schnauben_a":
	{"file": RANCH_DIR + "/pferd_schnauben_a.ogg", "volume_db": -6.0, "pitch_jitter": 0.05},
	"ranch_schnauben_b":
	{"file": RANCH_DIR + "/pferd_schnauben_b.ogg", "volume_db": -6.0, "pitch_jitter": 0.05},
	# ── Pflege-Foley ──
	"ranch_sattel": {"file": RANCH_DIR + "/sattel_aufsteigen.ogg", "volume_db": -6.0},
	"ranch_buerste":
	{"file": RANCH_DIR + "/buerste_striegeln.ogg", "volume_db": -6.0, "pitch_jitter": 0.05},
	"ranch_heu": {"file": RANCH_DIR + "/heu_rascheln.ogg", "volume_db": -7.0, "pitch_jitter": 0.06},
	# ── Ambience-Loops (Mix je Zone/Wetter/Tageszeit: RanchAudio) ──
	"ranch_ambience_wind": {"file": RANCH_DIR + "/ambience_wind.ogg", "volume_db": -12.0},
	"ranch_ambience_regen": {"file": RANCH_DIR + "/ambience_regen.ogg", "volume_db": -10.0},
	"ranch_ambience_gewitter": {"file": RANCH_DIR + "/ambience_gewitter.ogg", "volume_db": -8.0},
	"ranch_ambience_voegel": {"file": RANCH_DIR + "/ambience_voegel.ogg", "volume_db": -12.0},
	"ranch_ambience_bach": {"file": RANCH_DIR + "/ambience_bach.ogg", "volume_db": -12.0},
	"ranch_ambience_grillen": {"file": RANCH_DIR + "/ambience_grillen.ogg", "volume_db": -12.0},
	# ── Turnier: Fanfaren + Publikum ──
	"ranch_fanfare": {"file": RANCH_DIR + "/turnier_fanfare.ogg", "volume_db": -4.0},
	"ranch_fanfare_sieg": {"file": RANCH_DIR + "/turnier_fanfare_sieg.ogg", "volume_db": -3.0},
	"ranch_menge_jubel": {"file": RANCH_DIR + "/menge_jubel.ogg", "volume_db": -6.0},
	"ranch_menge_gemurmel": {"file": RANCH_DIR + "/menge_gemurmel.ogg", "volume_db": -10.0},
	# ── Klangbetten (W18/J5, I-33): Orts-Ambience-Loops, gefahren von
	# Klangbett (scripts/audio/klangbett.gd). Eigen-Synthese, CC0 —
	# tools/audio/gen_klangbetten.py + ambient/LICENSE.md. Trims setzen
	# die Betten eff. auf ≈ −34…−36 dBFS: DEUTLICH unter Musik-Playback
	# (≈ −30) und SFX-Median (≈ −22,6) — Wache: test_j5_klangbett.gd.
	"bett_kamin": {"file": "ambient/bett_kamin.ogg", "volume_db": -14.0},
	"bett_uhr": {"file": "ambient/bett_uhr.ogg", "volume_db": -9.0},
	"bett_voegel": {"file": "ambient/bett_voegel.ogg", "volume_db": -15.0},
	"bett_wind": {"file": "ambient/bett_wind.ogg", "volume_db": -15.0},
	"bett_stadt": {"file": "ambient/bett_stadt.ogg", "volume_db": -14.0},
	"bett_laden": {"file": "ambient/bett_laden.ogg", "volume_db": -16.0},
}

## Pflicht-Ids des Ranch-DLC (RW-8-Kontrakt — Tests prüfen Existenz +
## Dateien; deckt ALLE 23 Dateien unter assets/ranch/audio/sfx ab).
const RANCH_REQUIRED_IDS: Array[String] = [
	"ranch_huf_gras",
	"ranch_huf_sand",
	"ranch_huf_holz",
	"ranch_huf_stein",
	"ranch_huf_trab",
	"ranch_huf_galopp",
	"ranch_wiehern_a",
	"ranch_wiehern_b",
	"ranch_schnauben_a",
	"ranch_schnauben_b",
	"ranch_sattel",
	"ranch_buerste",
	"ranch_heu",
	"ranch_ambience_wind",
	"ranch_ambience_regen",
	"ranch_ambience_gewitter",
	"ranch_ambience_voegel",
	"ranch_ambience_bach",
	"ranch_ambience_grillen",
	"ranch_fanfare",
	"ranch_fanfare_sieg",
	"ranch_menge_jubel",
	"ranch_menge_gemurmel",
]


## Eintrag zu einer Id ({} = unbekannt).
static func entry(id: String) -> Dictionary:
	return SOUNDS.get(id, {})


## Ressourcen-Pfad zu einer Id ("" = unbekannt). Absolute res://-Einträge
## (Ranch-Familie) gehen unverändert durch, alles andere hängt an BASE_DIR.
static func path(id: String) -> String:
	var row: Dictionary = SOUNDS.get(id, {})
	if row.is_empty():
		return ""
	var file := str(row["file"])
	if file.begins_with("res://"):
		return file
	return "%s/%s" % [BASE_DIR, file]


## Alle bekannten Ids (für Tests/Preload).
static func ids() -> Array:
	return SOUNDS.keys()

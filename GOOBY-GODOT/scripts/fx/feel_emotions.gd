class_name FeelEmotions
extends RefCounted
## FEEL-AC — Katalog der 12 inszenierten Emotionen (Animal-Crossing-Lesbarkeit).
## PURE Daten + Helfer, headless testbar. Jede Emotion ist ein komplettes
## Paket aus:
##  gesicht: Mix auf den 8 vorhandenen emotion_*-Shapekeys (Rig-Vertrag —
##           KEINE neuen Shapekey-Namen, nur neue KOMBINATIONEN)
##  extra:   Zusatz-Shapekeys (mouth_open, eye_size als Delta-Boost) — werden
##           vom GoobyFeelings-Layer NACH dem Rig geschrieben und beim Ende
##           exakt restauriert
##  pose:    Körperpose (ear_l/ear_r/head/arms — dieselben Kanäle wie
##           GoobyRig.EMOTION_POSES, via set_expression_override)
##  bewegung: Ganzkörper-Beat (zucken/huepfen/zittern/… — GoobyFeelings)
##  symbol:  Emote-Symbol über dem Kopf (assets/fx/symbols/<id>.svg,
##           saubere Vektor-Symbole im GOOBY-Stil, keine Emojis)
##  sfx:     SfxMap-Id ("" = stumm), dauer_s: Anzeigedauer,
##  stark:   true = Moment-Regie (Kamera-Zoom/Zeitlupe/Farbakzent, sparsam),
##  farbe:   Akzentfarbe für Regie/Post-FX-Puls.

const SYMBOL_DIR := "res://assets/fx/symbols"

## Reihenfolge = Doku-Reihenfolge (Schreck zuerst — ausdrücklich gewünscht).
const EMOTIONEN: Array[String] = [
	"schreck",
	"freude",
	"begeisterung",
	"ueberraschung",
	"verlegenheit",
	"trotz",
	"traurigkeit",
	"muedigkeit",
	"neugier",
	"stolz",
	"angst",
	"verliebtheit",
]

## Merkmals-Kanäle für den Unterscheidbarkeits-Test (Tests bauen daraus
## pro Emotion einen Vektor und prüfen paarweise Abstand).
const GESICHTS_KANAELE: Array[String] = [
	"neutral", "happy", "sad", "sleepy", "ecstatic", "angry", "scared", "dizzy"
]
const EXTRA_KANAELE: Array[String] = ["mouth_open", "eye_size"]
const POSE_KANAELE: Array[String] = ["ear_l", "ear_r", "head", "arms"]

const DEFS := {
	"schreck":
	{
		"gesicht": {"scared": 1.0},
		"extra": {"mouth_open": 0.55, "eye_size": 0.5},
		"pose": {"ear_l": 0.85, "ear_r": 0.85, "head": -0.08, "arms": 0.9},
		"bewegung": "zucken",
		"symbol": "ausrufezeichen",
		"sfx": "ui_error",
		"dauer_s": 2.4,
		"stark": true,
		"farbe": Color("#CFE0FF"),
	},
	"freude":
	{
		"gesicht": {"happy": 1.0},
		"extra": {},
		"pose": {"ear_l": -0.05, "ear_r": -0.05, "head": 0.0, "arms": 0.0},
		"bewegung": "wippen",
		"symbol": "note",
		"sfx": "ui_confirm",
		"dauer_s": 3.0,
		"stark": false,
		"farbe": Color("#FFD166"),
	},
	"begeisterung":
	{
		"gesicht": {"ecstatic": 1.0},
		"extra": {"mouth_open": 0.35},
		"pose": {"ear_l": -0.12, "ear_r": -0.12, "head": -0.05, "arms": 0.0},
		"bewegung": "huepfen",
		"symbol": "funkeln",
		"sfx": "ui_levelup",
		"dauer_s": 3.2,
		"stark": true,
		"farbe": Color("#FFE98A"),
	},
	"ueberraschung":
	{
		"gesicht": {"scared": 0.4, "ecstatic": 0.3},
		"extra": {"mouth_open": 0.45, "eye_size": 0.6},
		"pose": {"ear_l": -0.1, "ear_r": -0.1, "head": -0.06, "arms": 0.3},
		"bewegung": "aufrichten",
		"symbol": "blitzstern",
		"sfx": "ui_toast",
		"dauer_s": 2.6,
		"stark": false,
		"farbe": Color("#FFF3B0"),
	},
	"verlegenheit":
	{
		"gesicht": {"happy": 0.35, "sad": 0.3},
		"extra": {"mouth_open": 0.08},
		"pose": {"ear_l": 0.55, "ear_r": 0.25, "head": 0.3, "arms": 0.15},
		"bewegung": "abwenden",
		"symbol": "wirbel",
		"sfx": "pet_squish",
		"dauer_s": 3.0,
		"stark": false,
		"farbe": Color("#F58BAF"),
	},
	"trotz":
	{
		"gesicht": {"angry": 1.0},
		"extra": {},
		"pose": {"ear_l": 0.75, "ear_r": 0.05, "head": 0.12, "arms": 0.0},
		"bewegung": "stampfen",
		"symbol": "wolke",
		"sfx": "mg_junk",
		"dauer_s": 2.8,
		"stark": false,
		"farbe": Color("#AEB6C4"),
	},
	"traurigkeit":
	{
		"gesicht": {"sad": 1.0},
		"extra": {},
		"pose": {"ear_l": 0.75, "ear_r": 0.75, "head": 0.3, "arms": 1.0},
		"bewegung": "sacken",
		"symbol": "traene",
		"sfx": "ui_close",
		"dauer_s": 3.6,
		"stark": false,
		"farbe": Color("#4A90D9"),
	},
	"muedigkeit":
	{
		"gesicht": {"sleepy": 1.0},
		"extra": {"mouth_open": 0.25},
		"pose": {"ear_l": 0.4, "ear_r": 0.32, "head": 0.14, "arms": 0.5},
		"bewegung": "nicken",
		"symbol": "zzz",
		"sfx": "",
		"dauer_s": 3.6,
		"stark": false,
		"farbe": Color("#9C89D9"),
	},
	"neugier":
	{
		"gesicht": {"happy": 0.3},
		"extra": {"eye_size": 0.45},
		"pose": {"ear_l": -0.1, "ear_r": 0.35, "head": 0.04, "arms": 0.0},
		"bewegung": "neigen",
		"symbol": "fragezeichen",
		"sfx": "ui_tick",
		"dauer_s": 3.0,
		"stark": false,
		"farbe": Color("#FFB733"),
	},
	"stolz":
	{
		"gesicht": {"happy": 0.6, "ecstatic": 0.4},
		"extra": {},
		"pose": {"ear_l": -0.1, "ear_r": -0.1, "head": -0.12, "arms": 0.0},
		"bewegung": "strecken",
		"symbol": "stern",
		"sfx": "mg_win",
		"dauer_s": 3.2,
		"stark": true,
		"farbe": Color("#FFD166"),
	},
	"angst":
	{
		"gesicht": {"scared": 1.0},
		"extra": {"eye_size": 0.3},
		"pose": {"ear_l": 0.7, "ear_r": 0.7, "head": 0.26, "arms": 0.35},
		"bewegung": "zittern",
		"symbol": "schweiss",
		"sfx": "",
		"dauer_s": 4.0,
		"stark": false,
		"farbe": Color("#6EC6F5"),
	},
	"verliebtheit":
	{
		"gesicht": {"ecstatic": 0.55, "happy": 0.45},
		"extra": {"mouth_open": 0.2},
		"pose": {"ear_l": 0.18, "ear_r": 0.12, "head": 0.02, "arms": 0.0},
		"bewegung": "schweben",
		"symbol": "herz",
		"sfx": "ui_sticker",
		"dauer_s": 3.6,
		"stark": true,
		"farbe": Color("#FF6FA0"),
	},
}


static func alle() -> Array[String]:
	return EMOTIONEN.duplicate()


static func kennt(id: String) -> bool:
	return DEFS.has(id)


static func def_of(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func ist_stark(id: String) -> bool:
	return bool(def_of(id).get("stark", false))


static func dauer_s(id: String) -> float:
	return float(def_of(id).get("dauer_s", 3.0))


static func farbe(id: String) -> Color:
	var def := def_of(id)
	if def.is_empty():
		return Color.WHITE
	return def["farbe"]


static func symbol_pfad(symbol: String) -> String:
	return "%s/%s.svg" % [SYMBOL_DIR, symbol]


## Dominante Gesichts-Emotion (Rig-Id) — für die Stimm-Modulation der
## Sprech-Zeile (GoobyVoice.modulation kennt die 8 Rig-Emotionen).
static func stimm_emotion(id: String) -> String:
	var def := def_of(id)
	if def.is_empty():
		return "neutral"
	var gesicht: Dictionary = def["gesicht"]
	var beste := "neutral"
	var wert := 0.0
	for kanal: String in gesicht:
		if float(gesicht[kanal]) > wert:
			wert = float(gesicht[kanal])
			beste = kanal
	return beste


## Merkmals-Vektor (Gesicht + Extra + Pose) — Tests messen darüber, dass
## alle 12 Emotionen UNTERSCHEIDBARE Shape-Key-/Pose-Kombinationen setzen.
static func merkmale(id: String) -> PackedFloat32Array:
	var def := def_of(id)
	var out := PackedFloat32Array()
	if def.is_empty():
		return out
	var gesicht: Dictionary = def["gesicht"]
	for kanal in GESICHTS_KANAELE:
		out.append(float(gesicht.get(kanal, 0.0)))
	var extra: Dictionary = def["extra"]
	for kanal in EXTRA_KANAELE:
		out.append(float(extra.get(kanal, 0.0)))
	var pose: Dictionary = def["pose"]
	for kanal in POSE_KANAELE:
		out.append(float(pose.get(kanal, 0.0)))
	return out

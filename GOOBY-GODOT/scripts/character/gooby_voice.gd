class_name GoobyVoice
extends Node3D
## Gooby-Stimme (W1b): Animal-Crossing-Gebrabbel aus den gebackenen
## Silben-WAVs (assets/audio/voice/*.wav, via tools/audio/gen_syllables.py).
##
## API:
##   sagt(text, emotion := "neutral")  — startet Gebrabbel (bricht laufendes ab)
##   ist_am_reden()                    — läuft gerade Gebrabbel?
## Signale:
##   silbe(index, anzahl)  — pro Silben-Onset (Lipsync: GoobyRig.babble_pulse)
##   fertig                — Gebrabbel zu Ende (auch bei Abbruch)
##
## Design nach F-gooby §1.6: 4-Spieler-Pool, ±12 % Pitch pro Silbe, Hash
## Buchstabe→Silbe (deterministisch pro Wort), Rate ~11 Silben/s, Satzende =
## Pitch-Bogen runter, '?' = rauf; Emotion moduliert Basis-Pitch.
##
## SEELE-2: Zusätzlich moduliert die DURCHGEHENDE Stimmung (SoulMood, 0..100
## via set_stimmung) Tonhöhe, Tempo UND Länge des Gebrabbels — man hört,
## wie es Gooby geht: elend = tiefer, langsamer, wortkarg; selig = hell und
## flott. Die Ableitung ist pur (modulation/kuerze_plan) und damit testbar.

signal silbe(index: int, anzahl: int)
signal fertig

const VOICE_DIR := "res://assets/audio/voice"
const RATE := 11.0  # Silben pro Sekunde
const PITCH_JITTER := 0.12  # ±12 %
const POOL_SIZE := 4
## EVAL-1 S3: Gebrabbel läuft über den Voice-Bus (vorher Master — der
## Settings-Regler "Stimme" war wirkungslos). Die Silben-WAVs sind auf
## −16 dBFS RMS gemastert (tools/audio/ef2_gen_sfx.py); der Trim setzt
## die Stimme auf die Effekt-Ebene (eff. ≈ −22 dBFS) statt lautester
## Sound im Spiel zu sein.
const VOICE_BUS := &"Voice"
const VOICE_TRIM_DB := -6.0
const EMOTION_PITCH: Dictionary = {
	"neutral": 1.0,
	"happy": 1.15,
	"ecstatic": 1.2,
	"sad": 0.8,
	"sleepy": 0.85,
	"angry": 0.9,
	"scared": 1.1,
	"dizzy": 0.95,
}
## Kurzatmig, aber nie stumm: gekürzte Sätze behalten mindestens so viele
## Silben (SEELE-2, kuerze_plan).
const MIN_SILBEN := 4

var _streams: Array[AudioStream] = []
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_index := 0
var _token := 0  # neue sagt()-Aufrufe entwerten laufende Schleifen
var _talking := false
var _stimmung := SoulMood.DEFAULT_WERT


func _ready() -> void:
	_load_streams()
	_ensure_voice_bus()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.name = "Voice%d" % i
		player.max_distance = 30.0
		player.bus = VOICE_BUS
		player.volume_db = VOICE_TRIM_DB
		add_child(player)
		_pool.append(player)


## Ohne AudioDirector (Showcase/Tests) existiert der Voice-Bus evtl. noch
## nicht — dann anlegen, sonst fiele der Player still auf Master zurück.
func _ensure_voice_bus() -> void:
	if AudioServer.get_bus_index(VOICE_BUS) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, VOICE_BUS)
	AudioServer.set_bus_send(idx, &"Master")


func _load_streams() -> void:
	_streams.clear()
	var dir := DirAccess.open(VOICE_DIR)
	if dir == null:
		push_error("GoobyVoice: Silben-Ordner fehlt: %s" % VOICE_DIR)
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".wav"):
			files.append(entry)
		elif entry.ends_with(".wav.import"):  # exportierte Builds listen .import
			files.append(entry.trim_suffix(".import"))
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for file in files:
		var stream: AudioStream = load(VOICE_DIR + "/" + file)
		if (
			stream != null
			and not _streams.any(func(existing: AudioStream) -> bool: return existing == stream)
		):
			_streams.append(stream)


func syllable_count() -> int:
	return _streams.size()


func ist_am_reden() -> bool:
	return _talking


## Durchgehende Stimmung (0..100, SoulMood-Skala) — färbt jedes Gebrabbel.
func set_stimmung(wert: float) -> void:
	_stimmung = clampf(wert, 0.0, 100.0)


func stimmung() -> float:
	return _stimmung


## PURE (SEELE-2): Stimm-Parameter aus Stimmung + Moment-Emotion.
## pitch = Emotions-Grundton × Laune-Ton; tempo skaliert die Silbenrate
## (traurig bleibt zusätzlich gedehnt); laenge 0..1 kürzt den Satz.
static func modulation(stimmung_wert: float, emotion: String) -> Dictionary:
	var laune := SoulMood.stimme(stimmung_wert)
	return {
		"pitch": float(EMOTION_PITCH.get(emotion, 1.0)) * float(laune["pitch"]),
		"tempo": float(laune["tempo"]) * (0.85 if emotion == "sad" else 1.0),
		"laenge": float(laune["laenge"]),
	}


## PURE (SEELE-2): Silben-Plan auf laenge (0..1) kürzen — ein matter Gooby
## brabbelt kurz. Nie unter MIN_SILBEN klingende Silben, Pausen zählen nicht.
static func kuerze_plan(plan: Array[Dictionary], laenge: float) -> Array[Dictionary]:
	if laenge >= 1.0:
		return plan
	var klingend := 0
	for step in plan:
		if not step["pause"]:
			klingend += 1
	var behalten := maxi(MIN_SILBEN, int(ceilf(klingend * clampf(laenge, 0.0, 1.0))))
	if behalten >= klingend:
		return plan
	var out: Array[Dictionary] = []
	var gezaehlt := 0
	for step in plan:
		if not step["pause"]:
			if gezaehlt >= behalten:
				break
			gezaehlt += 1
		out.append(step)
	return out


## Text → Gebrabbel. Läuft asynchron; ein neuer Aufruf bricht den alten ab.
func sagt(text: String, emotion: String = "neutral") -> void:
	_token += 1
	_babble(text, emotion, _token)


func _babble(text: String, emotion: String, token: int) -> void:
	if _streams.is_empty():
		fertig.emit()
		return
	var stimme := modulation(_stimmung, emotion)
	var plan := kuerze_plan(_plan_syllables(text), float(stimme["laenge"]))
	if plan.is_empty():
		fertig.emit()
		return
	_talking = true
	var base_pitch: float = stimme["pitch"]
	var question := text.strip_edges().ends_with("?")
	var interval := 1.0 / (RATE * float(stimme["tempo"]))
	var count := plan.size()
	for i in count:
		if token != _token or not is_inside_tree():
			break
		var step: Dictionary = plan[i]
		if not step["pause"]:
			# Satzende-Bogen über die letzten 3 Silben: runter, bei '?' rauf.
			var arc := 1.0
			var from_end := count - 1 - i
			if from_end < 3:
				var lift := (3 - from_end) * 0.06
				arc = 1.0 + lift if question else 1.0 - lift
			var jitter := 1.0 + _hash01(step["seed"]) * 2.0 * PITCH_JITTER - PITCH_JITTER
			var player := _pool[_pool_index]
			_pool_index = (_pool_index + 1) % POOL_SIZE
			player.stream = _streams[step["syllable"] % _streams.size()]
			player.pitch_scale = base_pitch * arc * jitter
			player.play()
			silbe.emit(i, count)
		await get_tree().create_timer(interval).timeout
	if token == _token:
		_talking = false
		fertig.emit()


## Pro Buchstabe eine Silbe (Hash Buchstabe+Wortindex → deterministisch pro
## Wort); Leerzeichen/Satzzeichen = kurze Pause.
func _plan_syllables(text: String) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var word_index := 0
	for i in text.length():
		var ch := text.unicode_at(i)
		if ch == 32 or ch == 10:  # Wortgrenze → Pause
			word_index += 1
			plan.append({"pause": true, "syllable": 0, "seed": 0})
		elif (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch >= 128:
			var seed := ch * 31 + word_index * 7
			plan.append({"pause": false, "syllable": seed % 97, "seed": seed})
	return plan


func _hash01(seed: int) -> float:
	return float((seed * 2654435761) % 1000) / 999.0

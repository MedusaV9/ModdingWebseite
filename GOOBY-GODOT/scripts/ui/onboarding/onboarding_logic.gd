class_name OnboardingLogic
extends RefCounted
## PURE Onboarding-Statemaschine (headless testbar): Name ist Pflicht,
## Spitzname optional (Default „Gooby“), Char-Editor überspringbar.
## Ergebnis-Dict-Form ist Vertrag mit W1d (handoffs/W1c-needs-from-state.md).

enum Step { WELCOME, NICKNAME, EDITOR, DONE, FINISHED }

const NAME_MAX_LEN := 24
const DEFAULT_NICKNAME := "Gooby"
const EDITOR_DEFAULTS := {
	"eyes_apart": 0.0,
	"eye_scale": 1.0,
	"ear_len": 1.0,
	"chubby": 0.0,
}
const EDITOR_RANGES := {
	"eyes_apart": Vector2(-1.0, 1.0),
	"eye_scale": Vector2(0.7, 1.4),
	"ear_len": Vector2(0.7, 1.4),
	"chubby": Vector2(0.0, 1.0),
}

var step: Step = Step.WELCOME
var player_name := ""
var gooby_nickname := DEFAULT_NICKNAME
var editor: Dictionary = EDITOR_DEFAULTS.duplicate()


## Name abgeben. Leer/nur Leerzeichen → false, Step bleibt WELCOME.
func submit_name(raw: String) -> bool:
	var trimmed := raw.strip_edges().left(NAME_MAX_LEN)
	if trimmed.is_empty():
		return false
	player_name = trimmed
	step = Step.NICKNAME
	return true


## Spitzname abgeben — leer → Default „Gooby“. Danach EDITOR.
func submit_nickname(raw: String) -> void:
	if step != Step.NICKNAME:
		return
	var trimmed := raw.strip_edges().left(NAME_MAX_LEN)
	gooby_nickname = DEFAULT_NICKNAME if trimmed.is_empty() else trimmed
	step = Step.EDITOR


## Editor-Wert setzen (geclampt auf den erlaubten Bereich).
func set_editor_value(key: String, value: float) -> bool:
	if not EDITOR_RANGES.has(key):
		return false
	var r: Vector2 = EDITOR_RANGES[key]
	editor[key] = clampf(value, r.x, r.y)
	return true


## Editor überspringen → Defaults bleiben, weiter zu DONE.
func skip_editor() -> void:
	if step != Step.EDITOR:
		return
	editor = EDITOR_DEFAULTS.duplicate()
	step = Step.DONE


## Editor bestätigen (Slider-Werte bleiben) → DONE.
func confirm_editor() -> void:
	if step == Step.EDITOR:
		step = Step.DONE


## Abschluss: liefert das Profil-Dict und sperrt die Maschine.
func finish() -> Dictionary:
	step = Step.FINISHED
	return result()


## Vertragsform: {player_name, gooby_nickname, editor:{...}}.
func result() -> Dictionary:
	return {
		"player_name": player_name,
		"gooby_nickname": gooby_nickname,
		"editor": editor.duplicate(),
	}

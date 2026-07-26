class_name Haptics
extends RefCounted
## RW-7 — Haptik-Helfer (Doc §3.5). Statisch, überall aufrufbar:
## `Haptics.tap(node)` für kurze Impulse, `Haptics.success(node)` für den
## weichen Doppelimpuls. Intensität kommt aus controls.haptics
## (aus/dezent/normal/stark).
##
## EHRLICH: Ohne signierte iOS-App und natives Core-Haptics-Plugin gibt es
## auf dem iPhone keine Haptik. Godots portables `Input.vibrate_handheld()`
## deckt Android ab und ist auf iOS erst im signierten Build wirksam;
## auf dem Desktop ist alles ein No-op. Das Mapping hier definiert bereits
## die späteren Plugin-Parameter (Dauer/Amplitude).

## Stufe → [Dauer ms, Amplitude 0..1] für einen Standard-Tipp.
const STUFEN := {
	"aus": [0, 0.0],
	"dezent": [8, 0.3],
	"normal": [14, 0.6],
	"stark": [24, 1.0],
}


## Kurzer Impuls (Button-Tipp, Regler-Raste).
static func tap(from_node: Node) -> void:
	_vibrate(from_node, 1.0)


## Kräftiger Einzelimpuls (Landung, Bestätigung wichtiger Aktionen).
static func heavy(from_node: Node) -> void:
	_vibrate(from_node, 1.8)


## Aktuelle Stufe aus den Settings ("normal" ohne Autoload).
static func level(from_node: Node) -> String:
	var settings := from_node.get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("value_of"):
		return String(settings.value_of("controls.haptics"))
	return "normal"


static func _vibrate(from_node: Node, factor: float) -> void:
	var stufe := level(from_node)
	var params: Array = STUFEN.get(stufe, STUFEN["normal"])
	var dauer_ms := int(int(params[0]) * factor)
	if dauer_ms <= 0:
		return
	Input.vibrate_handheld(dauer_ms, float(params[1]))

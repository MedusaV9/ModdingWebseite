class_name Haptics
extends RefCounted
## W14/UIKERN — zentrale Haptik für alle AC-Buttons (User-Wunsch:
## „haptisches Feedback auf Knöpfen“). Statisch, überall aufrufbar:
##
##   Haptics.tap()      leichter Tipp (10 ms) — feuert automatisch bei jedem
##                      SquishButton-Press, Screens verdrahten NICHTS selbst.
##   Haptics.success()  weicher Doppelimpuls (8 ms + 8 ms) für Belohnungen.
##   Haptics.warn()     langer Einzelimpuls (40 ms) für Fehler/Warnungen.
##
## GATE: neues Setting `game.haptik` (bool, Default AN — fehlender Key zählt
## als AN). Die Settings-Zeile baut Screen-Agent A; zusätzlich respektieren
## wir die bestehende RW-7-Stufe `controls.haptics` == "aus" (wer Haptik dort
## abgeschaltet hat, bleibt still). Ersetzt scripts/platform/haptics.gd —
## die Alt-Aufrufe `Haptics.tap(node)` / `Haptics.heavy(node)` laufen weiter.
##
## EHRLICH (RW-7 Doc §3.5): `Input.vibrate_handheld()` wirkt auf Android
## sofort, auf iOS erst im signierten Build; Desktop/Headless = No-op.

const SETTING_KEY := "game.haptik"
const ALT_LEVEL_KEY := "controls.haptics"
const TAP_MS := 10
const SUCCESS_MS := 8
const SUCCESS_PAUSE_S := 0.08
const WARN_MS := 40

## Tests injizieren hier ein Settings-Double (statt /root/AppSettings).
static var settings_override: Object = null


## Leichter Tipp — für JEDEN Knopfdruck (SquishButton ruft das zentral).
static func tap(from_node: Node = null) -> void:
	_fire("tap", from_node)


## Doppelimpuls — Erfolg/Belohnung (Quest fertig, Kauf, Sticker).
static func success(from_node: Node = null) -> void:
	_fire("success", from_node)


## Langer Impuls — Warnung/Fehler (destruktive Aktion, ungültiger Tap).
static func warn(from_node: Node = null) -> void:
	_fire("warn", from_node)


## Alt-API (RW-7, settings_screen/dev_unlock): kräftiger Einzelimpuls.
static func heavy(from_node: Node = null) -> void:
	_fire("warn", from_node)


## PURE: Impulsplan in Millisekunden je Art (headless testbar).
static func plan(art: String) -> Array[int]:
	match art:
		"success":
			return [SUCCESS_MS, SUCCESS_MS]
		"warn":
			return [WARN_MS]
		_:
			return [TAP_MS]


## Gate — PURE bei injizierten Settings: `game.haptik` (Default AN) muss an
## sein UND die Alt-Stufe `controls.haptics` darf nicht "aus" sein.
static func is_enabled(settings: Object = null) -> bool:
	var source := settings if settings != null else _settings(null)
	if source == null:
		return true
	if source.has_method("get_setting") and not bool(source.get_setting(SETTING_KEY, true)):
		return false
	if source.has_method("value_of") and String(source.value_of(ALT_LEVEL_KEY)) == "aus":
		return false
	return true


static func _fire(art: String, from_node: Node) -> void:
	if not is_enabled(_settings(from_node)):
		return
	_vibrate_plan(plan(art), from_node)


## Plan abspielen — bei Mehrfach-Impulsen mit kurzer Pause dazwischen.
static func _vibrate_plan(pulses: Array[int], from_node: Node) -> void:
	for i in pulses.size():
		if i > 0:
			var tree := _tree(from_node)
			if tree == null:
				return
			await tree.create_timer(SUCCESS_PAUSE_S).timeout
		Input.vibrate_handheld(pulses[i])


static func _settings(from_node: Node) -> Object:
	if settings_override != null:
		return settings_override
	if from_node != null and from_node.is_inside_tree():
		return from_node.get_node_or_null("/root/AppSettings")
	var tree := _tree(from_node)
	if tree == null:
		return null
	return tree.root.get_node_or_null("AppSettings")


static func _tree(from_node: Node) -> SceneTree:
	if from_node != null and from_node.is_inside_tree():
		return from_node.get_tree()
	return Engine.get_main_loop() as SceneTree

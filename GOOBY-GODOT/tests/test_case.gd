class_name TestCase
extends RefCounted
## Basisklasse aller GOOBY-Tests (W1a). Konventionen (nach W1 FROZEN):
## - Testdateien: tests/unit/test_*.gd (auch tests/test_*.gd wird entdeckt),
##   jede Datei erbt von TestCase.
## - Testmethoden: func test_*() — dürfen async sein (await erlaubt, der
##   Runner awaitet jede Methode).
## - Asserts sammeln Fehler in einer Liste statt zu crashen; der Runner
##   liest sie über take_failures() aus.
## - `tree` (SceneTree) wird vom Runner injiziert: Nodes via
##   tree.root.add_child() einhängen und am Testende selbst aufräumen.

var tree: SceneTree

var _failures: PackedStringArray = PackedStringArray()


func begin_test() -> void:
	_failures = PackedStringArray()


func take_failures() -> PackedStringArray:
	var out := _failures
	_failures = PackedStringArray()
	return out


func fail_test(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		_failures.append("assert_true fehlgeschlagen. %s" % message)


func assert_false(condition: bool, message := "") -> void:
	if condition:
		_failures.append("assert_false fehlgeschlagen. %s" % message)


func assert_eq(got: Variant, want: Variant, message := "") -> void:
	if got != want:
		_failures.append("assert_eq: got=%s want=%s. %s" % [got, want, message])


func assert_ne(got: Variant, unwanted: Variant, message := "") -> void:
	if got == unwanted:
		_failures.append("assert_ne: beide=%s. %s" % [got, message])


func assert_almost(got: float, want: float, eps := 1e-6, message := "") -> void:
	if absf(got - want) > eps:
		_failures.append("assert_almost: got=%f want=%f eps=%f. %s" % [got, want, eps, message])


## Wartet n Prozess-Frames (für Node-/Szenen-Tests).
func wait_frames(count: int) -> void:
	for _i in count:
		await tree.process_frame


## Pollt predicate bis true oder Timeout; gibt Erfolg zurück.
func wait_until(predicate: Callable, timeout_ms := 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await tree.process_frame
	return false

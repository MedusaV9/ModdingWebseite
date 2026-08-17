extends TestCase
## Wohnmodus-Kamera: Pan-Deadzone muss ab Finger-Down gemessen werden,
## nicht pro Frame-Delta — sonst startet freies Schwenken auf Touch nie.


func test_pan_deadzone_frame_delta_never_activates() -> void:
	# Langsamer Swipe: 3 px pro Event, Deadzone 8 — Frame-Delta-Bug.
	var origin := Vector2.ZERO
	var frames: Array[Vector2] = [
		Vector2(3, 0), Vector2(6, 0), Vector2(9, 0), Vector2(12, 0), Vector2(15, 0)
	]
	var last := origin
	var activated_bug := false
	for p in frames:
		if last.distance_to(p) >= HomeCameraRig.PAN_DEADZONE_PX:
			activated_bug = true
		last = p
	assert_false(activated_bug, "Frame-Delta-Messung aktiviert bei langsamem Swipe nie (Bug-Repro)")


func test_pan_deadzone_from_origin_activates() -> void:
	var origin := Vector2.ZERO
	var current := Vector2(15, 0)
	assert_true(
		HomeCameraRig.pan_gesture_ready(origin, current),
		"Origin-Messung aktiviert sobald Gesamtstrecke >= Deadzone"
	)
	assert_false(
		HomeCameraRig.pan_gesture_ready(origin, Vector2(3, 0)), "Unter Deadzone noch kein Pan"
	)


func test_pan_gesture_ready_zero_deadzone_always() -> void:
	# Deadzone 0 (wie BuildMode): jeder Drag startet sofort.
	assert_true(HomeCameraRig.pan_gesture_ready(Vector2.ZERO, Vector2(0.5, 0), 0.0))

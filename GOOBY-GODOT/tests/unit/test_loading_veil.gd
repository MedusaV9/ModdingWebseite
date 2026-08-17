extends TestCase
## Tests der echten LoadingVeil-Szene (W1a) — cover/reveal-Contract awaitbar,
## Reduced-Motion-Pfad instantan, animierter Pfad via Tween (headless ok).

const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")


func test_cover_and_reveal_reduced_motion() -> void:
	var veil: CanvasLayer = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	await wait_frames(1)
	var events: Array = []
	veil.covered.connect(func() -> void: events.append("covered"))
	veil.revealed.connect(func() -> void: events.append("revealed"))

	assert_false(veil.visible, "Veil startet unsichtbar.")
	await veil.cover(true)
	assert_true(veil.visible, "Veil muss nach cover sichtbar sein.")
	assert_almost(veil.get_node("Root").modulate.a, 1.0, 1e-4, "Voll deckend.")
	await veil.reveal(true)
	assert_false(veil.visible, "Veil muss nach reveal unsichtbar sein.")
	assert_eq(events, ["covered", "revealed"] as Array)
	veil.queue_free()
	await wait_frames(1)


func test_cover_and_reveal_animated() -> void:
	var veil: CanvasLayer = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	await wait_frames(1)

	await veil.cover(false)
	assert_almost(veil.get_node("Root").modulate.a, 1.0, 1e-4, "Tween muss bei 1.0 enden.")
	await veil.reveal(false)
	assert_almost(veil.get_node("Root").modulate.a, 0.0, 1e-4, "Tween muss bei 0.0 enden.")
	assert_false(veil.visible)
	veil.queue_free()
	await wait_frames(1)


func test_progress_is_clamped() -> void:
	var veil: CanvasLayer = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	await wait_frames(1)
	veil.set_progress(1.5)
	assert_almost(veil.get_progress(), 1.0)
	veil.set_progress(-0.5)
	assert_almost(veil.get_progress(), 0.0)
	veil.set_progress(0.42)
	assert_almost(veil.get_progress(), 0.42)
	veil.queue_free()
	await wait_frames(1)

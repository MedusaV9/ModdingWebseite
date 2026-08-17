class_name HomeBuildAnim
extends RefCounted
## Gemeinsame Bau-Animation (Doc D §3.1/§4.1): Hammer-Gag, Qualmwolke,
## Konfetti und der Squash-&-Stretch-Plopp, mit dem ein neues Bauwerk
## erscheint. Wird vom Möbel-Bau, den Garten-Bauten (Werkstatt, Gewächshaus,
## Shed-Upgrade) und der Werkbank benutzt — EINE Stelle, ein Look.
##
## Bauen kostet KEINE Energie (User-Regel) — hier wird nichts abgezogen.
## Reduced Motion (AppSettings) kürzt alles auf einen kurzen Puff.

## Sound-Ids aus der zentralen SfxMap (W4-P1).
const SFX_HAMMER := "build_hammer"
const SFX_FERTIG := "ui_confirm"
const DAUER := 1.4
const DAUER_REDUZIERT := 0.35


## Qualmwolke an `world_pos` (Kind von `parent`). Der Aufrufer räumt sie mit
## `queue_free()` weg — oder benutzt gleich `plopp()`.
static func qualm(parent: Node3D, world_pos: Vector3, staerke := 1.0) -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	smoke.name = "BauQualm"
	smoke.amount = int(18 * staerke)
	smoke.lifetime = 0.9
	smoke.one_shot = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 0.5 * staerke
	mat.initial_velocity_max = 1.2 * staerke
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.6 * staerke
	mat.scale_max = 1.5 * staerke
	smoke.process_material = mat
	var kugel := SphereMesh.new()
	kugel.radius = 0.06
	kugel.height = 0.12
	smoke.draw_pass_1 = kugel
	smoke.position = world_pos + Vector3(0, 0.4 * staerke, 0)
	smoke.emitting = true
	parent.add_child(smoke)
	return smoke


## Das Kernstück: `neubau` erscheint hinter einer Qualmwolke und ploppt mit
## Squash & Stretch heraus. Awaitbar.
static func plopp(parent: Node3D, neubau: Node3D, world_pos: Vector3, staerke := 1.0) -> void:
	var reduziert := _reduced_motion(parent)
	var smoke := qualm(parent, world_pos, staerke) if not reduziert else null
	AudioDirector.try_play(parent, SFX_HAMMER)
	neubau.scale = Vector3(0.01, 0.01, 0.01)
	neubau.visible = true
	if reduziert:
		neubau.scale = Vector3.ONE
		await parent.get_tree().create_timer(DAUER_REDUZIERT).timeout
	else:
		await parent.get_tree().create_timer(DAUER * 0.5).timeout
		var tween := parent.create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(neubau, "scale", Vector3.ONE, 0.45)
		await tween.finished
		AudioDirector.try_play(parent, SFX_FERTIG)
		await parent.get_tree().create_timer(0.5).timeout
	if smoke != null:
		smoke.queue_free()


## Kurzer Hammer-Puff ohne neues Modell (Werkbank-Craft, Shed-Upgrade).
static func puff(parent: Node3D, world_pos: Vector3) -> void:
	var reduziert := _reduced_motion(parent)
	var smoke := qualm(parent, world_pos, 0.8) if not reduziert else null
	AudioDirector.try_play(parent, SFX_HAMMER)
	await parent.get_tree().create_timer(DAUER_REDUZIERT if reduziert else 0.9).timeout
	if smoke != null:
		smoke.queue_free()
	AudioDirector.try_play(parent, SFX_FERTIG)


static func _reduced_motion(node: Node) -> bool:
	var settings := node.get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()

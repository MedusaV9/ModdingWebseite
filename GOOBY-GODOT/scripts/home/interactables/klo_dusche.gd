class_name KloDusche
extends Node3D
## Klo/Dusche-Interactable (W3d CONTENT, Doc F §3.2): Gooby geht WIRKLICH
## aufs Klo (Bedürfnis-Timer im `bad`-Slice → Klo-Gang mit Schatten) und
## duscht hinter dem Vorhang: Gooby-Mesh unsichtbar, stattdessen eine
## animierte Schatten-Silhouette (flaches Quad — billig, lesbar, witzig).
## Duschvorhang-Peek: sitzt er > 45 s, lugen Kopf+Ohren über die
## Vorhangkante und die Textblasen rotieren („…hallo?“ / „Das Wasser wird
## kalt…“ / „Ich zähle bis drei…“).

const PEEK_LINES: Array[String] = ["bad.dusche.peek1", "bad.dusche.peek2", "bad.dusche.peek3"]
const KLO_CHECK_S := 5.0

var _host: InteractablesHost
var _furniture: Node3D
var _is_shower := false
var _routine_active := false
var _curtain: Node3D
var _silhouette: MeshInstance3D
var _peek_head: MeshInstance3D
var _peek_index := 0
var _peeked := false
var _klo_accum := 0.0
var _sil_tween: Tween


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_furniture = furniture
	var item_id := str((furniture.get("item_def") as Dictionary).get("id", ""))
	_is_shower = item_id == "shower" or item_id == "bathtub"
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))
	var gs := _host.game_state()
	if gs != null:
		BadState.ensure_klo_timer(gs, _now_ms())


func _process(delta: float) -> void:
	if _is_shower or _routine_active:
		return
	_klo_accum += delta
	if _klo_accum < KLO_CHECK_S:
		return
	_klo_accum = 0.0
	var gs := _host.game_state()
	if gs != null and BadState.klo_due(int(gs.get_value("bad.kloLastMs", 0)), _now_ms()):
		_run_klo_routine()


func _on_tapped() -> void:
	if _room_busy():
		return
	if _routine_active:
		# Zweiter Tap während der Dusche = abspülen.
		finish_shower()
		return
	if _is_shower:
		_run_shower_routine()
	else:
		_run_klo_routine()


## Dusch-Ablauf: hinter den Vorhang, Silhouette an, Peek-Gag nach 45 s;
## zweiter Tap (= Abspülen) beendet und gibt Hygiene.
func _run_shower_routine() -> void:
	_routine_active = true
	_peeked = false
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		await gooby.walk_to(global_position + Vector3(0.4, 0.0, 0.6), 5.0)
		gooby.visible = false
	_show_curtain(true)
	var gs := _host.game_state()
	var started := _now_ms()
	if gs != null:
		BadState.set_shower_started(gs, started)
	_say("bad.dusche.start")
	while _routine_active and is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		if not _routine_active:
			break
		if not _peeked and BadState.shower_peek_due(started, _now_ms()):
			_peek_gag()


## Zweiter Tap während der Dusche = abspülen/beenden.
func finish_shower() -> void:
	if not _routine_active or not _is_shower:
		return
	_routine_active = false
	_show_curtain(false)
	var gooby := _gooby()
	if gooby != null:
		gooby.visible = true
		gooby.play_clip("hop")
		gooby.set_wander_enabled(true)
	var gs := _host.game_state()
	if gs != null:
		BadState.set_shower_started(gs, 0)
		gs.update(
			func(state: Dictionary) -> void:
				var stats: Variant = state.get("gooby", {}).get("stats")
				if stats is Dictionary:
					stats["hygiene"] = minf(100.0, float(stats.get("hygiene", 0.0)) + 20.0)
		)
		# EF-1/EVAL-1 D6: Pflege zählt (washes → Sticker) und meldet SICHTBAR
		# und HÖRBAR zurück — vorher endete die Dusche wortlos.
		BadState.mark_washed(gs)
	AudioDirector.try_play(self, "ui_sticker")
	_show_care_reward(gooby, 20)
	_say("bad.dusche.fertig")


## Klo-Gang mit Schatten (Bedürfnis erledigt → Timer neu).
func _run_klo_routine() -> void:
	_routine_active = true
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		await gooby.walk_to(global_position + Vector3(0.4, 0.0, 0.6), 5.0)
		gooby.visible = false
	_show_curtain(true)
	_say("bad.klo.gang")
	if is_inside_tree():
		await get_tree().create_timer(3.0).timeout
	_show_curtain(false)
	if gooby != null:
		gooby.visible = true
		gooby.play_clip("hop")
		gooby.set_wander_enabled(true)
	var gs := _host.game_state()
	if gs != null:
		BadState.mark_klo_done(gs, _now_ms())
	_say("bad.klo.fertig")
	_routine_active = false


func is_routine_active() -> bool:
	return _routine_active


## Pflege-Belohnung (EF-1, EVAL-1 D6): „+{n}“-Float + Glitzer über Gooby.
func _show_care_reward(gooby: Node, betrag: int) -> void:
	var room := _host.room()
	if room == null:
		return
	var pos: Vector3 = global_position + Vector3(0.0, 1.0, 0.4)
	if gooby is Node3D:
		pos = (gooby as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
	RewardFx.pflege_reward(room, pos, betrag)


func _peek_gag() -> void:
	_peeked = true
	if _peek_head != null:
		_peek_head.visible = true
	_say(PEEK_LINES[_peek_index % PEEK_LINES.size()])
	_peek_index += 1
	# Nach dem Spruch wieder abtauchen — beim nächsten 45-s-Fenster erneut.
	if is_inside_tree():
		await get_tree().create_timer(2.5).timeout
	if _peek_head != null:
		_peek_head.visible = false
	_peeked = false


func _show_curtain(active: bool) -> void:
	if _curtain == null:
		_build_curtain()
	_curtain.visible = active
	_silhouette.visible = active
	if not active and _peek_head != null:
		_peek_head.visible = false
	if active:
		_animate_silhouette()
	else:
		_stop_silhouette_tween()


## Vorhang + Silhouetten-Quad (Doc F: 2D-Silhouette statt Shader-Magie).
## WELT2: welliger Blender-Vorhang mit Stange + Clips statt Box-Plane;
## bei Duschen hängt zusätzlich ein Duschkopf über der Vorhangkante.
## Primitive-Fallback, falls das Asset fehlt.
func _build_curtain() -> void:
	var glb := HomeProps.prop_glb("duschvorhang")
	if glb != null:
		_curtain = Node3D.new()
		_curtain.name = "Vorhang"
		_curtain.position = Vector3(0.0, 0.0, 0.55)
		_curtain.add_child(glb)
		if _is_shower:
			var kopf := HomeProps.prop_glb("duschkopf")
			if kopf != null:
				kopf.position = Vector3(0.0, 0.0, -0.35)
				_curtain.add_child(kopf)
		add_child(_curtain)
	else:
		var platte := MeshInstance3D.new()
		var curtain_mesh := BoxMesh.new()
		curtain_mesh.size = Vector3(1.1, 1.5, 0.03)
		platte.mesh = curtain_mesh
		var curtain_mat := StandardMaterial3D.new()
		curtain_mat.albedo_color = Color(0.81, 0.91, 0.95, 0.9)
		curtain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		platte.material_override = curtain_mat
		platte.position = Vector3(0.0, 0.85, 0.55)
		_curtain = platte
		add_child(_curtain)
	_silhouette = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.62, 0.8)
	_silhouette.mesh = quad
	_silhouette.material_override = _silhouette_material()
	_silhouette.position = Vector3(0.0, 0.7, 0.53)
	add_child(_silhouette)
	_peek_head = MeshInstance3D.new()
	var head_quad := QuadMesh.new()
	head_quad.size = Vector2(0.4, 0.42)
	_peek_head.mesh = head_quad
	_peek_head.material_override = _silhouette_material()
	_peek_head.position = Vector3(0.12, 1.72, 0.55)
	_peek_head.visible = false
	add_child(_peek_head)


func _silhouette_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.16, 0.15, 0.55)
	var icon := "res://assets/ui/icons/rabbit.svg"
	if ResourceLoader.exists(icon):
		mat.albedo_texture = load(icon)
	return mat


## „3 Sprite-Frames“ light: Silhouette wackelt (sitzen/schrubbeln/Ohren).
## Reduced Motion (W4-P3 POLISH-16): Silhouette bleibt still; der Loop-Tween
## wird beim Vorhang-Zuziehen sauber beendet (kein Endlos-Tween-Leak).
func _animate_silhouette() -> void:
	if _silhouette == null or not is_inside_tree():
		return
	_stop_silhouette_tween()
	if ThemeService.is_reduced_motion(self):
		return
	_sil_tween = create_tween().set_loops()
	_sil_tween.tween_property(_silhouette, "rotation:z", 0.12, 0.5)
	_sil_tween.tween_property(_silhouette, "rotation:z", -0.12, 0.5)
	_sil_tween.tween_property(_silhouette, "scale:y", 0.92, 0.4)
	_sil_tween.tween_property(_silhouette, "scale:y", 1.0, 0.4)


func _stop_silhouette_tween() -> void:
	if _sil_tween != null and _sil_tween.is_running():
		_sil_tween.kill()
	_sil_tween = null


func _gooby() -> Node:
	var room := _host.room()
	if room != null and room.has_method("gooby"):
		return room.gooby()
	return null


func _say(key: String) -> void:
	var room := _host.room()
	if room != null and room.has_method("say"):
		room.say(I18nService.t(key))


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()


func _now_ms() -> int:
	var gs := _host.game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)

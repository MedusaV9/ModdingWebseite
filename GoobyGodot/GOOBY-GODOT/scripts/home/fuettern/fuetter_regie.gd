class_name FuetterRegie
extends Node3D
## W14/FRIDGE — Inszenierung der Fütter-Sequenz im Raum. Konsumiert die PURE
## FuetterSequenz (echte Uhr) und übersetzt jedes Ereignis in Sicht/Ton:
## Speise-Modell schwebt in einem Bogen vom Kühlschrank zu Goobys Mund,
## Gooby schaut hin (look_at_target) und öffnet pro Biss den BESTEHENDEN
## mouth_open-Morph (rig.babble_pulse — öffentliche Rig-API), das Modell
## schrumpft in Bissen (Krümel-Partikel + nom_nom-SFX aus der SfxMap),
## Schluck, dann die Emotion: Lieblingsessen → verliebtheit (GoobyFeelings),
## Junk → kurzes Zucker-Zittern, sonst happy + Hüpfer. `ablauf()` kehrt GENAU
## beim `buchen`-Ereignis zurück — der Kühlschrank bucht danach.
## Reduced Motion: Kurzfassung der Sequenz (1 Biss), keine Tweens/Partikel,
## Töne bleiben.

const MUND_HOEHE_M := 0.5
const MUND_ABSTAND_M := 0.26
const BOGEN_HUB_M := 0.35
const LETZTER_BISSEN_SKALIERUNG := 0.18
const KRUEMEL_ANZAHL := 7
const KRUEMEL_FARBE := Color("#C99666")
## Pitch-Treppe der Mampf-Bisse (Muster EF-1-Nom-Töne).
const NOM_PITCH_BASIS := 0.85
const NOM_PITCH_SCHRITT := 0.1

var _sequenz := FuetterSequenz.new()
var _modell: Node3D
var _reduziert := false


func sequenz() -> FuetterSequenz:
	return _sequenz


## Sequenz abspielen (await-bar). true = durchgelaufen bis `buchen`,
## false = Doppel-Start/kein Baum. Gooby/Rig dürfen fehlen (headless).
func ablauf(gooby: Node, food_id: String, start_pos: Vector3, reduziert: bool) -> bool:
	if not is_inside_tree():
		return false
	_reduziert = reduziert
	if not _sequenz.start(food_id, Time.get_ticks_msec(), reduziert):
		return false
	var rig := _rig_von(gooby)
	while _sequenz.ist_aktiv():
		for ev: Dictionary in _sequenz.tick(Time.get_ticks_msec()):
			_verarbeite(ev, rig, food_id, start_pos)
		await get_tree().process_frame
	_aufraeumen(rig)
	return true


func _verarbeite(ev: Dictionary, rig: GoobyRig, food_id: String, start_pos: Vector3) -> void:
	match str(ev["typ"]):
		"schwebt":
			_starte_schweben(ev, rig, food_id, start_pos)
		"biss":
			_biss(ev, rig)
		"schluck":
			_schluck(rig)
		"emotion":
			_emotion(str(ev["art"]), rig)
		"buchen":
			pass  # Buchung macht der Aufrufer — genau HIER endet ablauf().


# ── Ereignisse ────────────────────────────────────────────────────────────────


func _starte_schweben(ev: Dictionary, rig: GoobyRig, food_id: String, start_pos: Vector3) -> void:
	_modell = FuetterModelle.instanz(food_id)
	add_child(_modell)
	_modell.global_position = start_pos
	var ziel := _mund_position(rig, start_pos)
	if rig != null:
		rig.look_at_target = _modell
		rig.set_emotion("ecstatic")
	if _reduziert:
		_modell.global_position = ziel
		return
	var dauer := float(ev.get("dauer_ms", FuetterSequenz.SCHWEBEN_MS)) / 1000.0
	var scheitel := (start_pos + ziel) * 0.5 + Vector3(0.0, BOGEN_HUB_M, 0.0)
	var tween := _modell.create_tween()
	(
		tween
		. tween_property(_modell, "global_position", scheitel, dauer * 0.45)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(_modell, "global_position", ziel, dauer * 0.55)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN)
	)
	var dreher := _modell.create_tween()
	dreher.tween_property(_modell, "rotation:y", TAU, dauer)


func _biss(ev: Dictionary, rig: GoobyRig) -> void:
	var index := int(ev.get("index", 1))
	var von := maxi(int(ev.get("von", 1)), 1)
	AudioDirector.try_play(self, "nom_nom", NOM_PITCH_BASIS + NOM_PITCH_SCHRITT * float(index))
	if rig != null:
		rig.babble_pulse()
	if _modell != null and is_instance_valid(_modell):
		var rest := maxf(
			1.0 - float(index) / float(von) * (1.0 - LETZTER_BISSEN_SKALIERUNG),
			LETZTER_BISSEN_SKALIERUNG
		)
		if _reduziert:
			_modell.scale = Vector3.ONE * rest
		else:
			var tween := _modell.create_tween()
			(
				tween
				. tween_property(_modell, "scale", Vector3.ONE * rest, 0.12)
				. set_trans(Tween.TRANS_BACK)
				. set_ease(Tween.EASE_OUT)
			)
			_kruemel(_modell.global_position)
	if rig != null and not _reduziert:
		var wippe := rig.create_tween()
		wippe.tween_property(rig, "scale:y", 0.9, 0.12)
		wippe.tween_property(rig, "scale:y", 1.0, 0.16)


func _schluck(rig: GoobyRig) -> void:
	AudioDirector.try_play(self, "pet_squish")
	if rig != null:
		rig.babble_pulse()
	if _modell == null or not is_instance_valid(_modell):
		return
	if _reduziert:
		_modell.queue_free()
		_modell = null
		return
	var tween := _modell.create_tween()
	(
		tween
		. tween_property(_modell, "scale", Vector3.ONE * 0.01, 0.18)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN)
	)
	tween.tween_callback(_modell.queue_free)
	_modell = null


func _emotion(art: String, rig: GoobyRig) -> void:
	if rig == null:
		return
	rig.look_at_target = null
	match art:
		FuetterSequenz.EMOTION_VERLIEBT:
			AudioDirector.try_play(self, "mg_perfect", 1.1)
			GoobyFeelings.attach_to(rig).zeige("verliebtheit")
		FuetterSequenz.EMOTION_ZUCKER:
			_zucker_zittern(rig)
		_:
			rig.set_emotion("happy")
			rig.play_clip("hop")


## Zucker-Gag: kurzes Zittern nach dem Junk-Snack (Reduced Motion: nur Ton).
func _zucker_zittern(rig: GoobyRig) -> void:
	AudioDirector.try_play(self, "mg_junk", 1.2)
	rig.set_emotion("dizzy")
	if _reduziert:
		rig.set_emotion("happy")
		return
	var tween := rig.create_tween()
	for i in 4:
		var winkel := 0.06 if i % 2 == 0 else -0.06
		tween.tween_property(rig, "rotation:z", winkel, 0.05)
	tween.tween_property(rig, "rotation:z", 0.0, 0.06)
	tween.tween_callback(rig.set_emotion.bind("happy"))


# ── Helfer ────────────────────────────────────────────────────────────────────


func _aufraeumen(rig: GoobyRig) -> void:
	if rig != null:
		rig.look_at_target = null
	if _modell != null and is_instance_valid(_modell):
		_modell.queue_free()
	_modell = null


static func _rig_von(gooby: Node) -> GoobyRig:
	if gooby == null:
		return null
	var raw: Variant = gooby.get("rig")
	return raw if raw is GoobyRig else null


## Mundposition: knapp vor und über Goobys Ursprung, dem Modell zugewandt.
func _mund_position(rig: GoobyRig, start_pos: Vector3) -> Vector3:
	if rig == null:
		return start_pos + Vector3(0.0, -0.15, 0.4)
	var basis := rig.global_position
	var richtung := start_pos - basis
	richtung.y = 0.0
	richtung = richtung.normalized() if richtung.length() > 0.01 else Vector3(0.0, 0.0, 1.0)
	return basis + richtung * MUND_ABSTAND_M + Vector3(0.0, MUND_HOEHE_M, 0.0)


func _kruemel(at: Vector3) -> void:
	var teilchen := CPUParticles3D.new()
	teilchen.one_shot = true
	teilchen.amount = KRUEMEL_ANZAHL
	teilchen.lifetime = 0.5
	teilchen.explosiveness = 1.0
	var wuerfel := BoxMesh.new()
	wuerfel.size = Vector3(0.02, 0.02, 0.02)
	var material := StandardMaterial3D.new()
	material.albedo_color = KRUEMEL_FARBE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wuerfel.material = material
	teilchen.mesh = wuerfel
	teilchen.direction = Vector3(0.0, 1.0, 0.0)
	teilchen.spread = 65.0
	teilchen.initial_velocity_min = 0.5
	teilchen.initial_velocity_max = 1.1
	teilchen.gravity = Vector3(0.0, -4.0, 0.0)
	add_child(teilchen)
	teilchen.global_position = at
	teilchen.emitting = true
	get_tree().create_timer(1.2).timeout.connect(teilchen.queue_free)

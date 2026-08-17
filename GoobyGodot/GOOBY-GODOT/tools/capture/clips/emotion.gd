extends "res://tools/capture/clip_driver.gd"
## Clip: Emotions-Nahaufnahme (FEEL-AC) — Gooby in Großaufnahme spielt zwei
## der 12 inszenierten Emotionen: SCHRECK (Ausrufezeichen-Symbol, Zucken)
## und VERLIEBTHEIT (Herz-Symbol, Schweben). Beide sind "stark", d. h. die
## echte MomentRegie fährt Kamera-Zoom + Zeitlupe + Post-FX-Puls — genau
## die Inszenierung, die auch im Spiel läuft. Kamera ist bewusst STATISCH
## (kein move_camera): der FOV-Zoom der MomentRegie braucht die Hoheit.

const SCENE := "res://scripts/character/gooby_showcase.tscn"

var showcase: Node3D
var feelings: GoobyFeelings


func _setup() -> void:
	duration = 9.4
	var packed: PackedScene = load(SCENE)
	showcase = packed.instantiate()
	# Ruhiges Grund-Programm (idle) — die Emotionen kommen vom Feelings-Layer.
	var prog: Array[Dictionary] = []
	for _i in 10:
		prog.append({"clip": "idle", "emotion": "neutral"})
	showcase._program = prog
	add_child(showcase)
	# KEINE Schatten-Regie: shadow_enabled auf der Showcase-Sonne wäscht
	# unter gl_compatibility das Bild aus (Fell-Rimlight + Glow kippen ins
	# Weiße — per Probelauf verifiziert). Look bleibt wie im Spiel.
	# Nahaufnahme mit Luft nach oben fürs Emote-Symbol über den Ohren.
	cine_camera(Vector3(0.42, 0.92, 1.9), Vector3(0.0, 0.72, 0.0), 46.0)
	schedule(0.8, _schreck)
	schedule(4.9, _verliebtheit)


func _schreck() -> void:
	feelings = GoobyFeelings.attach_to(showcase.rig)
	feelings.zeige("schreck")


func _verliebtheit() -> void:
	if feelings == null:
		return
	# Regie-Cooldown (45 s) nur für die Aufnahme zurücksetzen, damit auch
	# die zweite starke Emotion ihren Zoom-Moment bekommt.
	if feelings.regie() != null:
		feelings.regie().reset_cooldown()
	feelings.zeige("verliebtheit")

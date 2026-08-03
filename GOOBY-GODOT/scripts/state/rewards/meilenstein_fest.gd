class_name MeilensteinFest
extends Node
## Meilenstein-Fest im Zuhause (W18/R3, G8-IDEE Progression Nr. 2): das
## kleine Fest beim Erreichen von Level 5/10/…/40 — eine Geburtstagstorte
## erscheint neben Gooby (bei Level 40: die GOLDENE MÖHRE mit Funken),
## 3D-Konfetti regnet (GoobyReactions-Muster), Gooby tanzt kurz und jubelt
## per Bubble („…der Stempel ist im Reisepass!“). Der RewardHub reiht das
## Fest über seine Feier-Queue ein (NIE über Overlays stapeln — Bühne-frei-
## Warten dort) und ruft zeige_in(); OHNE Raum (Arcade offen, nackte Tests)
## bleibt es beim Hub-Toast + 2D-Konfetti — dieser Node degradiert weich.
##
## Muster: LevelUpFeier (Fabrik + Selbstaufräumen), GoobyReactions._confetti
## (CPU-Partikel, Methoden-Callable statt Lambda — B2), Kissenturm
## (kurzlebiges Prop im Raum), HomeProps.modell_glb (AABB-normiert).

## Torte fürs 5er-Fest; Goldene Möhre als Reiseziel-Zeremonie (L40).
const TORTE_PFAD := "res://assets/furniture/kenney-food/cake-birthday.glb"
const MOEHRE_PFAD := "res://assets/furniture/gfree/carrot.glb"
const TORTE_HOEHE_M := 0.4
const MOEHRE_HOEHE_M := 0.55
## Prop steht schräg vor Gooby und bleibt wie der Kissenturm kurz stehen.
const PROP_VERSATZ := Vector3(0.65, 0.0, 0.35)
const PROP_DAUER_S := 10.0
## Node-Lebenszeit (Tanz + Konfetti ausklingen lassen, dann weg).
const FEST_DAUER_S := 3.2
const TANZ_S := 2.4
const KONFETTI_TEILE := 96

var level := 5
var gs: Object = null

var _gooby: Node3D = null


## Fabrik (Muster LevelUpFeier.zeige_in): Fest bauen, einhängen, abspielen.
static func zeige_in(parent: Node, fest_level: int, game_state: Object) -> MeilensteinFest:
	var fest := MeilensteinFest.new()
	fest.name = "MeilensteinFest%d" % fest_level
	fest.level = fest_level
	fest.gs = game_state
	parent.add_child(fest)
	return fest


## Aktueller Raum als Fest-Bühne (MorgenSequenz-Muster) — null heißt:
## kein Zuhause auf dem Schirm, das Fest bleibt beim Hub-Toast.
static func aktuelle_buehne(von: Node) -> Node:
	var router := von.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("get_current_scene"):
		return null
	var szene: Node = router.get_current_scene()
	return szene if szene is RoomBase else null


func _ready() -> void:
	AudioDirector.try_play(self, "ui_levelup")
	var raum := aktuelle_buehne(self)
	if raum != null:
		_feiere_im_raum(raum)
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	# Methoden-Callable statt Lambda (B2): stirbt der Node vorher, trennt
	# Godot die Verbindung selbst.
	tree.create_timer(FEST_DAUER_S).timeout.connect(_aufraeumen)


## ---------------------------------------------------------------- Raum-Fest


func _feiere_im_raum(raum: Node) -> void:
	_gooby = raum.gooby() if raum.has_method("gooby") else null
	_stelle_prop(raum)
	_konfetti(raum)
	_jubel(raum)


## Torte/Möhre neben Gooby abstellen (kurzlebig wie der Kissenturm).
## Die Goldene Möhre bekommt goldene Funken obendrauf (RewardFx).
func _stelle_prop(raum: Node) -> void:
	var max_fest := level >= LevelReiseLogic.Leveling.MAX_LEVEL
	var prop := HomeProps.modell_glb(
		MOEHRE_PFAD if max_fest else TORTE_PFAD, MOEHRE_HOEHE_M if max_fest else TORTE_HOEHE_M
	)
	if prop == null or not (raum is Node3D):
		return
	prop.name = "MeilensteinTorte"
	prop.position = _fusspunkt() + PROP_VERSATZ
	raum.add_child(prop)
	if max_fest:
		RewardFx.funken_burst(raum, prop.position + Vector3(0.0, MOEHRE_HOEHE_M, 0.0), 16)
	var tree := get_tree()
	if tree != null:
		tree.create_timer(PROP_DAUER_S).timeout.connect(prop.queue_free)


## Konfetti-Regen über Gooby (GoobyReactions._confetti-Muster; Reduced
## Motion lässt ihn weg — Torte + Jubel bleiben).
func _konfetti(raum: Node) -> void:
	if not (raum is Node3D) or RewardFx.reduced_motion(raum):
		return
	var particles := CPUParticles3D.new()
	particles.name = "MeilensteinKonfetti"
	particles.amount = KONFETTI_TEILE
	particles.lifetime = 2.2
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.direction = Vector3.UP
	particles.initial_velocity_min = 1.6
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0.0, -2.6, 0.0)
	particles.spread = 75.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	# Ohne vertex_color_use_as_albedo rendert der Gradient NICHT (grau).
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	particles.mesh = mesh
	particles.color_ramp = _konfetti_gradient()
	particles.position = _fusspunkt() + Vector3(0.0, 0.9, 0.0)
	raum.add_child(particles)
	particles.emitting = true
	var tree := get_tree()
	if tree != null:
		tree.create_timer(2.5).timeout.connect(particles.queue_free)


## Gooby-Jubel: kurzer Tanz (zeitbegrenzter Loop), Freuden-Gesicht und die
## deterministische Jubel-Zeile als Bubble (LevelReiseLogic.jubel_key).
func _jubel(raum: Node) -> void:
	if _gooby != null and _gooby.get("rig") is GoobyRig:
		_gooby.rig.set_emotion("ecstatic")
		_gooby.rig.play_clip_for(GoobyRig.CLIP_DANCE, TANZ_S)
	if raum.has_method("say"):
		raum.say(jubel_text(level, _spitzname()))


## Jubel-Text (pur, testbar): Zeile nach Level-Variante + Stempel-Hinweis.
static func jubel_text(fest_level: int, spitzname: String) -> String:
	return I18nService.t(
		LevelReiseLogic.jubel_key(fest_level), {"level": fest_level, "gooby": spitzname}
	)


## ---------------------------------------------------------------- Helfer


func _fusspunkt() -> Vector3:
	if _gooby != null and is_instance_valid(_gooby):
		return _gooby.global_position
	return Vector3.ZERO


func _spitzname() -> String:
	if gs == null or not gs.has_method("get_value"):
		return "Gooby"
	return str(gs.get_value("meta.goobyNickname", "Gooby"))


func _aufraeumen() -> void:
	queue_free()


static func _konfetti_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color("#FF7BA9"))
	gradient.set_color(1, Color("#59C9B9"))
	gradient.add_point(0.5, Color("#FFD166"))
	return gradient

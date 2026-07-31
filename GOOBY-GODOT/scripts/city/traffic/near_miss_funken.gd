class_name NearMissFunken
extends RefCounted
## Near-Miss-Funken (W13B, Doc E §1.5 Stadtleben-Polish): kleine
## GPUParticles3D-Funken am Berührungspunkt einer Beinahe-Kollision — die
## Hupe gibt es schon (city_scene._pruefe_near_miss), jetzt sprüht es dazu.
## Entscheidung PURE (testbar, Reduced-Motion respektiert), Spawn als
## One-Shot mit Selbst-Aufräumen über das `finished`-Signal.
##
## Einbau (Request W13, Tag GOBERANDO — city_scene gehört diese Welle
## niemandem): in `_pruefe_near_miss` nach der Hupe
##   if NearMissFunken.soll_funken(abstand, auto.speed, reduced_motion):
##       NearMissFunken.spawne(
##           self, NearMissFunken.funkenpunkt(auto.position, node.position)
##       )

## Funkenhöhe = Stoßstangen-Höhe der Kenney-Autos.
const FUNKEN_HOEHE_M := 0.35
const LEBENSDAUER_S := 0.45
const ANZAHL := 20

const FUNKEN_GELB := Color("#FFD166")
const GLUT_ORANGE := Color("#FFB13D")


## Funken NUR bei echtem Near-Miss (CityAmbiente.ist_beinahe) und NUR ohne
## Reduced-Motion — der Hupen-Toast läuft unabhängig davon weiter.
static func soll_funken(abstand_m: float, tempo: float, reduced_motion: bool) -> bool:
	return not reduced_motion and CityAmbiente.ist_beinahe(abstand_m, tempo)


## Berührungspunkt: Mitte zwischen beiden Wagen, auf Stoßstangen-Höhe.
static func funkenpunkt(spieler: Vector3, anderer: Vector3) -> Vector3:
	var mitte := (spieler + anderer) * 0.5
	return Vector3(mitte.x, FUNKEN_HOEHE_M, mitte.z)


## One-Shot-Funkengarbe am Punkt spawnen; räumt sich nach dem Ausbrennen
## selbst weg (finished → queue_free).
static func spawne(parent: Node, punkt: Vector3) -> GPUParticles3D:
	var funken := GPUParticles3D.new()
	funken.name = "NearMissFunken"
	funken.amount = ANZAHL
	funken.lifetime = LEBENSDAUER_S
	funken.one_shot = true
	funken.explosiveness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 70.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.5
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = FUNKEN_GELB
	funken.process_material = mat
	var korn := SphereMesh.new()
	korn.radius = 0.03
	korn.height = 0.06
	var glut := StandardMaterial3D.new()
	glut.albedo_color = FUNKEN_GELB
	glut.emission_enabled = true
	glut.emission = GLUT_ORANGE
	glut.emission_energy_multiplier = 2.0
	korn.material = glut
	funken.draw_pass_1 = korn
	funken.position = punkt
	funken.emitting = true
	parent.add_child(funken)
	funken.finished.connect(funken.queue_free)
	return funken

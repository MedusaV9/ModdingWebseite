class_name KoerperForm
extends RefCounted
## Wo ist Goobys Oberfläche? (CONTENT-A)
##
## Halsbänder, Schals, Rucksäcke und Panzer müssen AUF dem Körper liegen, nicht
## darin. Die Web-Zahlen taugen dafür nicht: der 3D-Gooby ist deutlich runder
## als seine Web-Vorlage, mit den Web-Radien verschwindet jedes Halsband im
## Bauch. Deshalb steht hier ein am GLB GEMESSENES Zwei-Kugel-Modell — ermittelt
## per Vertex-Sweep über die Rumpf-/Kopf-Bones (ArrayMesh-Vertices in Bändern von
## 0.01 Welt-Einheiten, je Band der maximale Abstand zur y-Achse):
##
##   Rumpf: Kugel um y = 0.225, r = 0.300   (Messung y 0.10…0.45: max 0.300)
##   Kopf:  Ellipsoid um y = 0.5595, z = 0.0141, rx 0.2219 / ry 0.1945
##
## Beide Zahlen sind Welt-Einheiten. Die Builder rechnen im Rezept-Raum, also
## gibt es alles auch relativ zu einem Anker: `radius(ANKER_Y, y_lokal)`.
##
## Hier stehen außerdem die ANKER-Weltpositionen selbst — `cosmetic_attach.gd`
## leitet daraus die Bone-Versätze ab, die Builder ihre Oberflächenabstände.
## Eine Quelle, keine zwei Zahlensätze, die auseinanderlaufen können.

## Rezept-Raum → Godot (tools/blender/gooby_build/gooby_params.py).
const RIG_SCALE := 0.6522
## Die Kopfgruppe ist zusätzlich um 1.08 skaliert (HEAD_GRP_SCALE).
const KOPF_SCALE := RIG_SCALE * 1.08

const RUMPF_Y := 0.225
const RUMPF_R := 0.300
const KOPF_Y := 0.5595
const KOPF_Z := 0.0141
const KOPF_RX := 0.2219
const KOPF_RY := 0.1945

## Anker in WELTKOORDINATEN der Ruhepose. Herkunft: die Web-Anker aus
## `GOOBY/src/character/gooby.js` (hat 0/0.44/0.02 in der Kopfgruppe,
## glasses 0/0.2/0.3), umgerechnet — und für Hals/Rücken NEU eingemessen,
## weil die Web-Positionen im runderen 3D-Körper stecken würden:
## Hals sitzt auf der Kopf-Körper-Naht (y 0.452, dort sind Kopf und Rumpf
## gleich breit), Rücken auf der dicksten Stelle des Rumpfes (y 0.2217).
const ANKER := {
	"hut": Vector3(0.0, 0.7567, 0.0141),
	"brille": Vector3(0.0, 0.5877, 0.2113),
	"hals": Vector3(0.0, 0.4520, 0.0),
	"ruecken": Vector3(0.0, 0.2217, 0.0),
}
## Bone je Kategorie + dessen Ruhe-Höhe (gemessen am Skeleton).
const BONE := {"hut": "head", "brille": "head", "hals": "chest", "ruecken": "spine"}
const BONE_Y := {"head": 0.456522, "chest": 0.378261, "spine": 0.260870}
## Anker-Skalierung: Kopfteile leben in der Kopfgruppe, Körperteile nicht.
const ANKER_SCALE := {
	"hut": KOPF_SCALE, "brille": KOPF_SCALE, "hals": RIG_SCALE, "ruecken": RIG_SCALE
}


## Versatz des Ankers zum Bone-Ursprung (Godot-Einheiten) — für BoneAttachment.
static func bone_versatz(kategorie: String) -> Vector3:
	var anker: Vector3 = ANKER.get(kategorie, Vector3.ZERO)
	return anker - Vector3(0.0, float(BONE_Y.get(str(BONE.get(kategorie, "")), 0.0)), 0.0)


## Silhouetten-Radius auf Welt-Höhe `welt_y` (Welt-Einheiten, 0 außerhalb).
static func welt_radius(welt_y: float) -> float:
	var rumpf := _kugel_radius(welt_y - RUMPF_Y, RUMPF_R, RUMPF_R)
	var kopf := _kugel_radius(welt_y - KOPF_Y, KOPF_RY, KOPF_RX)
	return maxf(rumpf, kopf)


## Dasselbe in REZEPT-Einheiten, relativ zu einem Anker: `y` ist die lokale
## Höhe im Builder, das Ergebnis der dort passende Oberflächenradius.
static func radius(anker_y: float, y: float, luft := 0.0) -> float:
	return welt_radius(anker_y + y * RIG_SCALE) / RIG_SCALE + luft


## Punkt AUF der Oberfläche: `y` lokale Höhe, `winkel` 0 = vorn (+z), wachsend
## Richtung +x. `luft` schiebt nach außen (Stoffdicke).
static func punkt(anker_y: float, y: float, winkel: float, luft := 0.0) -> Vector3:
	var r := radius(anker_y, y, luft)
	return Vector3(sin(winkel) * r, y, cos(winkel) * r)


## Vorderseite auf Höhe `y` (Schalenden, Anhänger, Krawatten).
static func vorne(anker_y: float, y: float, luft := 0.0) -> float:
	return radius(anker_y, y, luft)


## Rückseite auf Höhe `y` (Rucksäcke, Panzer, Flügel) — negatives z.
static func hinten(anker_y: float, y: float, luft := 0.0) -> float:
	return -radius(anker_y, y, luft)


static func _kugel_radius(dy: float, ry: float, rx: float) -> float:
	if absf(dy) >= ry:
		return 0.0
	return rx * sqrt(1.0 - (dy / ry) * (dy / ry))

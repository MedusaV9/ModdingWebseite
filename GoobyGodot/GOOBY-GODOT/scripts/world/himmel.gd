class_name GoobyHimmel
extends RefCounted
## Himmel-Fahrer aller GOOBY-Welten (FB-2): hält den prozeduralen Sky-
## Shader (assets/sky/gooby_himmel.gdshader) und schreibt den von
## HimmelStimmungen gemischten Uniform-Satz hinein. Ranch: der
## RanchWetterController ruft `wende_an(stunde, zustand)` im Wetter-Tick
## (Wetter-Signale und Himmel bleiben synchron); Stadt: einmal beim
## Szenen-Aufbau. `horizont_farbe()` versorgt die Fernsicht-Berge
## (WeltFernsicht) mit der passenden Dunst-Farbe.
##
## Entscheidung Shader statt Panorama-Texturen (Python/PIL): sieben
## Stimmungen als 4k-Panoramen wären ~50+ MB Texturspeicher ODER sichtbares
## Banding in den weichen Verläufen — und jedes Überblenden bräuchte ZWEI
## Panorama-Fetches pro Pixel. Der Shader mischt auf der CPU nur Uniforms
## (0 Texturen, stufenlos, Sonne folgt dem echten Licht) und rechnet pro
## Pixel nur Verläufe + 2 Oktaven Value-Noise — billiger auf Mobile.

const SHADER_PFAD := "res://assets/sky/gooby_himmel.gdshader"

var sky: Sky
var material: ShaderMaterial

var _zuletzt: Dictionary = {}


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PFAD)
	sky = Sky.new()
	sky.sky_material = material
	# Kleine Radiance reicht: Ambient kommt aus Farb-Ambient, nicht aus
	# der Sky-Reflexion — spart Cubemap-Kosten auf Mobile.
	sky.radiance_size = Sky.RADIANCE_SIZE_64


## Uniform-Satz für Stunde + Wetter-Zustand anwenden (stetig, deterministisch).
func wende_an(stunde: float, wetter: Dictionary) -> void:
	var p := HimmelStimmungen.parameter(stunde, wetter)
	_zuletzt = p
	material.set_shader_parameter("zenit_farbe", p["zenit"])
	material.set_shader_parameter("horizont_farbe", p["horizont"])
	material.set_shader_parameter("boden_farbe", p["boden"])
	material.set_shader_parameter("dunst_staerke", p["dunst"])
	material.set_shader_parameter("sonnen_farbe", p["sonne_farbe"])
	material.set_shader_parameter("sonnen_groesse", p["sonne_groesse"])
	material.set_shader_parameter("sonnen_glow", p["sonne_glow"])
	material.set_shader_parameter("wolken_farbe", p["wolken_farbe"])
	material.set_shader_parameter("wolken_menge", p["wolken_menge"])
	material.set_shader_parameter("sterne_staerke", p["sterne"])


## Horizont-Farbe des zuletzt angewendeten Zustands (für Fernsicht/Nebel).
func horizont_farbe() -> Color:
	if _zuletzt.is_empty():
		return Color(0.8, 0.89, 0.97)
	return _zuletzt["horizont"]


## Zenit-Farbe des zuletzt angewendeten Zustands.
func zenit_farbe() -> Color:
	if _zuletzt.is_empty():
		return Color(0.48, 0.67, 0.9)
	return _zuletzt["zenit"]

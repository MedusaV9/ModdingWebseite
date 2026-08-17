class_name RaumLicht
extends RefCounted
## Baut die WorldEnvironment-/Licht-Kette eines RoomBase-Raums (EVAL-2026-08
## Lens B, Befunde 5+6): Tonemap/Exposure kommen aus der GLOBALEN Referenz
## LichtKalibrierung, die Energien aus dem HomeLicht-Profil. Draußen
## (Garten) gibt es statt der flachen Hintergrund-Farbe den echten
## GoobyHimmel-Shader (BG_SKY) plus Nebelschleier in Horizontfarbe — die
## Szene endet damit nie mehr in „hellblauer Leere“.
##
## Ausgelagert aus room_base.gd (gdlint-Zeilendeckel). Sonnen-Schatten
## bleiben AUS (Mobile-Budget A §7): Gooby erdet ein Blob-Shadow, das
## Füll-Licht bringt die Gemütlichkeit.


## Environment + Sonne + Füll-Licht an den Raum hängen. `wetter` = Override
## für Tests/Screenshots ({} = echter SoulWetter-Tagesplan). Liefert
## {"fenster_energie": float, "himmel": GoobyHimmel|null}.
static func anbauen(
	room: Node3D,
	room_id: String,
	outdoor: bool,
	stunde: float,
	wetter: Dictionary,
	world_size: Vector2
) -> Dictionary:
	var profil := HomeLicht.profil(room_id, outdoor, stunde)
	var world_env := WorldEnvironment.new()
	world_env.name = "RaumLicht"
	var env := LichtKalibrierung.environment(str(profil["kontext"]))
	var himmel: GoobyHimmel = null
	if outdoor:
		himmel = _himmel_anbauen(env, stunde, wetter)
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = LichtKalibrierung.hintergrund(profil["hintergrund"])
	env.ambient_light_color = profil["ambient_farbe"]
	env.ambient_light_energy = profil["ambient_energie"]
	world_env.environment = env
	room.add_child(world_env)
	room.add_child(_sonne(profil))
	room.add_child(_fuell_licht(profil, world_size))
	return {"fenster_energie": profil["fenster_energie"], "himmel": himmel}


## Echter Himmel für Außen-Räume: GoobyHimmel-Shader mit dem GLEICHEN
## deterministischen Wetterplan wie WetterFx/Dioramen (SoulWetter) + Nebel.
static func _himmel_anbauen(env: Environment, stunde: float, wetter: Dictionary) -> GoobyHimmel:
	var zustand := wetter
	if zustand.is_empty():
		zustand = SoulWetter.zustand(RanchWetter.datum_heute(), stunde)
	var himmel := GoobyHimmel.new()
	himmel.wende_an(stunde, zustand)
	env.background_mode = Environment.BG_SKY
	env.sky = himmel.sky
	LichtKalibrierung.nebel_anwenden(env, himmel.horizont_farbe())
	return himmel


static func _sonne(profil: Dictionary) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sonne"
	sun.light_color = profil["sonnen_farbe"]
	sun.light_energy = profil["sonnen_energie"]
	sun.rotation_degrees = profil["sonnen_rotation"]
	sun.shadow_enabled = false
	return sun


static func _fuell_licht(profil: Dictionary, world_size: Vector2) -> OmniLight3D:
	var fuell := OmniLight3D.new()
	fuell.name = "FuellLicht"
	fuell.light_color = profil["fuell_farbe"]
	fuell.light_energy = profil["fuell_energie"]
	fuell.omni_range = maxf(world_size.x, world_size.y) * 1.1
	fuell.omni_attenuation = 1.4
	fuell.position = Vector3(world_size.x * 0.5, RoomBase.WALL_HEIGHT * 0.9, world_size.y * 0.55)
	fuell.shadow_enabled = false
	return fuell

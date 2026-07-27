class_name RanchRideController
extends Node3D
## Reit-Controller (RANCH-2 + RW-2-DLC): Gooby reitet ein Pferd wie ein
## sanftes Fahrzeug — Gangarten Schritt/Trab/Galopp (+ Tölt fuer
## berechtigte Pferde), Tiefpass-Lenkung, Spruenge mit Timing-Wertung,
## Verfolgerkamera mit Tempo-FOV, Kopfnicken, Staub und Hufschlag-Sounds
## je Untergrund. ALLE Mathematik kommt aus RanchRideFeel/RanchRideStats
## (PURE, getestet); dieser Knoten ist nur die Verdrahtung.
##
## Einbau (RANCH-1): mounten, set_horse()/set_bounds()/set_bindung()
## rufen, optional use_camera=false, HUD-Buttons auf steer_input()/
## gait_up()/gait_down()/jump() verdrahten. Ohne HUD funktioniert die
## Tastatur (Pfeile/WASD, Hoch/Runter = Gangart, Leer = Sprung).
##
## DLC-Schicht (alles optional, Bestand laeuft unveraendert):
##   set_pferd(dict)        — Trainingswerte/Eigenheit/Charakter wirken
##   set_gelaende(h, u)     — RW-1-Gelaende: Bodenhoehe + Untergrund-Id
##   set_hindernisse(pts)   — Sprung-Timing-Zonen ("Perfekt!"-Wertung)
##   zweiter_wind()         — 1×/Ritt Not-Ausdauer beim Streicheln
##   erschrecken()          — Scheu-Check an Spuk-Punkten (RW-1-Wild)
##   telemetrie()           — Ritt-Daten fuer RanchHorseLevels.ritt_training

signal gait_changed(gait: String)
signal jumped
signal landed
## Sprung-Timing-Wertung ("perfekt"|"gut"|"daneben") + Stilpunkte.
signal sprung_gewertet(wertung: String, punkte: int)
## Ausdauer-Tank leer: Schnauben, Kamera sackt, Zwangs-Trab (Kap. 3.4).
signal erschoepft
signal zweiter_wind_genutzt(bonus: float)
signal gescheut

const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")
const Stats := preload("res://scripts/ranch/gameplay/ride_stats.gd")

## Hufschlag-/Pferde-Sounds (RANCH-ASSETS) — geladen wird defensiv.
const SFX_PFAD := "res://assets/ranch/audio/sfx"

## Eigene Verfolgerkamera bauen (false, wenn die Welt schon eine hat).
@export var use_camera := true
## Tastatur-Direktsteuerung (Demo/Desktop); HUDs rufen die Methoden selbst.
@export var keyboard_input := true
## Galopp-Wippen der Kamera (OPT-IN, Standard AUS — kein Screenshake).
@export var wippen_an := false

var gait := "stand"
var tempo := 0.0
var heading := 0.0
var ausdauer := Feel.AUSDAUER_MAX
var active := true
var untergrund := "wiese"

var _horse: Node3D
var _steer_target := 0.0
var _steer := 0.0
var _sprung := {"y": 0.0, "vy": 0.0}
var _in_luft := false
var _bounds_center := Vector2.ZERO
var _bounds_half := Vector2(15.0, 15.0)
var _perks := {"tempo_mult": 1.0, "ausdauer_regen_mult": 1.0}
var _bindung := 50.0
var _camera: Camera3D
var _dust: GPUParticles3D
var _kopf_basis_y := 0.0
var _phase_vorher := 0.0
## --- DLC-Zustand (set_pferd & Co.) ---
var _stats: Dictionary = {}
var _effekte: Dictionary = {}
var _kann_toelt := false
var _laune := 70.0
var _kick_rest := 0.0
var _erschoepft_rest := 0.0
var _bindung_malus := 0.0
var _zweiter_wind_benutzt := false
var _scheu_tempo_rest := 0.0
var _scheu_hops_rest := 0.0
var _scheu_seite := 1.0
var _landung_rest := 0.0
var _wechsel_pending := ""
var _wechsel_rest := 0.0
var _erster_wechsel := true
var _zeit := 0.0
var _hoehe_cb := Callable()
var _untergrund_cb := Callable()
var _hindernisse: Array = []
var _tele := {"unterwegs_s": 0.0, "galopp_m": 0.0, "galopp_s": 0.0, "schritt_laune_s": 0.0}
var _tele_spruenge := {"gut": 0, "perfekt": 0}
var _huf_player: AudioStreamPlayer
var _huf_streams: Dictionary = {}


func _ready() -> void:
	if _horse == null:
		var stub := RanchHorseStub.new()
		add_child(stub)
		set_horse(stub)
	_dust = _build_dust()
	add_child(_dust)
	_huf_player = AudioStreamPlayer.new()
	_huf_player.bus = &"Sfx"
	add_child(_huf_player)
	if use_camera:
		_camera = Camera3D.new()
		_camera.current = true
		get_parent().add_child.call_deferred(_camera)
		_snap_camera.call_deferred()


func _exit_tree() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.queue_free()


func _process(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	if keyboard_input:
		_poll_keyboard()
	_zeit += delta
	_step_timers(delta)
	_step_ride(delta)
	_step_visuals(delta)
	if _camera != null:
		_step_camera(delta)


## Pferd-Knoten übernehmen (Vertrag: RanchHorseStub-API). null = Attrappe.
func set_horse(node: Node3D) -> void:
	_horse = node
	if _horse != null and _horse.has_method("head_pivot"):
		var kopf: Node3D = _horse.head_pivot()
		if kopf != null:
			_kopf_basis_y = kopf.position.y
	_verdrahte_bodenkontakt()


## Reit-Areal (Koppel) setzen: Mitte + Halbausdehnung in Metern (RANCH-1).
func set_bounds(center: Vector3, half: Vector2) -> void:
	_bounds_center = Vector2(center.x, center.z)
	_bounds_half = half


## Bindung des gerittenen Pferds → Tempo-/Ausdauer-Perks (RanchHorseCare)
## + Bindungs-Freischaltungen (Rutsch-Stopp, Zweiter-Wind-Plus).
func set_bindung(bindung: float) -> void:
	_bindung = clampf(bindung, 0.0, 100.0)
	_perks = RanchHorseCare.reit_perks(bindung)


## DLC: das komplette Pferde-Dict anlegen (Save-Format, RanchRassen-
## Felder). Trainingswerte, Rassen-Eigenheit, Charakterzuege, Tölt und
## Laune wirken ab jetzt auf Physik/Ausdauer/Sprung (IDEAS-3 Kap. 2.4).
func set_pferd(pferd: Dictionary) -> void:
	_stats = RanchHorseLevels.stats_effektiv(pferd)
	ausdauer = Stats.ausdauer_max(_stats)
	var eigenheit := ""
	var rasse := RanchRassen.rasse(RanchRassen.load_balance(), str(pferd.get("rasse", "")))
	eigenheit = str(rasse.get("eigenheit", ""))
	_effekte = RanchRassen.eigenheit_effekte(eigenheit).duplicate()
	var charakter: Variant = pferd.get("charakter")
	if charakter is Array:
		for zug: Variant in charakter:
			_effekte.merge(RanchRassen.charakter_effekte(str(zug)))
	_kann_toelt = bool(_effekte.get("toelt", false))
	set_bindung(_num(pferd.get("bindung"), _bindung))
	var werte: Variant = pferd.get("werte")
	if werte is Dictionary:
		_laune = RanchHorseCare.laune(werte, _bindung)


## DLC: Gelaende-Anbindung (RW-1). hoehe = Callable(x, z) -> float,
## untergrund = Callable(pos: Vector3) -> String (UNTERGRUND-Ids).
## Leere Callables = Bestand (flacher Boden y=0, Wiese).
func set_gelaende(hoehe: Callable, untergrund_cb: Callable) -> void:
	_hoehe_cb = hoehe
	_untergrund_cb = untergrund_cb
	_verdrahte_bodenkontakt()


## VIS-2: das Pferd bekommt dieselbe Gelaende-Hoehe fuer seinen
## Huf-Bodenkontakt (RanchPferd hebt das Rig, wenn ein Huf am Hang oder
## auf dem Brueckendeck sonst eintauchen wuerde). Der Stub kennt die API
## nicht — defensiv per has_method.
func _verdrahte_bodenkontakt() -> void:
	if _horse != null and _horse.has_method("set_bodenkontakt"):
		_horse.set_bodenkontakt(_hoehe_cb)


## DLC: Hindernis-Positionen (Welt) fuer die Sprung-Timing-Wertung.
func set_hindernisse(punkte: Array) -> void:
	_hindernisse = punkte.duplicate()


## Lenk-Eingabe -1..1 (HUD/Touch); Tastatur überschreibt bei keyboard_input.
func steer_input(value: float) -> void:
	_steer_target = clampf(value, -1.0, 1.0)


func gait_up() -> void:
	_wechsle_gangart(Stats.gangart_hoch(gait, _kann_toelt))


func gait_down() -> void:
	_wechsle_gangart(Stats.gangart_runter(gait, _kann_toelt))


## Absprung — nur ab Trab-Tempo und am Boden (Feel.kann_springen).
func jump() -> void:
	if not Feel.kann_springen(tempo, float(_sprung["y"])):
		return
	_sprung = {"y": 0.001, "vy": Stats.sprung_vy(_stats)}
	_in_luft = true
	jumped.emit()
	_werte_sprung()
	AudioDirector.try_play(self, "ui_open")


## DLC: Zweiter Wind (Kap. 3.4) — 1×/Ritt, Tank < 10, angehalten +
## streicheln. Ab Bindungs-L6 +35 statt +25. true = hat gezuendet.
func zweiter_wind() -> bool:
	if not Stats.zweiter_wind_moeglich(ausdauer, tempo, _zweiter_wind_benutzt):
		return false
	_zweiter_wind_benutzt = true
	var bonus := RanchHorseBond.zweiter_wind_bonus(_bindung, Feel.ZWEITER_WIND_BONUS)
	ausdauer = clampf(ausdauer + bonus, 0.0, Stats.ausdauer_max(_stats))
	zweiter_wind_genutzt.emit(bonus)
	_spiele_pferdelaut("pferd_wiehern", 1.05)
	return true


## DLC: Scheu-Check an einem Spuk-Punkt (RW-1-Wildtiere, Planen …).
## Wuerfelt gegen Gelassenheit + Zuege; true = Pferd ist gescheut.
func erschrecken() -> bool:
	var chance := Stats.scheu_chance(_stats, _num(_effekte.get("scheu_mult"), 1.0))
	if randf() >= chance:
		return false
	_scheu_tempo_rest = Feel.SCHEU_TEMPO_S
	_scheu_hops_rest = Feel.SCHEU_DAUER_S
	_scheu_seite = 1.0 if randf() < 0.5 else -1.0
	gescheut.emit()
	_spiele_pferdelaut("pferd_wiehern", 1.2)
	return true


## DLC: Abstand (m) zum naechsten Hindernis in Laufrichtung, −1 = keins
## in Reichweite. Das HUD pulsiert damit den Sprung-Button.
func naechstes_hindernis_m() -> float:
	return _hindernis_abstand()


## Ausdauer-Tank des aktuellen Pferds (HUD-Balken-Skala).
func ausdauer_max() -> float:
	return Stats.ausdauer_max(_stats) if not _stats.is_empty() else Feel.AUSDAUER_MAX


## Ist der Zweite Wind gerade zuendbar? (HUD zeigt den Streicheln-Knopf.)
func zweiter_wind_bereit() -> bool:
	return Stats.zweiter_wind_moeglich(ausdauer, tempo, _zweiter_wind_benutzt)


## DLC: Ritt-Telemetrie fuer RanchHorseLevels.ritt_training (beim
## Absitzen buchen). bindung_malus = Erschoepfungs-Abzug (Kap. 3.4).
func telemetrie() -> Dictionary:
	return {
		"unterwegs_min": float(_tele["unterwegs_s"]) / 60.0,
		"galopp_m": float(_tele["galopp_m"]),
		"galopp_s": float(_tele["galopp_s"]),
		"sprung_gut": int(_tele_spruenge["gut"]),
		"sprung_perfekt": int(_tele_spruenge["perfekt"]),
		"slalom_tore": 0,
		"schritt_laune_min": float(_tele["schritt_laune_s"]) / 60.0,
		"bindung_malus": _bindung_malus,
	}


## ------------------------------------------------------------ Ritt-Schritte


func _step_timers(delta: float) -> void:
	_kick_rest = maxf(0.0, _kick_rest - delta)
	_erschoepft_rest = maxf(0.0, _erschoepft_rest - delta)
	_scheu_tempo_rest = maxf(0.0, _scheu_tempo_rest - delta)
	_scheu_hops_rest = maxf(0.0, _scheu_hops_rest - delta)
	_landung_rest = maxf(0.0, _landung_rest - delta)
	if _wechsel_pending != "":
		_wechsel_rest -= delta
		if _wechsel_rest <= 0.0:
			var ziel := _wechsel_pending
			_wechsel_pending = ""
			_setze_gangart(ziel)


func _step_ride(delta: float) -> void:
	var war_leer := ausdauer <= 0.0
	var regen := (
		float(_perks["ausdauer_regen_mult"]) * _num(_effekte.get("ausdauer_regen_mult"), 1.0)
	)
	ausdauer = Stats.step_ausdauer(ausdauer, gait, delta, _stats, regen)
	if ausdauer <= 0.0 and not war_leer:
		_auf_erschoepfung()
	var effektiv := Stats.gangart_nach_ausdauer(gait, ausdauer, _ist_schnell(gait))
	if effektiv != gait:
		gait = effektiv
		gait_changed.emit(gait)
	_steer = Feel.smooth_steer(_steer, _steer_target, delta)
	heading = Feel.wrap_angle(heading - Stats.steer_yaw_rate(_steer, tempo, _stats) * delta)
	tempo = Stats.step_tempo(
		tempo,
		_zieltempo(),
		delta,
		Stats.accel_auf(gait, _kick_rest),
		RanchHorseBond.brems_bonus(_bindung)
	)
	var vorwaerts := Vector2(sin(heading), cos(heading)) * -1.0
	var pos := Vector2(position.x, position.z) + vorwaerts * tempo * delta
	if _scheu_hops_rest > 0.0:
		var seit := Vector2(cos(heading), -sin(heading)) * _scheu_seite
		pos += seit * (Feel.SCHEU_HOPS_M / Feel.SCHEU_DAUER_S) * delta
	pos = Feel.clamp_bounds(pos, _bounds_center, _bounds_half)
	if _in_luft:
		_sprung = Feel.step_sprung(_sprung, delta)
		if float(_sprung["y"]) <= 0.0:
			_in_luft = false
			_landung_rest = Feel.LANDUNGS_KICK_S
			landed.emit()
			AudioDirector.try_play(self, "mg_good", 0.8)
	position = Vector3(pos.x, _boden_y(pos) + float(_sprung["y"]), pos.y)
	rotation.y = heading
	untergrund = _lies_untergrund()
	_sammle_telemetrie(delta)


func _zieltempo() -> float:
	var ziel := Stats.zieltempo(gait, _stats, float(_perks["tempo_mult"]))
	ziel *= Stats.untergrund_tempo_mult(untergrund, _num(_effekte.get("gelaende_malus_mult"), 1.0))
	if _scheu_tempo_rest > 0.0:
		ziel *= Feel.SCHEU_TEMPO_MULT
	return ziel


## Erschoepfungsmoment (Kap. 3.4): Schnauben, Kamera sackt, Bindungs-
## Malus nur bei Laune < 40 (max 3/Tag — Deckel bucht RANCH-1 am Tag).
func _auf_erschoepfung() -> void:
	_erschoepft_rest = Feel.ERSCHOEPFT_SCHNAUBEN_S
	_bindung_malus += Stats.erschoepfung_bindung_malus(_laune, _bindung_malus)
	erschoepft.emit()
	_spiele_pferdelaut("pferd_schnauben", 1.0)


## Sprung-Timing gegen das naechste Hindernis in Laufrichtung werten.
func _werte_sprung() -> void:
	var beste := _hindernis_abstand()
	if beste < 0.0 or beste > 6.0:
		return
	var bonus := _num(_effekte.get("sprungfenster_bonus_ms"), 0.0)
	var wertung := Stats.sprung_wertung(beste, tempo, bonus)
	if wertung != "daneben":
		_tele_spruenge[wertung] = int(_tele_spruenge[wertung]) + 1
	var punkte := Feel.SPRUNG_PERFEKT_PUNKTE if wertung == "perfekt" else 0
	sprung_gewertet.emit(wertung, punkte)


## Naechstes Hindernis voraus (±2 m seitlich toleriert) oder −1.
func _hindernis_abstand() -> float:
	var vorwaerts := Vector2(sin(heading), cos(heading)) * -1.0
	var pos := Vector2(position.x, position.z)
	var beste := -1.0
	for punkt: Variant in _hindernisse:
		if not (punkt is Vector3):
			continue
		var d := Vector2((punkt as Vector3).x, (punkt as Vector3).z) - pos
		var entlang := d.dot(vorwaerts)
		if entlang > 0.0 and absf(d.cross(vorwaerts)) < 2.0 and (beste < 0.0 or entlang < beste):
			beste = entlang
	return beste


func _sammle_telemetrie(delta: float) -> void:
	if tempo > 0.2:
		_tele["unterwegs_s"] = float(_tele["unterwegs_s"]) + delta
	if gait == "galopp":
		_tele["galopp_m"] = float(_tele["galopp_m"]) + tempo * delta
		_tele["galopp_s"] = float(_tele["galopp_s"]) + delta
	if gait == "schritt" and _laune >= RanchHorseLevels.SCHRITT_LAUNE_AB:
		_tele["schritt_laune_s"] = float(_tele["schritt_laune_s"]) + delta


func _boden_y(pos: Vector2) -> float:
	if _hoehe_cb.is_valid():
		return _num(_hoehe_cb.call(pos.x, pos.y), 0.0)
	return 0.0


func _lies_untergrund() -> String:
	if _untergrund_cb.is_valid():
		var raw: Variant = _untergrund_cb.call(position)
		if raw is String and Feel.UNTERGRUND.has(raw):
			return raw
	return "wiese"


## ----------------------------------------------------------- Optik + Kamera


func _step_visuals(delta: float) -> void:
	if _horse == null:
		return
	if _horse.has_method("set_gait"):
		_horse.set_gait(gait)
	if _horse.has_method("tick"):
		_horse.tick(delta, tempo)
	var phase := _phase_vorher
	if _horse.has_method("phase"):
		phase = float(_horse.phase())
	_spiele_hufschlaege(phase)
	if _horse.has_method("head_pivot"):
		var kopf: Node3D = _horse.head_pivot()
		if kopf != null:
			var amp_mult := _num(_effekte.get("nick_amp_mult"), 1.0)
			kopf.position.y = _kopf_basis_y + Feel.kopfnicken(phase, gait) * amp_mult
	_dust.amount_ratio = maxf(0.05, Feel.staub_anteil(gait))
	_dust.emitting = Feel.staub_anteil(gait) > 0.0 and not _in_luft


func _spiele_hufschlaege(phase: float) -> void:
	var schlaege := Feel.hufschlaege(_phase_vorher, phase)
	if phase < _phase_vorher:
		schlaege = Feel.hufschlaege(_phase_vorher, 1.0) + Feel.hufschlaege(0.0, phase)
	_phase_vorher = phase
	if schlaege <= 0 or _in_luft or gait == "stand":
		return
	var info := Stats.untergrund_info(untergrund)
	var stream := _huf_stream(str(info.get("sound", "huf_gras")))
	if stream == null:
		AudioDirector.try_play(self, "ui_tick", 1.0 + randf_range(-0.04, 0.04))
		return
	_huf_player.stream = stream
	_huf_player.volume_db = _num(info.get("vol_db"), 0.0) - (6.0 if gait == "schritt" else 0.0)
	_huf_player.pitch_scale = _num(info.get("pitch"), 1.0) + randf_range(-0.05, 0.05)
	_huf_player.play()


func _step_camera(delta: float) -> void:
	var hinten := Vector3(sin(heading), 0.0, cos(heading))
	var extra_y := Stats.kamera_y_offset(
		_erschoepft_rest > 0.0, _landung_rest, wippen_an, gait, _zeit
	)
	var ziel := position + hinten * Feel.CAM_BACK + Vector3(0.0, Feel.CAM_HEIGHT + extra_y, 0.0)
	var f := Feel.cam_follow_factor(delta)
	_camera.position = _camera.position.lerp(ziel, f)
	_camera.look_at(position + Vector3(0.0, 1.2, 0.0) - hinten * 2.0)
	_camera.fov = lerpf(_camera.fov, Feel.fov_fuer_tempo(tempo), f)


func _snap_camera() -> void:
	if _camera == null:
		return
	var hinten := Vector3(sin(heading), 0.0, cos(heading))
	_camera.position = position + hinten * Feel.CAM_BACK + Vector3(0.0, Feel.CAM_HEIGHT, 0.0)
	_camera.look_at(position + Vector3(0.0, 1.2, 0.0))
	_camera.fov = Feel.fov_fuer_tempo(tempo)


## ---------------------------------------------------------------- Eingabe


func _poll_keyboard() -> void:
	var steer := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		steer -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		steer += 1.0
	_steer_target = steer


func _unhandled_key_input(event: InputEvent) -> void:
	if not keyboard_input or not active:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_UP, KEY_W:
			gait_up()
		KEY_DOWN, KEY_S:
			gait_down()
		KEY_SPACE:
			jump()


## Gangart-Wunsch: sture Pferde zoegern den ERSTEN Wechsel des Ritts
## hinaus (Kap. 1.3); danach schaltet es direkt.
func _wechsle_gangart(neu: String) -> void:
	var verzoegerung := _num(_effekte.get("erster_wechsel_verzoegerung_s"), 0.0)
	if _erster_wechsel and verzoegerung > 0.0 and neu != gait:
		_erster_wechsel = false
		_wechsel_pending = neu
		_wechsel_rest = verzoegerung
		return
	_erster_wechsel = false
	_setze_gangart(neu)


func _setze_gangart(neu: String) -> void:
	var effektiv := Stats.gangart_nach_ausdauer(neu, ausdauer, _ist_schnell(gait))
	if effektiv == gait:
		return
	if effektiv == "galopp" and gait != "galopp":
		_kick_rest = Stats.kick_dauer_s(_effekte)
	gait = effektiv
	gait_changed.emit(gait)


## ------------------------------------------------------------------ Helfer


func _ist_schnell(g: String) -> bool:
	return g == "galopp" or g == "toelt"


## Pferde-Laut (a/b-Varianten) defensiv aus den Ranch-Assets spielen —
## individuell gepitcht ueber stimm_pitch des Pferd-Knotens.
func _spiele_pferdelaut(basis: String, pitch: float) -> void:
	var variante := "a" if randf() < 0.5 else "b"
	var stream := _huf_stream("%s_%s" % [basis, variante])
	if stream == null:
		return
	var stimme := 1.0
	if _horse != null:
		stimme = _num(_horse.get("stimm_pitch"), 1.0)
	_huf_player.stream = stream
	_huf_player.volume_db = 0.0
	_huf_player.pitch_scale = pitch * clampf(stimme, 0.6, 1.4)
	_huf_player.play()


func _huf_stream(id: String) -> AudioStream:
	if _huf_streams.has(id):
		return _huf_streams[id]
	var pfad := "%s/%s.ogg" % [SFX_PFAD, id]
	var stream: AudioStream = load(pfad) if ResourceLoader.exists(pfad) else null
	_huf_streams[id] = stream
	return stream


func _build_dust() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 24
	particles.lifetime = 0.7
	particles.emitting = false
	particles.local_coords = false
	particles.position = Vector3(0.0, 0.12, 0.62)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.6)
	mat.spread = 32.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.4
	mat.gravity = Vector3(0.0, -0.4, 0.0)
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	mat.color = Color(0.76, 0.66, 0.5, 0.55)
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 6
	mesh.rings = 3
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.8, 0.7, 0.55, 0.5)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh
	return particles


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback

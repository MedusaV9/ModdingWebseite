class_name PflegeRunner
extends Node
## Pflege-Runner im Raum (REST-3, Rang 5+6): macht Schlaf-, Krankheits- und
## Gewichtszustand aus dem Save SICHTBAR. Wird wie InteractablesHost /
## GoobyReactions pro Raum angehaengt (home_entry._on_travel_finished).
##
## Was hier lebt (Logik ist PURE in scripts/logic/ — dieser Node ist Glue):
##  - Muedigkeit: Augenringe (rig.set_care), Gaehnen (Mund-Puls + sleepy),
##    langsamerer Watschelgang (gooby.speed_mult) — rein kosmetisch.
##  - Krankheit: blasse Haut, Schniefnase, Eisbeutel (Grad 2), gelegentliches
##    Niesen mit Ton, gedaempftes Tempo. Nie blockierend, nie bestrafend.
##  - Gewicht (P1-Bug): rig.set_weight speist die Silhouetten-Skalierung.
##  - Schlaf: schlafender Gooby liegt im sleep-Clip (kein Wandern); das
##    Ticker-wokeUp inszeniert die wake_morning-Cutscene + Morgen-Zeile.
## Reduced Motion: Kino/Niesen-Hopser entfallen, Zustandslogik bleibt.

const Sleep := preload("res://scripts/logic/sleep.gd")
const Health := preload("res://scripts/logic/health.gd")
const Weight := preload("res://scripts/logic/weight.gd")

## Zustands-Abgleich mit dem Save (Sekunden) — Signale decken das meiste ab,
## der Timer faengt stille Aenderungen (z. B. Ticker-Verfall ohne Low-Event).
const REFRESH_S := 2.0
## Gaehnen: ab dieser Muedigkeit (0..1), zufaellig alle YAWN_MIN..MAX s.
const YAWN_FROM := 0.35
const YAWN_MIN_S := 18.0
const YAWN_MAX_S := 32.0
## Niesen: kraenklich selten, richtig krank oefter.
const SNEEZE_QUEASY_MIN_S := 22.0
const SNEEZE_QUEASY_MAX_S := 40.0
const SNEEZE_SICK_MIN_S := 12.0
const SNEEZE_SICK_MAX_S := 24.0
## Tempo-Daempfung: voll muede −35 %; kraenklich/krank deckeln zusaetzlich.
const SLOW_TIRED := 0.35
const SPEED_QUEASY := 0.85
const SPEED_SICK := 0.6

var room: Node = null
var gs: Object = null
var gooby: Node = null
var rng := RandomNumberGenerator.new()

var _refresh_timer := 0.0
var _yawn_timer := 0.0
var _sneeze_timer := 0.0
var _sleep_posed := false
var _wake_running := false


## Runner erzeugen und an einen RoomBase haengen (idempotent pro Raum).
static func attach_to(target_room: Node) -> PflegeRunner:
	var existing := target_room.get_node_or_null("PflegeRunner")
	if existing is PflegeRunner:
		return existing
	# W18/4-B9: ohne Home-Gooby (Urlaub) KEIN Runner — Schlaf/Kranken-
	# Bubbles sind Gooby-Sprüche, im leeren Raum wären sie Geister-Stimmen.
	if target_room.has_method("gooby") and target_room.gooby() == null:
		return null
	var runner := PflegeRunner.new()
	runner.name = "PflegeRunner"
	target_room.add_child(runner)
	runner.setup(target_room)
	return runner


## Tempo-Faktor (PURE, testbar): Muedigkeit skaliert linear runter, Krankheit
## deckelt — nie unter SPEED_SICK, Gooby kommt IMMER noch ueberall hin.
static func speed_mult_for(grade: int, tired01: float) -> float:
	var v := 1.0 - SLOW_TIRED * clampf(tired01, 0.0, 1.0)
	if grade >= 2:
		v = minf(v, SPEED_SICK)
	elif grade >= 1:
		v = minf(v, SPEED_QUEASY)
	return v


func setup(target_room: Node) -> void:
	room = target_room
	gs = room.game_state() if room.has_method("game_state") else null
	gooby = room.gooby() if room.has_method("gooby") else null
	if gs == null:
		return
	rng.randomize()
	_yawn_timer = rng.randf_range(YAWN_MIN_S, YAWN_MAX_S)
	_arm_sneeze()
	if gs.has_signal("gooby_events"):
		gs.gooby_events.connect(_on_gooby_events)
	if gs.has_signal("stats_changed"):
		gs.stats_changed.connect(func(_stats: Dictionary) -> void: refresh())
	refresh()


func _process(delta: float) -> void:
	if gs == null:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_S
		refresh()
	if _busy() or _sleeping():
		return
	if _tired01() >= YAWN_FROM:
		_yawn_timer -= delta
		if _yawn_timer <= 0.0:
			_yawn_timer = rng.randf_range(YAWN_MIN_S, YAWN_MAX_S)
			_yawn()
	if _grade() >= 1:
		_sneeze_timer -= delta
		if _sneeze_timer <= 0.0:
			_arm_sneeze()
			_sneeze()


## Save → Optik: Gewichts-Silhouette, Pflege-Look (blass/Nase/Eisbeutel/
## Augenringe), Watschel-Tempo und die Schlaf-Pose abgleichen.
func refresh() -> void:
	if gs == null:
		return
	var slice := _gooby_slice()
	var stats: Dictionary = _dict(slice.get("stats"))
	var grade := Health.grade(slice.get("health"))
	var tired := Sleep.tiredness01(stats)
	var rig := _rig()
	if rig != null:
		rig.set_weight(Weight.clamp_weight(slice.get("weight", Weight.DEFAULT)))
		rig.set_care(grade, 0.0 if _sleeping() else tired)
	if gooby != null:
		gooby.set("speed_mult", speed_mult_for(grade, tired))
	_apply_sleep_pose()


# ── Ticker-Events ─────────────────────────────────────────────────────────────


func _on_gooby_events(events: Array) -> void:
	if events.has("wokeUp"):
		_wake_moment()
	if events.has("tummyWarning"):
		_say(I18nService.t("health.warnung_bauch"))
	if events.has("becameQueasy"):
		_say(I18nService.t("health.kraenklich"))
		_set_emotion("sad")
	if events.has("becameSick"):
		_say(I18nService.t("health.krank"))
		_set_emotion("sad")
	if events.has("recovered"):
		_say(I18nService.t("health.erholt"))
		_set_emotion("happy")
	refresh()


## Aufwachen nach vollem Schlaf (Ticker hat Grants schon gebucht): Kino
## (wake_morning, existierte ohne Aufrufer) → Morgen-Zeile → weiterwuseln.
func _wake_moment() -> void:
	if _wake_running:
		return
	_wake_running = true
	_sleep_posed = false
	if room != null and not _reduced_motion():
		var player := CutscenePlayer.play_in_room(room, gs, "wake_morning")
		if player != null:
			await player.spielen()
	if gooby != null:
		gooby.play_clip("idle")
		gooby.set_wander_enabled(true)
	_set_emotion("happy")
	_say(I18nService.t("sleep.aufgewacht"))
	_wake_running = false
	refresh()


# ── Sichtbare Momente ─────────────────────────────────────────────────────────


## Herzhaftes Gaehnen: sleepy-Gesicht + Mund-Puls + leiser tiefer Squish.
func _yawn() -> void:
	var rig := _rig()
	if rig != null:
		rig.set_emotion("sleepy")
		rig.babble_pulse()
	AudioDirector.try_play(self, "pet_squish", 0.7)
	if rng.randf() < 0.35:
		_say(I18nService.t("sleep.gaehnen"))


## Hatschi: Squash-Stretch am Rig (Reduced Motion: nur Ton) + heller Squish.
func _sneeze() -> void:
	var rig := _rig()
	if rig != null:
		rig.sneeze()
	AudioDirector.try_play(self, "pet_squish", 1.55)
	if rng.randf() < 0.5:
		_say(I18nService.t("health.hatschi"))


## Schlafender Gooby liegt ruhig im sleep-Clip (Bett-Snap + Yaw); nach dem
## Aufwachen (frueh geweckt via Bett ODER wokeUp) laeuft er wieder los.
## Snap wird bei jedem refresh erneut gesetzt, falls Gooby verrutscht.
func _apply_sleep_pose() -> void:
	var sleeping := _sleeping()
	if sleeping:
		if gooby != null:
			if gooby.has_method("cancel_walk"):
				gooby.cancel_walk()
			gooby.set_wander_enabled(false)
			var bed := _find_bed_furniture()
			if bed != null and gooby.has_method("lie_on_bed"):
				gooby.lie_on_bed(bed)
			if not _sleep_posed:
				gooby.play_clip("sleep")
		_sleep_posed = true
		_set_emotion("sleepy")
	elif not sleeping and _sleep_posed and not _wake_running:
		_sleep_posed = false
		if gooby != null:
			gooby.play_clip("idle")
			gooby.set_wander_enabled(true)


## Bett-Möbel im Raum finden (InteractablesHost → Bett._furniture).
func _find_bed_furniture() -> Node3D:
	if room == null:
		return null
	var host := room.get_node_or_null("InteractablesHost")
	if host == null:
		return null
	for child in host.get_children():
		if child is Bett:
			var furniture: Variant = child.get("_furniture")
			if furniture is Node3D and is_instance_valid(furniture):
				return furniture
			return child
	return null


func _arm_sneeze() -> void:
	if _grade() >= 2:
		_sneeze_timer = rng.randf_range(SNEEZE_SICK_MIN_S, SNEEZE_SICK_MAX_S)
	else:
		_sneeze_timer = rng.randf_range(SNEEZE_QUEASY_MIN_S, SNEEZE_QUEASY_MAX_S)


# ── Helfer ────────────────────────────────────────────────────────────────────


func _gooby_slice() -> Dictionary:
	if gs == null or not gs.has_method("state"):
		return {}
	return _dict((gs.state() as Dictionary).get("gooby"))


func _sleeping() -> bool:
	return Sleep.is_sleeping(_gooby_slice())


func _tired01() -> float:
	return Sleep.tiredness01(_gooby_slice().get("stats"))


func _grade() -> int:
	return Health.grade(_gooby_slice().get("health"))


func _rig() -> GoobyRig:
	if gooby == null:
		return null
	var value: Variant = gooby.get("rig")
	return value if value is GoobyRig else null


func _set_emotion(id: String) -> void:
	var rig := _rig()
	if rig != null:
		rig.set_emotion(id)


func _say(text: String) -> void:
	if room != null and room.has_method("say"):
		room.say(text)


func _busy() -> bool:
	if room == null or gs == null:
		return true
	if room.has_method("is_build_mode_active") and room.is_build_mode_active():
		return true
	return false


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

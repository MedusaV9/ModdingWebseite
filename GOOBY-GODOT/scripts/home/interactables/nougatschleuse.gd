class_name Nougatschleuse
extends Node3D
## Nougatschleuse-Interactable (W13/FOOD, P1 Punkt 17; Web §B7/§C6.4 +
## home/interactions.js nougatTap): der Wand-Schokospender in der Küche.
## Andocken (Möbel-Id `nougatschleuse`, s. furniture_catalog.json) setzt
## einmalig easterEggs.nougat.installed (Web: Kauf-Karte setzt das Flag,
## roomManager mountet). Tap → Refusal-Matrix (schlafend/krank/Cooldown,
## knuffige Zeilen aus strings/*/nougat.json) → Kurbel+Klecks-Sequenz
## (~2,8 s: Gooby watschelt unter den Auslauf, Kurbel-Quietscher mit
## Pitch-Treppe, Squash) → Wirkung PUR über NougatLogic.apply_glob
## (Stats +15/+10/−8, Junk ×2, Gewicht ×1, XP +2, Glas-Ausgabe, Cooldown,
## nougatGlobs-Counter) → RewardHub.note_action für die Sticker
## nutellaGlob/nougatFlood/kueche_nutellabrot.
##
## Einhängen (Host-Request, W13-requests.md): InteractablesHost.rescan
## dockt `nougatschleuse` → Nougatschleuse.new() an.

const KURBEL_PITCHES: Array[float] = [0.8, 0.95, 1.1]
const KURBEL_ABSTAND_S := 0.7
const HERZ_TEILE := 10
const KLECKS_KEYS: Array[String] = ["nougat.klecks1", "nougat.klecks2", "nougat.klecks3"]

var _host: InteractablesHost
var _rng := RandomNumberGenerator.new()
var _busy := false


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_rng.randomize()
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))
	_mark_installed()


func is_busy() -> bool:
	return _busy


## Erst-Installation persistieren (idempotent) — Web-Parität: das Flag
## `easterEggs.nougat.installed` speist Sticker-Hints und den Recap.
func _mark_installed() -> void:
	var gs := _host.game_state()
	if gs == null:
		return
	var fresh := {"neu": false}
	gs.update(func(state: Dictionary) -> void: fresh["neu"] = NougatLogic.mark_installed(state))
	if fresh["neu"]:
		_say_key("nougat.installiert")


func _on_tapped() -> void:
	if _busy or _room_busy():
		return
	var gs := _host.game_state()
	if gs == null:
		return
	var now := _now_ms()
	var verdict := NougatLogic.can_glob(gs.state(), now)
	if not bool(verdict.get("ok", false)):
		_say_refusal(str(verdict.get("reason", "")), gs, now)
		return
	_glob(gs)


func _say_refusal(reason: String, gs: Object, now: int) -> void:
	match reason:
		"sleeping":
			_say_key("nougat.schlaeft")
		"sick":
			_say_key("nougat.krank")
		"cooldown":
			var rest_ms := NougatLogic.cooldown_remaining_ms(gs.state(), now)
			var minuten := maxi(1, int(ceilf(rest_ms / 60000.0)))
			_say_text(I18nService.t("nougat.pause", {"minuten": minuten}))


# ── Kurbel+Klecks-Ablauf ──────────────────────────────────────────────────────


func _glob(gs: Object) -> void:
	_busy = true
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		await gooby.walk_to(global_position + Vector3(0.0, 0.0, 0.8), 5.0)
	await _kurbel_sequenz(gooby)
	var result := {}
	gs.update(
		func(state: Dictionary) -> void:
			result.merge(NougatLogic.apply_glob(state, _now_ms()), true)
	)
	if result.is_empty():
		# Fail-closed (z. B. Zustand kippte während der Sequenz): kein Effekt.
		_restore(gooby)
		return
	RewardHub.note_action(gs)
	AudioDirector.try_play(self, "mg_perfect", 1.05)
	_say_text(I18nService.t(KLECKS_KEYS[_rng.randi_range(0, KLECKS_KEYS.size() - 1)]))
	# W14/VOICE-Anbindung: frische Reaktions-Line (Bremse/Anti-Wdh. inklusive).
	SeeleRunner.kommentar_im_raum(_host.room(), "w13.nougat")
	_show_reward(gooby, result)
	_restore(gooby)


## Kurbel-Quietscher mit Pitch-Treppe + Squash-Wippen (Web: crank 720°,
## Sequenz ≈ 2,8 s). Reduced Motion: Töne bleiben, das Wippen fällt weg.
func _kurbel_sequenz(gooby: Node) -> void:
	var rig: Node3D = gooby.get("rig") if gooby != null else null
	if rig != null:
		rig.set_emotion("ecstatic")
	var reduced := RewardFx.reduced_motion(self)
	for pitch: float in KURBEL_PITCHES:
		AudioDirector.try_play(self, "mg_good", pitch)
		if rig != null and not reduced:
			var tween := rig.create_tween()
			tween.tween_property(rig, "scale:y", 0.9, KURBEL_ABSTAND_S * 0.4)
			tween.tween_property(rig, "scale:y", 1.0, KURBEL_ABSTAND_S * 0.5)
		if is_inside_tree():
			await get_tree().create_timer(KURBEL_ABSTAND_S).timeout
	if rig != null:
		rig.set_emotion("happy")


## Sichtbare Wirkung: „+{hunger}"-Float in Mint, Glas-Bonus in Gold,
## Herz-Burst über Gooby (Muster Kuehlschrank._show_reward).
func _show_reward(gooby: Node, result: Dictionary) -> void:
	var room := _host.room()
	if room == null:
		return
	var pos: Vector3 = global_position + Vector3(0.0, 0.9, 0.8)
	if gooby is Node3D:
		pos = (gooby as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
	var gain := int(roundf(float(result.get("hunger_gain", 0.0))))
	if gain > 0:
		RewardFx.float_text(room, pos, "+%d" % gain, RewardFx.MINT)
	RewardFx.float_text(
		room,
		pos + Vector3(0.0, 0.35, 0.0),
		"+1 %s" % FoodCatalog.display_name(str(result.get("jar_id", ""))),
		RewardFx.GOLD
	)
	RewardFx.herz_burst(room, pos + Vector3(0.0, -0.3, 0.0), HERZ_TEILE)


func _restore(gooby: Node) -> void:
	if gooby != null:
		gooby.play_clip("hop")
		gooby.set_wander_enabled(true)
	_busy = false


# ── Helfer ────────────────────────────────────────────────────────────────────


func _gooby() -> Node:
	var room := _host.room()
	if room != null and room.has_method("gooby"):
		return room.gooby()
	return null


func _say_key(key: String) -> void:
	_say_text(I18nService.t(key))


func _say_text(text: String) -> void:
	var room := _host.room()
	if room != null and room.has_method("say"):
		room.say(text)


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()


func _now_ms() -> int:
	var gs := _host.game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)

extends TestCase
## W19-Playtest HUD-ALERT-PULS — beim Übergang Settings → DLC-Bibliothek
## feuerte einmalig „Infinite loop detected (set_loops)“ plus mehrere
## „Target object freed before starting, aborting Tweener“ (hud.gd,
## _start_alert_pulse): der Puls-Loop-Tween hing am LANGLEBIGEN HUD
## (create_tween() bindet an den Aufrufer), tweent aber die Stat-Chips —
## wird ein Chip vor dem HUD freigegeben, brechen alle Tweener ab, der
## Loop braucht 0 Frames und Godots Endlos-Schutz killt ihn laut. Wächter:
## - Puls startet unter der Schwelle (< 25) und stoppt sauber darüber.
## - Der Tween ist an den CHIP gebunden: verlässt der Chip den Baum,
##   pausiert der Puls (kein Weiter-Schreiben auf scale/modulate mehr —
##   VOR dem Fix lief er weiter, das ist die rote Probe).
## - Wird der Chip freigegeben, stirbt der Tween lautlos mit (kein
##   Zombie-Loop, der in den Engine-Error läuft).
## - Keine 0-Dauer-Loop-Kante: ALERT_PULS_S ist eine Konstante > 0.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")

## Alle 4 Stats satt — nur „hunger“ fällt in den Tests unter die Schwelle.
const STATS_SATT := {"hunger": 80.0, "energie": 80.0, "hygiene": 80.0, "spass": 80.0}


## Reduced Motion global setzen; gibt den vorherigen Zustand zurück
## (Muster test_g7_hud_dynamik — der Puls existiert nur OHNE Reduced Motion).
func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func test_puls_dauer_nie_null() -> void:
	# Die „Infinite loop detected“-Meldung feuert, sobald ein Loop-Durchlauf
	# 0 Frames braucht — die Puls-Dauer muss deshalb hart > 0 sein.
	assert_true(Hud.ALERT_PULS_S > 0.0, "Puls-Dauer ist konstant > 0 (keine 0-Dauer-Kante)")


func test_alert_puls_stirbt_mit_dem_chip() -> void:
	var rm_vorher := _set_reduced_motion(false)
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(2)
	var stats: Dictionary = STATS_SATT.duplicate()
	stats["hunger"] = 10.0
	hud.set_stats(stats)
	assert_true(hud.is_stat_alerting("hunger"), "Puls unter der Schwelle aktiv")
	var tween: Tween = hud._alert_tweens["hunger"]
	assert_true(tween != null and tween.is_valid(), "Loop-Tween läuft")
	var chip := hud._stat_chips["hunger"] as Control
	# Teil-Abbau simulieren: der Chip verlässt den Baum VOR dem HUD (die
	# Szenenwechsel-Reihenfolge aus dem Playtest-Log). Ein an den Chip
	# gebundener Tween pausiert jetzt — der alte HUD-gebundene lief weiter.
	chip.get_parent().remove_child(chip)
	await wait_frames(2)
	var scale_vorher := chip.scale
	var modulate_vorher := chip.modulate
	await wait_frames(3)
	assert_eq(chip.scale, scale_vorher, "außerhalb des Baums pausiert der Puls (gebunden)")
	assert_eq(chip.modulate, modulate_vorher, "auch die Alarm-Färbung steht still")
	# Chip stirbt: der gebundene Tween stirbt lautlos mit — kein Tweener-
	# Abbruch, kein „Infinite loop detected“ im Log der folgenden Frames.
	chip.free()
	await wait_frames(3)
	assert_false(tween.is_valid(), "Tween stirbt mit dem Chip (kein Zombie-Loop)")
	hud.free()
	_set_reduced_motion(rm_vorher)


func test_alert_puls_stoppt_ueber_der_schwelle() -> void:
	var rm_vorher := _set_reduced_motion(false)
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(2)
	var stats: Dictionary = STATS_SATT.duplicate()
	stats["hunger"] = 10.0
	hud.set_stats(stats)
	var tween: Tween = hud._alert_tweens["hunger"]
	assert_true(tween != null and tween.is_valid(), "Puls läuft unter der Schwelle")
	hud.set_stats(STATS_SATT)
	assert_false(hud.is_stat_alerting("hunger"), "über der Schwelle: kein Alert mehr")
	# kill() räumt den Tween erst im nächsten Tween-Takt aus der SceneTree.
	await wait_frames(1)
	assert_false(tween.is_valid(), "Stop killt den Loop-Tween sauber")
	var chip := hud._stat_chips["hunger"] as Control
	assert_eq(chip.scale, Vector2.ONE, "Ruhelage: Skalierung zurückgesetzt")
	assert_eq(chip.modulate, Color.WHITE, "Ruhelage: Färbung zurückgesetzt")
	hud.free()
	_set_reduced_motion(rm_vorher)

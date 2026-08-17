extends TestCase
## W13C/RELEASE — „Jetzt neu laden“-Soft-Restart (Doc B §2.4; docs/UPDATES.md
## §5.5). Pur mit Fake-Diensten + injizierter Zeit: (1) Gates — Besuch/
## Brettspiel/Minigame/Reise verweigern, OHNE irgendeinen Dienst anzufassen;
## (2) Flush-Reihenfolge als Aufruf-Protokoll (Save → Netz → Musik-Fade →
## Remount → Registry → Router → Reboot); (3) die Settings-Glue bietet den
## Knopf NUR nach installiertem PCK-Update an (config-only = sofort wirksam,
## kein Knopf), mit Bestätigungs-Dialog und Gate-Toast.


## Ein „is_active“-Kind der Social-Dienste (visit/board/chess).
class FakeActive:
	extends RefCounted
	var active := false

	func is_active() -> bool:
		return active


## Social-Double: Duck-Typing-Ziel für SoftRestart.blocked_reason().
class FakeSocial:
	extends RefCounted
	var visit := FakeActive.new()
	var board := FakeActive.new()
	var chess := FakeActive.new()


## SceneRouter-Double: aktuelles Ziel + busy; clear_history protokolliert
## ins geteilte Log (Reihenfolge über Dienstgrenzen hinweg beweisbar).
class FakeRouter:
	extends RefCounted
	var target := &"home/living"
	var busy := false
	var history_cleared := 0
	var log: Array

	func _init(shared: Array) -> void:
		log = shared

	func get_current_target() -> StringName:
		return target

	func is_busy() -> bool:
		return busy

	func clear_history() -> void:
		history_cleared += 1
		log.append("clear_history")


class FakeGameState:
	extends RefCounted
	var log: Array

	func _init(shared: Array) -> void:
		log = shared

	func save_now() -> bool:
		log.append("save_now")
		return true


class FakeNet:
	extends RefCounted
	var log: Array

	func _init(shared: Array) -> void:
		log = shared

	func disconnect_now() -> void:
		log.append("disconnect_now")


class FakeMusic:
	extends RefCounted
	var log: Array
	var fade_s := -1.0

	func _init(shared: Array) -> void:
		log = shared

	func stop_music(fade := 0.0) -> void:
		fade_s = fade
		log.append("stop_music")


class FakePackLoader:
	extends RefCounted
	var log: Array

	func _init(shared: Array) -> void:
		log = shared

	func remount_for_soft_restart() -> Dictionary:
		log.append("remount")
		return {"loaded": ["cosmetics"]}


class FakeRegistry:
	extends RefCounted
	var log: Array

	func _init(shared: Array) -> void:
		log = shared

	func reload() -> void:
		log.append("registry_reload")


## UpdateService-Double für die Glue (nur die Signale zählen).
class FakeUpdateService:
	extends Node
	signal check_started
	signal check_completed(result: int, details: Dictionary)

	func check_for_updates() -> void:
		check_started.emit()


func test_gates_verweigern_ohne_seiteneffekte() -> void:
	var restart := _restart_mit_fakes()
	var social := restart.social as FakeSocial
	var router := restart.router as FakeRouter
	assert_eq(restart.blocked_reason(), "", "frei: Wohnzimmer, nichts aktiv")
	social.visit.active = true
	assert_eq(restart.blocked_reason(), "besuch", "Besuch aktiv → verweigert")
	var report: Dictionary = await restart.run()
	assert_false(bool(report["ok"]), "run() bei Besuch: ok=false")
	assert_eq(str(report["refused"]), "besuch", "run() nennt den Grund")
	assert_eq((restart.game_state as FakeGameState).log, [], "KEIN Dienst wurde angefasst")
	assert_eq(router.history_cleared, 0, "Router unangetastet")
	social.visit.active = false
	social.chess.active = true
	assert_eq(restart.blocked_reason(), "brettspiel", "Schach-Partie → verweigert")
	social.chess.active = false
	social.board.active = true
	assert_eq(restart.blocked_reason(), "brettspiel", "Schiffe-versenken-Partie → verweigert")
	social.board.active = false
	router.target = &"mg_host"
	assert_eq(restart.blocked_reason(), "minigame", "Minigame läuft → verweigert")
	router.target = &"mg_pregame"
	assert_eq(restart.blocked_reason(), "minigame", "Pregame zählt als Minigame")
	router.target = &"home/living"
	router.busy = true
	assert_eq(restart.blocked_reason(), "reise", "laufende Router-Reise → verweigert")
	restart.free()


func test_flush_reihenfolge_als_protokoll() -> void:
	var restart := _restart_mit_fakes()
	var log: Array = (restart.game_state as FakeGameState).log
	var states: Array[int] = []
	restart.state_changed.connect(func(state: int) -> void: states.append(state))
	var report: Dictionary = await restart.run()
	assert_true(bool(report["ok"]), "Soft-Restart läuft durch")
	assert_eq(
		log,
		[
			"save_now",
			"disconnect_now",
			"stop_music",
			"wait:0.6",
			"remount",
			"registry_reload",
			"clear_history",
			"reboot",
		],
		"FROZEN Flush-Reihenfolge (Doc B §2.4): Save → Netz → Fade → Remount → Reboot"
	)
	assert_eq(
		report["protocol"],
		[
			"GameState.save_now",
			"Net.disconnect_now",
			"Music.stop_music",
			"wait:0.6",
			"PackLoader.remount_for_soft_restart",
			"ContentRegistry.reload",
			"SceneRouter.clear_history",
			"reboot",
		],
		"internes Protokoll deckungsgleich"
	)
	assert_almost((restart.music as FakeMusic).fade_s, SoftRestart.FADE_S, 1e-6, "Fade-Dauer")
	assert_eq((restart.router as FakeRouter).history_cleared, 1, "History genau 1× geleert")
	assert_eq(
		states,
		[
			SoftRestart.State.SAVING,
			SoftRestart.State.DISCONNECTING,
			SoftRestart.State.FADING,
			SoftRestart.State.REMOUNTING,
			SoftRestart.State.REBOOTING,
			SoftRestart.State.DONE,
		],
		"Statemaschine in fester Folge"
	)
	restart.free()


func test_needs_soft_restart_nur_bei_pck() -> void:
	assert_false(
		SettingsUpdateGlue.needs_soft_restart({"updated": []}), "nichts installiert → kein Knopf"
	)
	assert_false(
		SettingsUpdateGlue.needs_soft_restart({"updated": [{"id": "config", "version": "1.0.1"}]}),
		"config wirkt sofort → kein Knopf"
	)
	assert_true(
		(
			SettingsUpdateGlue
			. needs_soft_restart(
				{
					"updated":
					[{"id": "config", "version": "1.0.1"}, {"id": "cosmetics", "version": "1.4.0"}],
				}
			)
		),
		"mindestens ein PCK → Knopf"
	)


func test_panel_knopf_nur_nach_installiertem_update() -> void:
	var setup := _glue_setup()
	var service := setup["service"] as FakeUpdateService
	service.check_completed.emit(UpdateService.Result.UP_TO_DATE, _details([]))
	assert_eq(_restart_button(setup), null, "UP_TO_DATE → kein Knopf")
	service.check_completed.emit(
		UpdateService.Result.UPDATED, _details([{"id": "config", "version": "1.0.1"}])
	)
	assert_eq(_restart_button(setup), null, "config-only-Update → kein Knopf (wirkt sofort)")
	service.check_completed.emit(
		UpdateService.Result.UPDATED, _details([{"id": "cosmetics", "version": "1.4.0"}])
	)
	var btn := _restart_button(setup)
	assert_ne(btn, null, "installiertes PCK-Update → Knopf ist da")
	if btn != null:
		assert_eq(btn.text, I18nService.t("updates.jetzt_neu_laden"), "deutscher Knopf-Text")
	service.check_completed.emit(
		UpdateService.Result.UPDATED, _details([{"id": "cosmetics", "version": "1.4.1"}])
	)
	var rows := setup["rows"] as VBoxContainer
	var anzahl := 0
	for child in rows.get_children():
		if String(child.name).begins_with("SoftRestartButton"):
			anzahl += 1
	assert_eq(anzahl, 1, "zweiter Check dupliziert den Knopf nicht")
	_glue_teardown(setup)


func test_panel_knopf_unterdrueckt_bei_aktivem_gate() -> void:
	var setup := _glue_setup()
	var glue := setup["glue"] as SettingsUpdateGlue
	(glue.soft_restart.social as FakeSocial).visit.active = true
	(setup["service"] as FakeUpdateService).check_completed.emit(
		UpdateService.Result.UPDATED, _details([{"id": "cosmetics", "version": "1.4.0"}])
	)
	assert_eq(_restart_button(setup), null, "Besuch aktiv → Knopf wird gar nicht angeboten")
	_glue_teardown(setup)


func test_knopf_dialog_bestaetigen_und_abbrechen() -> void:
	var setup := _glue_setup()
	var glue := setup["glue"] as SettingsUpdateGlue
	var screen := setup["screen"] as Control
	var log: Array = setup["log"]
	(setup["service"] as FakeUpdateService).check_completed.emit(
		UpdateService.Result.UPDATED, _details([{"id": "cosmetics", "version": "1.4.0"}])
	)
	var btn := _restart_button(setup)
	assert_ne(btn, null, "Knopf vorhanden")
	# --- Abbrechen: Dialog kommt, „Später“ schließt, NICHTS läuft.
	btn.pressed.emit()
	var dialog := screen.get_node_or_null("SoftRestartConfirm")
	assert_ne(dialog, null, "Bestätigungs-Dialog offen (Reduced-Surprise)")
	var body := dialog.find_child("Body", true, false) as Label
	assert_ne(body, null, "Dialog-Text vorhanden")
	if body != null:
		assert_eq(body.text, I18nService.t("updates.neu_laden_text"), "„Dauert nur einen Hoppler!“")
	(dialog.find_child("CancelButton", true, false) as Button).pressed.emit()
	dialog.free()
	assert_eq(log, [], "Abbrechen: kein Dienst angefasst")
	# --- Bestätigen: Soft-Restart läuft komplett durch (Zeit injiziert).
	btn.pressed.emit()
	dialog = screen.get_node_or_null("SoftRestartConfirm")
	assert_ne(dialog, null, "Dialog erneut offen")
	(dialog.find_child("ConfirmButton", true, false) as Button).pressed.emit()
	dialog.free()
	var fertig := await wait_until(func() -> bool: return log.size() >= 8)
	assert_true(fertig, "Soft-Restart nach Bestätigung durchgelaufen")
	assert_eq(str(log[0]), "save_now", "Lauf beginnt mit Save-Flush")
	assert_eq(str(log[log.size() - 1]), "reboot", "Lauf endet im Reboot")
	# --- Gate-Race: Besuch trifft NACH dem Knopf-Angebot ein → Toast statt Lauf.
	(glue.soft_restart.social as FakeSocial).visit.active = true
	btn.pressed.emit()
	assert_eq(screen.get_node_or_null("SoftRestartConfirm"), null, "kein Dialog bei Besuch")
	var toasts: Array = setup["toasts"]
	assert_true(
		toasts.has(I18nService.t("updates.neu_laden_besuch")), "Verweigerungs-Toast (Besuch)"
	)
	_glue_teardown(setup)


## ------------------------------------------------------------------ Helfer


## SoftRestart mit komplettem Fake-Satz + injizierter Zeit (kein echtes Warten).
func _restart_mit_fakes(shared_log: Array = []) -> SoftRestart:
	var restart := SoftRestart.new()
	restart.game_state = FakeGameState.new(shared_log)
	restart.net = FakeNet.new(shared_log)
	restart.music = FakeMusic.new(shared_log)
	restart.pack_loader = FakePackLoader.new(shared_log)
	restart.registry = FakeRegistry.new(shared_log)
	restart.router = FakeRouter.new(shared_log)
	restart.social = FakeSocial.new()
	restart.wait_fn = func(seconds: float) -> void: shared_log.append("wait:%.1f" % seconds)
	restart.reboot_fn = func() -> void: shared_log.append("reboot")
	return restart


## Glue + Fake-Screen (SectionUpdates/Rows) + Fake-Service + Fake-SoftRestart.
func _glue_setup() -> Dictionary:
	var screen := Control.new()
	screen.name = "FakeSettings"
	var section := PanelContainer.new()
	section.name = "SectionUpdates"
	screen.add_child(section)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	section.add_child(rows)
	var service := FakeUpdateService.new()
	var glue := SettingsUpdateGlue.new()
	var log: Array = []
	glue.soft_restart = _restart_mit_fakes(log)
	glue.add_child(glue.soft_restart)
	var toasts: Array = []
	glue.toast_sink = func(text: String) -> void: toasts.append(text)
	glue.attach(screen, service)
	return {
		"screen": screen,
		"rows": rows,
		"service": service,
		"glue": glue,
		"log": log,
		"toasts": toasts,
	}


func _restart_button(setup: Dictionary) -> Button:
	return (setup["rows"] as VBoxContainer).get_node_or_null("SoftRestartButton") as Button


func _glue_teardown(setup: Dictionary) -> void:
	(setup["glue"] as Node).free()
	(setup["service"] as Node).free()
	(setup["screen"] as Node).free()


func _details(updated: Array) -> Dictionary:
	return {
		"updated": updated,
		"gated": [],
		"native_update": false,
		"latest_native": "",
		"errors": [],
		"notes_de": "",
	}

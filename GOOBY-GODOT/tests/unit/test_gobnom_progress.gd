extends TestCase
## GOB-NOM-Fortschritts-Slice (GameState-Slice "gobnom", Muster GvzProgress):
## Default/Normalize-Roundtrip (Self-Heal), Zwei-Track-Schlüssel (c/n),
## Sieg-Verbuchung (Sterne/Best/Cleared monoton), Freischalt-Logik und
## Score-Formel — alles über ein GameState-Double (Duck-Typing).


class GameStateDouble:
	extends RefCounted
	var state := {}
	var notified: Array = []

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cursor: Variant = state
		for part in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(part):
				cursor = cursor[part]
			else:
				return fallback
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(slice_id: String) -> void:
		notified.append(slice_id)


func _balance() -> Dictionary:
	return GobnomData.load_balance(null)


func test_default_and_normalize_roundtrip() -> void:
	var fresh := GobnomProgress.default_slice()
	assert_eq(GobnomProgress.normalize_slice(fresh), fresh, "Default überlebt normalize")
	var healed := GobnomProgress.normalize_slice("kaputt")
	assert_eq(int(healed["v"]), 1, "Nicht-Dictionary → Default")
	var broken := {"v": "x", "stars": [], "best": {"c1": 120}, "cleared": null}
	var fixed := GobnomProgress.normalize_slice(broken)
	assert_eq(int(fixed["v"]), 1, "v repariert")
	assert_true(fixed["stars"] is Dictionary, "stars-Typ repariert")
	assert_eq(int((fixed["best"] as Dictionary).get("c1", 0)), 120, "gültige Daten VERBATIM")


func test_level_keys_split_tracks() -> void:
	assert_eq(GobnomProgress.level_key(GobnomProgress.TRACK_CAMPAIGN, 3), "c3")
	assert_eq(GobnomProgress.level_key(GobnomProgress.TRACK_COOP, 3), "n3")
	assert_eq(GobnomProgress.level_count(GobnomProgress.TRACK_CAMPAIGN), 15)
	assert_eq(GobnomProgress.level_count(GobnomProgress.TRACK_COOP), 10)


func test_record_win_books_and_stays_monotone() -> void:
	var gs := GameStateDouble.new()
	var track := GobnomProgress.TRACK_CAMPAIGN
	var first := GobnomProgress.record_win(gs, track, 1, 2, 100)
	assert_true(bool(first["first_clear"]), "erster Sieg = First Clear")
	assert_true(bool(first["new_best"]), "erster Score = Bestwert")
	assert_eq(GobnomProgress.level_stars(gs, track, 1), 2, "Sterne gebucht")
	assert_true(GobnomProgress.is_cleared(gs, track, 1), "cleared gebucht")
	assert_eq(gs.notified, ["gobnom"], "Slice-Änderung gemeldet")
	var worse := GobnomProgress.record_win(gs, track, 1, 1, 40)
	assert_false(bool(worse["first_clear"]), "kein zweiter First Clear")
	assert_false(bool(worse["new_best"]), "schlechterer Score ist kein Bestwert")
	assert_eq(GobnomProgress.level_stars(gs, track, 1), 2, "Sterne bleiben monoton")
	var better := GobnomProgress.record_win(gs, track, 1, 3, 200)
	assert_true(bool(better["new_best"]), "besserer Score zählt")
	assert_eq(GobnomProgress.level_stars(gs, track, 1), 3, "Sterne wachsen")


func test_tracks_do_not_leak_into_each_other() -> void:
	var gs := GameStateDouble.new()
	GobnomProgress.record_win(gs, GobnomProgress.TRACK_CAMPAIGN, 1, 3, 100)
	assert_false(
		GobnomProgress.is_cleared(gs, GobnomProgress.TRACK_COOP, 1),
		"Kampagnen-Sieg schaltet kein Coop-Level frei"
	)
	assert_eq(GobnomProgress.total_stars(gs, GobnomProgress.TRACK_COOP), 0, "Coop-Sterne 0")


func test_unlock_and_cleared_count() -> void:
	var gs := GameStateDouble.new()
	var track := GobnomProgress.TRACK_COOP
	assert_eq(GobnomProgress.max_unlocked(gs, track), 1, "CN1 immer offen")
	for id in range(1, 11):
		GobnomProgress.record_win(gs, track, id, 1, 50)
	assert_eq(GobnomProgress.max_unlocked(gs, track), 10, "Deckel bei Vollabschluss")
	assert_eq(GobnomProgress.cleared_count(gs, track), 10, "cleared_count zählt WIRKLICH")


func test_final_score_formula() -> void:
	var balance := _balance()
	var score: Dictionary = balance["score"]
	var want := (
		int(score["win_base"])
		+ 3 * int(score["jar_bonus"])
		+ 5 * int(score["level_bonus"])
		+ int(score["first_clear_bonus"])
	)
	assert_eq(GobnomProgress.final_score(5, 3, true, balance), want, "Formel wie Balance")
	assert_eq(
		GobnomProgress.final_score(5, 3, false, balance),
		want - int(score["first_clear_bonus"]),
		"ohne First Clear fehlt nur der Bonus"
	)


func test_null_gamestate_is_safe() -> void:
	assert_eq(GobnomProgress.level_stars(null, "campaign", 1), 0)
	assert_false(GobnomProgress.is_cleared(null, "campaign", 1))
	assert_eq(GobnomProgress.max_unlocked(null, "campaign"), 1)
	var booking := GobnomProgress.record_win(null, "campaign", 1, 3, 100)
	assert_true(bool(booking["first_clear"]), "Host-loser Lauf liefert das Ergebnis-Dict")

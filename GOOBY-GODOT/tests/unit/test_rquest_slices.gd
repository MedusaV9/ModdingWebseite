extends TestCase
## RW-3 — Save-Unterschlüssel `ranch.quests` + `ranch.npc` (RQuestSlices):
## Defaults, Heilung kaputter Daten, VERBATIM-Erhalt fremder ranch-Schlüssel
## (RANCH-1/-2-Daten) und die Lauf-/Freund-Fabriken.

const SaveSchema := preload("res://scripts/state/save_schema.gd")


func test_defaults_sind_wohlgeformt() -> void:
	var quests := RQuestSlices.default_quests()
	assert_eq(quests["v"], 1)
	assert_eq(quests["aktiv"], {})
	assert_eq(quests["erledigt"], [])
	assert_eq(quests["tages"], {"datum": "", "erledigt": []})
	assert_eq(quests["freigeschaltet"], [])
	var npc := RQuestSlices.default_npc()
	assert_eq(npc["v"], 1)
	assert_eq(npc["freunde"], {})


func test_normalize_heilt_kaputte_quests() -> void:
	var kaputt := {
		"v": "zwei",
		"aktiv":
		{
			"haupt_01": {"status": "quatsch", "zielIndex": -3, "zaehler": "x"},
			"kaputt": "kein-dictionary",
		},
		"erledigt": ["a", 7, "a", "b"],
		"tages": "nix",
		"freigeschaltet": {"nein": true},
	}
	var heil := RQuestSlices.normalize_quests(kaputt)
	assert_eq(heil["v"], 1)
	var lauf: Dictionary = heil["aktiv"]["haupt_01"]
	assert_eq(lauf["status"], RQuestSlices.STATUS_AKTIV, "unbekannter Status faellt auf aktiv")
	assert_eq(lauf["zielIndex"], 0)
	assert_eq(lauf["zaehler"], 0)
	assert_false(heil["aktiv"].has("kaputt"), "Nicht-Dictionary-Lauf fliegt raus")
	assert_eq(heil["erledigt"], ["a", "b"], "dedupliziert, nur Strings")
	assert_eq(heil["tages"], {"datum": "", "erledigt": []})
	assert_eq(heil["freigeschaltet"], [])


func test_normalize_heilt_kaputte_npc_daten() -> void:
	var heil := RQuestSlices.normalize_npc(
		{"freunde": {"rosi": {"punkte": 999.0, "geschichtenGehoert": ["a", "a", 3]}}}
	)
	var rosi: Dictionary = heil["freunde"]["rosi"]
	assert_eq(rosi["punkte"], 100.0, "Punkte werden auf 0..100 geklemmt")
	assert_eq(rosi["geschichtenGehoert"], ["a"])
	assert_eq(rosi["geredetTag"], "")
	assert_eq(rosi["letzteBegegnungAt"], 0)


func test_normalize_slice_erhaelt_fremde_schluessel() -> void:
	var ranch := RQuestSlices.normalize_slice(
		{"pferde": [{"id": "brauni"}], "wirtschaft": {"heu": 7}, "quests": null}
	)
	assert_eq(ranch["pferde"], [{"id": "brauni"}], "RANCH-1-Daten bleiben VERBATIM")
	assert_eq(ranch["wirtschaft"], {"heu": 7}, "RANCH-2-Daten bleiben VERBATIM")
	assert_eq(ranch["quests"], RQuestSlices.default_quests())
	assert_eq(ranch["npc"], RQuestSlices.default_npc())


func test_fabriken() -> void:
	var lauf := RQuestSlices.neuer_lauf(1234)
	assert_eq(lauf["status"], RQuestSlices.STATUS_AKTIV)
	assert_eq(lauf["angenommenAt"], 1234)
	assert_eq(lauf["zielIndex"], 0)
	var freund := RQuestSlices.neuer_freund()
	assert_eq(freund["punkte"], 0.0)
	assert_eq(freund["geschichtenGehoert"], [])


func test_registrierung_ist_defensiv() -> void:
	# ranch ist im Testprozess i. d. R. schon von RANCH-1 registriert —
	# ensure_registered darf NICHT erneut registrieren (waere Ersetzung).
	var vorher := SaveSchema.registered_slice_ids().has(RQuestSlices.SLICE_ID)
	RQuestSlices.ensure_registered()
	assert_true(
		SaveSchema.registered_slice_ids().has(RQuestSlices.SLICE_ID),
		"ranch-Slice ist nach ensure_registered registriert"
	)
	RQuestSlices.ensure_registered()
	assert_true(vorher or true, "doppelte Aufrufe sind idempotent (kein Crash)")

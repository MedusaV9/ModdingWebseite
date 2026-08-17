extends TestCase
## FIX-4: CutsceneLib — die fünf Pflicht-Cutscenes existieren, validieren
## sauber, alle Caption-/Titel-Keys haben DE- UND EN-Strings, referenzierte
## Sounds/Tracks existieren (User-Meldung 3: „Die kompletten Cutscenes fehlen").


func test_pflicht_cutscenes_vorhanden() -> void:
	CutsceneLib.reset_cache()
	var ids := CutsceneLib.ids()
	for id: String in CutsceneLib.REQUIRED_IDS:
		assert_true(ids.has(id), "Pflicht-Cutscene fehlt: %s" % id)


func test_alle_cutscenes_validieren() -> void:
	for id: String in CutsceneLib.ids():
		var errors := CutsceneLib.validate(CutsceneLib.get_cutscene(id))
		assert_eq(errors.size(), 0, "%s: %s" % [id, "; ".join(errors)])


func test_caption_und_titel_keys_haben_de_und_en() -> void:
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for id: String in CutsceneLib.ids():
		var def := CutsceneLib.get_cutscene(id)
		var keys := CutsceneLib.caption_keys(def)
		var title_key := str(def.get("title_key", ""))
		if not title_key.is_empty():
			keys.append(title_key)
		for key: String in keys:
			assert_true(de.has(key), "DE-String fehlt: %s (%s)" % [key, id])
			assert_true(en.has(key), "EN-String fehlt: %s (%s)" % [key, id])


func test_referenzierte_sfx_und_musik_existieren() -> void:
	for id: String in CutsceneLib.ids():
		_check_steps(CutsceneLib.get_cutscene(id).get("steps", []), id)


func _check_steps(steps: Variant, ctx: String) -> void:
	if not (steps is Array):
		return
	for step: Variant in steps:
		if not (step is Dictionary):
			continue
		var row: Dictionary = step
		match str(row.get("op", "")):
			"sfx":
				var sfx_id := str(row.get("id", ""))
				assert_true(SfxMap.SOUNDS.has(sfx_id), "%s: unbekannte sfx-Id '%s'" % [ctx, sfx_id])
			"music":
				if row.has("track"):
					assert_true(
						MusicRegistry.TRACKS.has(str(row["track"])),
						"%s: unbekannter Track '%s'" % [ctx, row["track"]]
					)
				if row.has("context"):
					assert_false(
						MusicRegistry.track_for(str(row["context"])).is_empty(),
						"%s: Kontext ohne Musik '%s'" % [ctx, row["context"]]
					)
			"stinger":
				assert_true(
					MusicRegistry.is_stinger(str(row.get("track", ""))),
					"%s: stinger '%s' ist keiner" % [ctx, row.get("track")]
				)
		_check_steps(row.get("steps"), ctx)


func test_validate_meldet_kaputte_skripte() -> void:
	assert_true(CutsceneLib.validate({}).size() > 0, "Leeres Skript muss Fehler melden.")
	var kaputt := {
		"id": "x",
		"steps": [{"op": "gibtEsNicht"}, {"op": "camera", "move": "warp"}, {"op": "caption"}],
	}
	var errors := CutsceneLib.validate(kaputt)
	assert_true(errors.size() >= 3, "Unbekannter op, Move + fehlendes Feld: %s" % errors)

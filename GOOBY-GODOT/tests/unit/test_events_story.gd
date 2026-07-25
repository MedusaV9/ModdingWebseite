extends TestCase
## W3d — Geschichten-Stunde M1: Lücken-Logik (pure) + Daten-Validierung der
## zwei Pack-Geschichten (content/events/data/stories.json).

const STORIES_JSON := "res://content/events/data/stories.json"


func _stories() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORIES_JSON))
	assert_true(parsed is Dictionary, "stories.json parst")
	return parsed.get("items", []) if parsed is Dictionary else []


func _beispiel() -> Dictionary:
	return {
		"id": "test",
		"titel_de": "Test",
		"saetze_de": ["Gooby mag {0}.", "Er träumt von {1} und {2}."],
		"luecken": ["moehre", "nutella", "wolke"],
		"woerter_de":
		[
			{"id": "moehre", "text": "Möhre"},
			{"id": "nutella", "text": "Nutella"},
			{"id": "wolke", "text": "Wolke"},
			{"id": "socke", "text": "Socke"},
		],
	}


func test_stories_json_daten() -> void:
	var stories := _stories()
	assert_eq(stories.size(), 2, "2 Geschichten (M1)")
	var seen := {}
	for story: Dictionary in stories:
		var id := str(story.get("id", ""))
		seen[id] = true
		assert_false(str(story.get("titel_de", "")).is_empty(), id + ": titel_de")
		var luecken: Array = story.get("luecken", [])
		assert_eq(luecken.size(), 3, id + ": 3 Lücken")
		var woerter: Array = story.get("woerter_de", [])
		assert_eq(woerter.size(), 6, id + ": 6 Wort-Chips")
		var word_ids := {}
		for word: Dictionary in woerter:
			assert_false(str(word.get("text", "")).is_empty(), id + ": Wort-Text")
			word_ids[str(word.get("id", ""))] = true
		assert_eq(word_ids.size(), 6, id + ": Wort-Ids eindeutig")
		for gap: Variant in luecken:
			assert_true(word_ids.has(str(gap)), "%s: Lücke '%s' hat ein Wort" % [id, gap])
		var all_text := "\n".join(PackedStringArray(story.get("saetze_de", [])))
		for i in luecken.size():
			assert_true(all_text.contains("{%d}" % i), "%s: Token {%d} im Text" % [id, i])
		assert_true(int(story.get("entertainment", 0)) > 0, id + ": entertainment-Feld (M2-Marker)")
	assert_eq(seen.size(), 2, "Story-Ids eindeutig")


func test_fills_platzierung() -> void:
	var story := _beispiel()
	var fills := StoryTime.empty_fills(story)
	assert_eq(fills, [null, null, null], "eine Zelle pro Lücke")
	assert_false(StoryTime.is_complete(fills))
	assert_eq(StoryTime.place_word(fills, "socke"), 0, "erste freie Lücke")
	assert_eq(StoryTime.place_word(fills, "nutella"), 1)
	assert_eq(StoryTime.place_word(fills, "wolke"), 2)
	assert_true(StoryTime.is_complete(fills))
	assert_eq(StoryTime.place_word(fills, "moehre"), -1, "voll → -1")
	assert_false(StoryTime.is_complete([]), "leer ist nie komplett")


func test_korrektheit_und_wrong_count() -> void:
	var story := _beispiel()
	assert_true(StoryTime.is_correct(story, 0, "moehre"))
	assert_false(StoryTime.is_correct(story, 0, "socke"))
	assert_false(StoryTime.is_correct(story, 9, "moehre"), "Index out of range")
	# Falsche Wörter sind ERLAUBT (lustigere Geschichte) — nur gezählt.
	assert_eq(StoryTime.wrong_count(story, ["moehre", "nutella", "wolke"]), 0)
	assert_eq(StoryTime.wrong_count(story, ["socke", "nutella", "moehre"]), 2)
	assert_eq(StoryTime.wrong_count(story, ["socke", null, null]), 1, "offene zählen nicht")


func test_rendered_sentences() -> void:
	var story := _beispiel()
	var leer := StoryTime.rendered_sentences(story, [null, null, null])
	assert_eq(leer[0], "Gooby mag ____.", "leere Lücke = Platzhalter")
	assert_eq(leer[1], "Er träumt von ____ und ____.")
	var voll := StoryTime.rendered_sentences(story, ["moehre", "nutella", "socke"])
	assert_eq(voll[0], "Gooby mag Möhre.", "Wort-Text eingesetzt")
	assert_eq(voll[1], "Er träumt von Nutella und Socke.")

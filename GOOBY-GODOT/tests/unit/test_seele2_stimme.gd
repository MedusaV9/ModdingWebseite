extends TestCase
## SEELE-2: Stimme mit Gefühl (GoobyVoice + SoulMood.stimme). Kern-
## versprechen: man HÖRT, wie es Gooby geht — Tonhöhe, Tempo und Länge des
## Gebrabbels folgen der durchgehenden Stimmung, die Moment-Emotion bleibt
## als Grundton erhalten, und gekürzt wird nie unter MIN_SILBEN.


func test_modulation_folgt_der_stimmung() -> void:
	var elend := GoobyVoice.modulation(5.0, "neutral")
	var selig := GoobyVoice.modulation(95.0, "neutral")
	assert_true(
		float(elend["pitch"]) < float(selig["pitch"]),
		"elend klingt tiefer (%f vs %f)" % [elend["pitch"], selig["pitch"]]
	)
	assert_true(float(elend["tempo"]) < float(selig["tempo"]), "elend brabbelt langsamer")
	assert_true(float(elend["laenge"]) < float(selig["laenge"]), "elend ist wortkarger")


func test_emotion_bleibt_grundton() -> void:
	var traurig := GoobyVoice.modulation(50.0, "sad")
	var froh := GoobyVoice.modulation(50.0, "happy")
	assert_true(
		float(traurig["pitch"]) < float(froh["pitch"]),
		"sad bleibt tiefer als happy (gleiche Laune)"
	)
	assert_true(
		float(traurig["tempo"]) < float(froh["tempo"]), "sad bleibt gedehnt (Tempo-Dämpfer)"
	)


func test_kuerze_plan_respektiert_laenge_und_minimum() -> void:
	var plan: Array[Dictionary] = []
	for i in 12:
		plan.append({"pause": false, "syllable": i, "seed": i})
		if i == 5:
			plan.append({"pause": true, "syllable": 0, "seed": 0})
	assert_eq(GoobyVoice.kuerze_plan(plan, 1.0).size(), plan.size(), "laenge 1.0 → unverändert")
	var halb := GoobyVoice.kuerze_plan(plan, 0.5)
	assert_eq(_klingend(halb), 6, "laenge 0.5 → 6 von 12 klingenden Silben")
	var mini := GoobyVoice.kuerze_plan(plan, 0.01)
	assert_eq(_klingend(mini), GoobyVoice.MIN_SILBEN, "nie unter MIN_SILBEN — nie stumm")
	# Pausen zählen nicht als Silben, bleiben aber zwischen behaltenen stehen.
	var acht := GoobyVoice.kuerze_plan(plan, 8.0 / 12.0)
	assert_eq(_klingend(acht), 8)
	assert_true(acht.size() >= 9, "Pause nach Silbe 6 bleibt im gekürzten Plan")


func test_gebrabbel_wird_hoerbar_kuerzer_bei_mieser_laune() -> void:
	var voice := GoobyVoice.new()
	tree.root.add_child(voice)
	await wait_frames(2)
	var text := "Hallo liebes Gooby Zuhause"  # 23 Buchstaben
	var selig := await _silben_von(voice, text, 95.0)
	var elend := await _silben_von(voice, text, 5.0)
	assert_true(elend < selig, "miese Laune brabbelt kürzer (%d vs %d Silben)" % [elend, selig])
	assert_true(elend >= GoobyVoice.MIN_SILBEN, "aber nie stumm")
	voice.free()


func test_set_stimmung_klammert() -> void:
	var voice := GoobyVoice.new()
	voice.set_stimmung(250.0)
	assert_almost(voice.stimmung(), 100.0, 1e-6, "Klammer oben")
	voice.set_stimmung(-40.0)
	assert_almost(voice.stimmung(), 0.0, 1e-6, "Klammer unten")
	voice.free()


func _silben_von(voice: GoobyVoice, text: String, stimmung: float) -> int:
	voice.set_stimmung(stimmung)
	var events := {"silben": 0, "fertig": false}
	var on_silbe := func(_i: int, _n: int) -> void: events["silben"] += 1
	var on_fertig := func() -> void: events["fertig"] = true
	voice.silbe.connect(on_silbe)
	voice.fertig.connect(on_fertig)
	voice.sagt(text, "neutral")
	await wait_until(func() -> bool: return events["fertig"], 8000)
	voice.silbe.disconnect(on_silbe)
	voice.fertig.disconnect(on_fertig)
	return int(events["silben"])


func _klingend(plan: Array[Dictionary]) -> int:
	var count := 0
	for step in plan:
		if not step["pause"]:
			count += 1
	return count

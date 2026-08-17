extends TestCase
## FEEL-AC: der Emotions-Katalog (FeelEmotions) — 12 vollständige, klar
## UNTERSCHEIDBARE Pakete. Gesicht nur auf den 8 Vertrags-Shapekeys
## (emotion_*), Extra nur auf vorhandenen Zusatz-Shapekeys, Pose nur auf den
## EMOTION_POSES-Kanälen — der Rig-Vertrag bleibt unangetastet.

const GEWUENSCHT: Array[String] = [
	"schreck",
	"freude",
	"begeisterung",
	"ueberraschung",
	"verlegenheit",
	"trotz",
	"traurigkeit",
	"muedigkeit",
	"neugier",
	"stolz",
	"angst",
	"verliebtheit",
]
## Paarweiser Mindestabstand der Merkmals-Vektoren (Gesicht+Extra+Pose):
## darunter wären zwei Emotionen auf dem Handy nicht mehr unterscheidbar.
const MIN_ABSTAND := 0.35


func test_alle_zwoelf_emotionen_vorhanden() -> void:
	assert_eq(FeelEmotions.alle().size(), 12, "genau 12 Emotionen")
	for id in GEWUENSCHT:
		assert_true(FeelEmotions.kennt(id), "Emotion fehlt: %s" % id)
	assert_eq(FeelEmotions.alle()[0], "schreck", "Schreck ist ausdrücklich gewünscht → zuerst")


func test_defs_sind_vollstaendig() -> void:
	for id in FeelEmotions.alle():
		var def := FeelEmotions.def_of(id)
		for feld in ["gesicht", "extra", "pose", "bewegung", "symbol", "sfx", "dauer_s"]:
			assert_true(def.has(feld), "%s: Feld %s fehlt" % [id, feld])
		assert_true(FeelEmotions.dauer_s(id) >= 2.0, "%s: lesbare Dauer (≥2 s)" % id)
		assert_true(FeelEmotions.dauer_s(id) <= 5.0, "%s: nicht endlos (≤5 s)" % id)
		assert_false(str(def["symbol"]).is_empty(), "%s: Emote-Symbol Pflicht" % id)
		assert_false(str(def["bewegung"]).is_empty(), "%s: Bewegungs-Beat Pflicht" % id)
		assert_true(FeelEmotions.farbe(id).a > 0.0, "%s: Akzentfarbe gesetzt" % id)


func test_gesicht_nutzt_nur_vertrags_shapekeys() -> void:
	for id in FeelEmotions.alle():
		var def := FeelEmotions.def_of(id)
		for kanal: String in def["gesicht"]:
			assert_true(
				GoobyRig.EMOTIONS.has(kanal), "%s: unbekannter Gesichts-Kanal %s" % [id, kanal]
			)
		for kanal: String in def["extra"]:
			assert_true(
				FeelEmotions.EXTRA_KANAELE.has(kanal),
				"%s: unbekannter Extra-Kanal %s" % [id, kanal]
			)
		for kanal: String in def["pose"]:
			assert_true(
				FeelEmotions.POSE_KANAELE.has(kanal), "%s: unbekannter Pose-Kanal %s" % [id, kanal]
			)


func test_alle_emotionen_sind_paarweise_unterscheidbar() -> void:
	var ids := FeelEmotions.alle()
	for i in range(ids.size()):
		var a := FeelEmotions.merkmale(ids[i])
		assert_true(a.size() > 0, "%s: Merkmals-Vektor leer" % ids[i])
		for j in range(i + 1, ids.size()):
			var b := FeelEmotions.merkmale(ids[j])
			var dist := 0.0
			for k in range(a.size()):
				dist += absf(a[k] - b[k])
			assert_true(
				dist >= MIN_ABSTAND, "%s und %s zu ähnlich (Abstand %.2f)" % [ids[i], ids[j], dist]
			)


func test_symbole_existieren_als_svg() -> void:
	var gesehen := {}
	for id in FeelEmotions.alle():
		var symbol := str(FeelEmotions.def_of(id)["symbol"])
		var pfad := FeelEmotions.symbol_pfad(symbol)
		assert_true(ResourceLoader.exists(pfad), "%s: Symbol fehlt (%s)" % [id, pfad])
		gesehen[symbol] = true
	assert_eq(gesehen.size(), 12, "jede Emotion hat ihr EIGENES Symbol")


func test_starke_emotionen_sind_sparsam() -> void:
	var starke := 0
	for id in FeelEmotions.alle():
		if FeelEmotions.ist_stark(id):
			starke += 1
	assert_true(starke >= 2 and starke <= 5, "Regie sparsam: 2–5 starke (ist %d)" % starke)
	assert_true(FeelEmotions.ist_stark("schreck"), "Schreck ist ein Regie-Moment")


func test_stimm_emotion_liefert_rig_ids() -> void:
	for id in FeelEmotions.alle():
		var stimme := FeelEmotions.stimm_emotion(id)
		assert_true(GoobyRig.EMOTIONS.has(stimme), "%s: Stimm-Emotion %s" % [id, stimme])
	assert_eq(FeelEmotions.stimm_emotion("schreck"), "scared", "Schreck klingt erschrocken")
	assert_eq(FeelEmotions.stimm_emotion("traurigkeit"), "sad", "Traurigkeit klingt traurig")

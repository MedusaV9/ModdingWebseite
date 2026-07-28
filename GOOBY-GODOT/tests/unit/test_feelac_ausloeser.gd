extends TestCase
## FEEL-AC: SoulFeelings — Ereignis→Emotion-Mapping und die Frequenzbremse
## (Mindestabstand, Tagesdeckel, Je-Emotion-Abstand, Tages-Gates). Alles
## PURE mit hereingereichter Zeit — vollständig deterministisch.

const NOW := 1_768_478_400_000
const TAG := "2026-01-15"


func test_ereignisse_mappen_auf_die_richtigen_emotionen() -> void:
	assert_eq(SoulFeelings.emotion_fuer("donner"), "schreck", "Donner erschreckt")
	assert_eq(SoulFeelings.emotion_fuer("fund"), "ueberraschung", "Fund überrascht")
	assert_eq(SoulFeelings.emotion_fuer("ertappt"), "verlegenheit", "Ertappt = verlegen")
	assert_eq(SoulFeelings.emotion_fuer("rekord"), "stolz", "Rekord macht stolz")
	assert_eq(SoulFeelings.emotion_fuer("lieblingsessen"), "verliebtheit", "Lieblingsessen")
	assert_eq(SoulFeelings.emotion_fuer("dunkelheit"), "angst", "Dunkelheit ängstigt")
	assert_eq(SoulFeelings.emotion_fuer("quatsch"), "", "Unbekanntes bleibt stumm")
	for ereignis: String in SoulFeelings.EREIGNISSE:
		var emotion := SoulFeelings.emotion_fuer(ereignis)
		assert_true(FeelEmotions.kennt(emotion), "%s → unbekannte Emotion %s" % [ereignis, emotion])
		assert_true(SoulFeelings.prio(ereignis) >= 1, "%s: Priorität fehlt" % ereignis)


func test_mindestabstand_bremst_normale_aber_nicht_starke() -> void:
	var feelings := SoulFeelings.buche(SoulFeelings.default_feelings(), "fund", NOW, TAG)
	var kurz_danach := NOW + SoulFeelings.MIN_GAP_MS - 1
	assert_false(SoulFeelings.erlaubt(feelings, "ertappt", kurz_danach, TAG), "prio 2 gebremst")
	assert_true(SoulFeelings.erlaubt(feelings, "donner", kurz_danach, TAG), "prio 3 überstimmt")
	var nach_gap := NOW + SoulFeelings.MIN_GAP_MS + 1
	assert_true(SoulFeelings.erlaubt(feelings, "ertappt", nach_gap, TAG), "nach Gap frei")


func test_dieselbe_emotion_braucht_ihren_eigenen_abstand() -> void:
	var feelings := SoulFeelings.buche(SoulFeelings.default_feelings(), "donner", NOW, TAG)
	var nach_min_gap := NOW + SoulFeelings.MIN_GAP_MS + 1
	assert_false(
		SoulFeelings.erlaubt(feelings, "donner", nach_min_gap, TAG),
		"Schreck auf Schreck nutzt sich ab"
	)
	assert_false(
		SoulFeelings.erlaubt(feelings, "umgefallen", nach_min_gap, TAG),
		"gleiche Emotion über anderes Ereignis auch gebremst"
	)
	var nach_emotion_gap := NOW + SoulFeelings.JE_EMOTION_GAP_MS + 1
	assert_true(SoulFeelings.erlaubt(feelings, "donner", nach_emotion_gap, TAG), "später wieder")


func test_tagesdeckel_und_tageswechsel() -> void:
	var feelings := SoulFeelings.default_feelings()
	var t := NOW
	for i in SoulFeelings.MAX_PRO_TAG:
		var ereignis := "fund" if i % 2 == 0 else "ertappt"
		assert_true(SoulFeelings.erlaubt(feelings, ereignis, t, TAG), "Buchung %d erlaubt" % i)
		feelings = SoulFeelings.buche(feelings, ereignis, t, TAG)
		t += SoulFeelings.JE_EMOTION_GAP_MS + 1
	assert_false(SoulFeelings.erlaubt(feelings, "donner", t, TAG), "Tagesdeckel voll")
	assert_true(
		SoulFeelings.erlaubt(feelings, "donner", t, "2026-01-16"), "neuer Tag = neuer Zähler"
	)
	var morgen := SoulFeelings.buche(feelings, "donner", t, "2026-01-16")
	assert_eq(int(morgen["count"]), 1, "Zähler startet neu")


func test_tages_gates_feuern_hoechstens_einmal_pro_tag() -> void:
	var feelings := SoulFeelings.buche(SoulFeelings.default_feelings(), "dunkelheit", NOW, TAG)
	var viel_spaeter := NOW + 2 * SoulFeelings.JE_EMOTION_GAP_MS
	assert_false(
		SoulFeelings.erlaubt(feelings, "dunkelheit", viel_spaeter, TAG),
		"Dunkelheit nölt nicht die ganze Nacht"
	)
	assert_true(
		SoulFeelings.erlaubt(feelings, "dunkelheit", viel_spaeter, "2026-01-16"),
		"nächste Nacht wieder"
	)


func test_normalize_heilt_kaputte_daten() -> void:
	var kaputt: Variant = {"day": 7, "count": "x", "je": [], "gates": null, "bestMax": -3}
	var heil := SoulFeelings.normalize(kaputt)
	assert_eq(str(heil["day"]), "", "day geheilt")
	assert_eq(int(heil["count"]), 0, "count geheilt")
	assert_true(heil["je"] is Dictionary, "je geheilt")
	assert_true(heil["gates"] is Dictionary, "gates geheilt")
	assert_eq(int(heil["bestMax"]), 0, "bestMax geheilt")
	assert_eq(SoulFeelings.normalize("quatsch")["count"], 0, "Nicht-Dict geheilt")


func test_dunkelheit_und_muedigkeit_erkennung() -> void:
	assert_true(SoulFeelings.ist_dunkel(23), "23 Uhr dunkel")
	assert_true(SoulFeelings.ist_dunkel(2), "2 Uhr dunkel")
	assert_false(SoulFeelings.ist_dunkel(12), "mittags hell")
	assert_false(SoulFeelings.ist_dunkel(21), "21 Uhr noch Abend")
	assert_true(SoulFeelings.ist_muede({"energy": 10.0}), "Energie 10 = müde")
	assert_false(SoulFeelings.ist_muede({"energy": 80.0}), "Energie 80 = wach")
	assert_false(SoulFeelings.ist_muede({}), "fehlende Stats = wach (nie nörgeln)")


func test_rekord_max_ueber_alle_boards() -> void:
	var state := {
		"minigames":
		{
			"legacy":
			{
				"best": {"gap": 12, "runner": 30},
				"endlessBest": {"gap": 44},
				"bestByDiff": {"golf": {"normal": 51, "schwer": 9}},
			}
		}
	}
	assert_eq(SoulFeelings.rekord_max(state), 51, "höchster Wert über alle Boards")
	assert_eq(SoulFeelings.rekord_max({}), 0, "leerer State = 0")


func test_lieblingsessen_regel() -> void:
	assert_true(
		SoulFeelings.ist_lieblingsessen({"apple": 3, "cake": 1}, "apple", 3), "3× + meistgegeben"
	)
	assert_false(SoulFeelings.ist_lieblingsessen({"apple": 2}, "apple", 3), "zu selten")
	assert_false(
		SoulFeelings.ist_lieblingsessen({"apple": 3, "cake": 5}, "apple", 3), "nicht das liebste"
	)


func test_donner_intervall_ist_deterministisch_und_begrenzt() -> void:
	assert_almost(SoulFeelings.donner_intervall_s(0.0), SoulFeelings.DONNER_MIN_S, 1e-4, "min")
	assert_almost(SoulFeelings.donner_intervall_s(1.0), SoulFeelings.DONNER_MAX_S, 1e-4, "max")
	assert_almost(
		SoulFeelings.donner_intervall_s(0.5),
		(SoulFeelings.DONNER_MIN_S + SoulFeelings.DONNER_MAX_S) / 2.0,
		1e-4,
		"mitte"
	)
	assert_almost(
		SoulFeelings.donner_intervall_s(0.5), SoulFeelings.donner_intervall_s(0.5), 0.0, "stabil"
	)

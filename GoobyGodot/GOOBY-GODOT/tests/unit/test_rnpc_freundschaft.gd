extends TestCase
## RW-3 — Freundschafts-Mathematik (RNpcFreundschaft): Herz-Kurve,
## gebremster Verfall (Karenz, Deckel, Stufen-Boden), Reden-/Geschenk-
## Tageslimits, Quest-Bonus und Freischaltungs-Deltas.

const TAG := RNpcFreundschaft.MS_PRO_TAG

## NPC-Fixture mit Vorlieben + Freischaltungen an Stufe 1/3/5.
const NPC_DEF := {
	"id": "fx_npc",
	"geschenke": {"liebt": ["apfel"], "mag": ["karotte"]},
	"freischaltungen":
	{
		"1": [{"typ": "smalltalk"}],
		"3": [{"typ": "rabatt", "shop": "markt", "prozent": 10}],
		"5": [{"typ": "geschichte", "knoten": "geschichte_2"}],
	},
}


func test_herz_kurve() -> void:
	assert_eq(RNpcFreundschaft.herzen(0.0), 0)
	assert_eq(RNpcFreundschaft.herzen(9.9), 0)
	assert_eq(RNpcFreundschaft.herzen(10.0), 1)
	assert_eq(RNpcFreundschaft.herzen(25.0), 2)
	assert_eq(RNpcFreundschaft.herzen(45.0), 3)
	assert_eq(RNpcFreundschaft.herzen(70.0), 4)
	assert_eq(RNpcFreundschaft.herzen(100.0), 5)
	assert_almost(RNpcFreundschaft.punkte_bis_naechste(7.0), 3.0)
	assert_almost(RNpcFreundschaft.punkte_bis_naechste(100.0), 0.0, 1e-6, "Herz 5 = fertig")


func test_verfall_karenz_und_deckel() -> void:
	var punkte := 30.0
	assert_almost(
		RNpcFreundschaft.punkte_nach_verfall(punkte, TAG, TAG * 7),
		30.0,
		1e-6,
		"innerhalb der Karenz kein Verfall"
	)
	assert_almost(
		RNpcFreundschaft.punkte_nach_verfall(punkte, 0, TAG * 999),
		30.0,
		1e-6,
		"ohne Begegnungs-Stempel kein Verfall"
	)
	var nach_10 := RNpcFreundschaft.punkte_nach_verfall(punkte, TAG, TAG * 11)
	assert_almost(nach_10, 27.0, 1e-6, "3 Tage ueber der Karenz = -3")
	var nach_100 := RNpcFreundschaft.punkte_nach_verfall(punkte, TAG, TAG * 101)
	assert_almost(nach_100, 25.0, 1e-6, "Deckel greift NICHT unter den Stufen-Boden (Herz 2 = 25)")


func test_verfall_faellt_nie_unter_die_erreichte_stufe() -> void:
	# 46 Punkte = Herz 3 (Schwelle 45). Selbst nach ewiger Abwesenheit
	# bleibt der Boden bei 45 — Freischaltungen gehen nie verloren.
	var nach := RNpcFreundschaft.punkte_nach_verfall(46.0, TAG, TAG * 400)
	assert_almost(nach, 45.0, 1e-6)
	assert_eq(RNpcFreundschaft.herzen(nach), 3, "Herz-Stufe bleibt erhalten")


func test_reden_tageslimit() -> void:
	var freund := RQuestSlices.neuer_freund()
	freund = RNpcFreundschaft.reden(freund, "2026-07-26", 1000)
	assert_almost(float(freund["punkte"]), RNpcFreundschaft.REDEN_PUNKTE)
	freund = RNpcFreundschaft.reden(freund, "2026-07-26", 2000)
	assert_almost(
		float(freund["punkte"]),
		RNpcFreundschaft.REDEN_PUNKTE + RNpcFreundschaft.REDEN_TROST,
		1e-6,
		"zweites Gespraech am Tag gibt nur Trostpunkte"
	)
	freund = RNpcFreundschaft.reden(freund, "2026-07-27", 3000)
	assert_almost(
		float(freund["punkte"]),
		RNpcFreundschaft.REDEN_PUNKTE * 2.0 + RNpcFreundschaft.REDEN_TROST,
		1e-6,
		"neuer Tag zaehlt wieder voll"
	)
	assert_eq(int(freund["letzteBegegnungAt"]), 3000, "Begegnung wird gestempelt")


func test_geschenk_vorlieben_und_tageslimit() -> void:
	assert_eq(RNpcFreundschaft.geschenk_reaktion(NPC_DEF, "apfel"), "liebt")
	assert_eq(RNpcFreundschaft.geschenk_reaktion(NPC_DEF, "karotte"), "mag")
	assert_eq(RNpcFreundschaft.geschenk_reaktion(NPC_DEF, "stein"), "normal")
	var freund := RQuestSlices.neuer_freund()
	freund = RNpcFreundschaft.geschenk(freund, NPC_DEF, "apfel", "2026-07-26", 0)
	assert_almost(float(freund["punkte"]), RNpcFreundschaft.GESCHENK_LIEBT)
	freund = RNpcFreundschaft.geschenk(freund, NPC_DEF, "apfel", "2026-07-26", 0)
	assert_almost(
		float(freund["punkte"]),
		RNpcFreundschaft.GESCHENK_LIEBT + RNpcFreundschaft.GESCHENK_TROST,
		1e-6,
		"zweites Geschenk am Tag gibt nur Trost — kein Geschenk-Spam"
	)
	var normal := RNpcFreundschaft.geschenk(
		RQuestSlices.neuer_freund(), NPC_DEF, "stein", "2026-07-26", 0
	)
	assert_almost(
		float(normal["punkte"]),
		RNpcFreundschaft.GESCHENK_NORMAL,
		1e-6,
		"schlechtestes Geschenk gibt trotzdem Punkte (nie Abzug)"
	)


func test_quest_bonus_und_klemme() -> void:
	var freund := RQuestSlices.neuer_freund()
	freund = RNpcFreundschaft.quest_abgeschlossen(freund, 0)
	assert_almost(float(freund["punkte"]), RNpcFreundschaft.QUEST_PUNKTE)
	freund["punkte"] = 98.0
	freund = RNpcFreundschaft.bonus(freund, 50.0, 0)
	assert_almost(float(freund["punkte"]), 100.0, 1e-6, "Punkte klemmen bei 100")
	freund = RNpcFreundschaft.bonus(freund, -33.0, 0)
	assert_almost(float(freund["punkte"]), 100.0, 1e-6, "negative Boni werden ignoriert")


func test_freischaltungen_je_stufe() -> void:
	assert_eq(RNpcFreundschaft.freischaltungen_der_stufe(NPC_DEF, 1), [{"typ": "smalltalk"}])
	assert_eq(RNpcFreundschaft.freischaltungen_der_stufe(NPC_DEF, 2), [])
	assert_eq(RNpcFreundschaft.freischaltungen_bis(NPC_DEF, 3).size(), 2, "Stufe 1 + 3")
	assert_eq(RNpcFreundschaft.freischaltungen_bis(NPC_DEF, 5).size(), 3)


func test_neue_freischaltungen_delta() -> void:
	# Sprung von 20 (Herz 1) auf 75 (Herz 4): Stufen 2..4 werden neu —
	# davon traegt nur Stufe 3 einen Eintrag.
	var neu := RNpcFreundschaft.neue_freischaltungen(NPC_DEF, 20.0, 75.0)
	assert_eq(neu.size(), 1)
	assert_eq(str((neu[0] as Dictionary).get("typ", "")), "rabatt")
	assert_eq(
		RNpcFreundschaft.neue_freischaltungen(NPC_DEF, 75.0, 75.0),
		[],
		"kein Stufensprung = kein Delta"
	)

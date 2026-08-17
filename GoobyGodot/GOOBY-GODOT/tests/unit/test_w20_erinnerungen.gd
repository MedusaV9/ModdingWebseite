extends TestCase
## W20/HORIZONT (Roadmap Top-10 #3): Goobys Gedächtnis kennt die W18/W19-
## Brocken — Goo-und-Bye-Laden (dlc.goobye.*), McGooby-Schichten
## (mcgooby.schichten.*), Ranch-Fundorte (ranch.welt.*), Geister-Bestläufe
## (minigames.geist.*), Urlaubs-Heimkehr/Mitbringsel (vacation.heimkehr* +
## inventory.items) und das Arcade-Spotlight (minigames.spotlightBonusDay).
## Verträge: präparierter Save → erwartete Erinnerung; leerer/kaputter Save
## → NICHTS; alle Sprüche DE+EN paritätisch; keine Duplikat-Ids; die
## Anti-Wiederholung (pick + memoryShownAt-Cooldown) gilt auch für neue
## Quellen.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const DE_PATH := "res://strings/de/soul.json"
const EN_PATH := "res://strings/en/soul.json"
const MS_D := 86_400_000

## Alle neuen W20-Text-Keys (DE+EN Pflicht — 16 Sprüche, 6 Quellen).
const NEUE_KEYS: Array[String] = [
	"soul.erinnerung.goobye_markttag",
	"soul.erinnerung.goobye_umsatz",
	"soul.erinnerung.goobye_lieferwagen",
	"soul.erinnerung.mcgooby_schichten",
	"soul.erinnerung.mcgooby_bestwert",
	"soul.erinnerung.mcgooby_perfekt",
	"soul.erinnerung.ranch_fund",
	"soul.erinnerung.ranch_funde",
	"soul.erinnerung.ranch_karte",
	"soul.erinnerung.geist_rekord",
	"soul.erinnerung.geist_sammlung",
	"soul.erinnerung.heimkehr",
	"soul.erinnerung.mitbringsel",
	"soul.erinnerung.spotlight_a",
	"soul.erinnerung.spotlight_b",
]


func test_frischer_save_bleibt_still() -> void:
	assert_eq(SoulMemories.candidates({}).size(), 0, "leerer State = nichts")
	var frisch := SaveSchema.default_state(100 * MS_D)
	assert_eq(SoulMemories.candidates(frisch).size(), 0, "frischer Save = nichts erlebt")


func test_kaputte_neue_quellen_crashen_nicht() -> void:
	var kaputt := {
		"dlc": {"goobye": {"umsatz": "quatsch", "transport": {"lieferwagen": "ja"}}},
		"mcgooby": {"schichten": {"gespielt": "NaN", "bestwert": null, "perfekt": []}},
		"ranch": {"welt": {"funde": {"nicht": "liste"}, "karteGesehen": [3, null]}},
		"minigames": {"geist": {"sprint": "kein dict"}, "spotlightBonusDay": 7},
		"vacation": {"heimkehrGefeiert": "wahr", "heimkehrZiel": {"x": 1}},
		"inventory": {"items": {"mitbringsel_beach_magnet": "viele"}},
	}
	assert_eq(SoulMemories.candidates(kaputt).size(), 0, "Müll-Typen = still, kein Crash")


func test_goobye_markttag_und_umsatz() -> void:
	var erster := {"dlc": {"goobye": {"umsatz": {"tage": 1, "gestern": 12, "gesamt": 12}}}}
	assert_eq(_ids(erster), ["goobye_markttag"], "1 Markttag = Markttag-Erinnerung")
	var bilanz := {"dlc": {"goobye": {"umsatz": {"tage": 4, "gestern": 40, "gesamt": 250}}}}
	assert_eq(_ids(bilanz), ["goobye_markttag", "goobye_umsatz"], "Bilanz ab Schwelle dazu")
	var out := SoulMemories.candidates(bilanz)
	assert_eq(int(out[1]["args"]["tage"]), 4, "echte Markttage im Text")
	assert_eq(int(out[1]["args"]["muenzen"]), 250, "echter Gesamt-Umsatz im Text")
	var wenig := {
		"dlc":
		{
			"goobye":
			{"umsatz": {"tage": 4, "gestern": 5, "gesamt": SoulMemories.MIN_GOOBYE_UMSATZ - 1}}
		}
	}
	assert_eq(_ids(wenig), ["goobye_markttag"], "unter Umsatz-Schwelle keine Bilanz")


func test_goobye_lieferwagen() -> void:
	var mit := {"dlc": {"goobye": {"transport": {"lieferwagen": true, "unterwegs": {}}}}}
	assert_eq(_ids(mit), ["goobye_lieferwagen"], "Lieferwagen gekauft = Erinnerung")
	var ohne := {"dlc": {"goobye": {"transport": {"lieferwagen": false, "unterwegs": {}}}}}
	assert_eq(_ids(ohne).size(), 0, "ohne Lieferwagen still")


func test_mcgooby_schichten_bestwert_perfekt() -> void:
	var voll := {
		"mcgooby":
		{
			"schichten":
			{
				"gespielt": SoulMemories.MIN_SCHICHTEN,
				"bestwert": SoulMemories.MIN_BESTWERT + 40,
				"perfekt": 1,
			}
		}
	}
	assert_eq(
		_ids(voll),
		["mcgooby_schichten", "mcgooby_bestwert", "mcgooby_perfekt"],
		"alle drei McGooby-Erinnerungen ab Schwelle"
	)
	var out := SoulMemories.candidates(voll)
	assert_eq(int(out[0]["args"]["anzahl"]), SoulMemories.MIN_SCHICHTEN, "echte Schichtenzahl")
	assert_eq(int(out[1]["args"]["punkte"]), SoulMemories.MIN_BESTWERT + 40, "echter Bestwert")
	var wenig := {
		"mcgooby":
		{
			"schichten":
			{
				"gespielt": SoulMemories.MIN_SCHICHTEN - 1,
				"bestwert": SoulMemories.MIN_BESTWERT - 1,
				"perfekt": 0,
			}
		}
	}
	assert_eq(_ids(wenig).size(), 0, "unter allen Schwellen still")


func test_ranch_funde_und_karte() -> void:
	var ein_fund := {"ranch": {"welt": {"v": 1, "entdeckt": ["hof"], "funde": ["wasserfall"]}}}
	assert_eq(_ids(ein_fund), ["ranch_fund_wasserfall"], "ein Fundort = eine Erinnerung")
	var out := SoulMemories.candidates(ein_fund)
	assert_false(str(out[0]["args"]["ort"]).is_empty(), "Fundort-Name aufgelöst")
	# Stabile Auswahl: sortiert, erster gewinnt (Determinismus-Vertrag).
	var zwei := {"ranch": {"welt": {"funde": ["steinkreis", "hoehle"]}}}
	assert_eq(_ids(zwei), ["ranch_fund_hoehle"], "sortierte Fund-Ids, erster gewinnt")
	var viele := {"ranch": {"welt": {"funde": ["wasserfall", "hoehle", "steinkreis"]}}}
	assert_eq(
		_ids(viele), ["ranch_fund_hoehle", "ranch_funde"], "ab MIN_FUNDE kommt die Sammlung dazu"
	)
	assert_eq(int(SoulMemories.candidates(viele)[1]["args"]["anzahl"]), 3, "echte Fund-Anzahl")
	var karte := {"ranch": {"welt": {"karteGesehen": ["wasserfall"]}}}
	assert_eq(_ids(karte), ["ranch_karte"], "Karte angesehen = Karten-Erinnerung")
	assert_eq(_ids({"ranch": {"welt": {"funde": [], "karteGesehen": []}}}).size(), 0, "leer=still")


func test_geist_rekord_und_sammlung() -> void:
	var einer := {
		"minigames":
		{"geist": {"sprint": {"score": 120, "schritt_sec": 1.0, "dauer_sec": 30.0, "kurve": [0]}}}
	}
	assert_eq(_ids(einer), ["geist_sprint"], "ein Bestlauf = eine Geist-Erinnerung")
	assert_eq(int(SoulMemories.candidates(einer)[0]["args"]["punkte"]), 120, "echter Score")
	var zwei := {
		"minigames": {"geist": {"golf": {"score": 80}, "sprint": {"score": 120}, "kaputt": 5}}
	}
	assert_eq(_ids(zwei), ["geist_sprint", "geist_sammlung"], "höchster Score + Sammlung ab 2")
	assert_eq(int(SoulMemories.candidates(zwei)[1]["args"]["anzahl"]), 2, "kaputte zählen nicht")
	assert_eq(_ids({"minigames": {"geist": {"golf": {"score": 0}}}}).size(), 0, "Score 0 = still")


func test_heimkehr_und_mitbringsel() -> void:
	var heim := {"vacation": {"heimkehrGefeiert": true, "heimkehrZiel": "beach"}}
	assert_eq(_ids(heim), ["heimkehr_beach"], "gefeierte Heimkehr = Erinnerung")
	assert_false(
		str(SoulMemories.candidates(heim)[0]["args"]["ziel"]).is_empty(), "Zielname aufgelöst"
	)
	var offen := {"vacation": {"heimkehrGefeiert": false, "heimkehrZiel": "beach"}}
	assert_eq(_ids(offen).size(), 0, "ungefeierte Heimkehr = still (kommt erst nach dem Moment)")
	var sammlung := {
		"inventory":
		{"items": {"mitbringsel_beach_magnet": 1, "mitbringsel_space_wimpel": 2, "sofa": 1}}
	}
	assert_eq(_ids(sammlung), ["mitbringsel"], "2 Mitbringsel = Sammel-Erinnerung")
	assert_eq(int(SoulMemories.candidates(sammlung)[0]["args"]["anzahl"]), 2, "nur mitbringsel_*")
	var eins := {"inventory": {"items": {"mitbringsel_beach_magnet": 1}}}
	assert_eq(_ids(eins).size(), 0, "ein einzelnes Mitbringsel ist noch keine Sammlung")
	var nullstueck := {
		"inventory": {"items": {"mitbringsel_beach_magnet": 0, "mitbringsel_space_wimpel": 0}}
	}
	assert_eq(_ids(nullstueck).size(), 0, "0-Stück-Einträge zählen nicht")


func test_spotlight_deterministische_variante() -> void:
	var gerade := {"minigames": {"spotlightBonusDay": "2026-08-04"}}
	var out := SoulMemories.candidates(gerade)
	assert_eq(_ids(gerade), ["spotlight"], "eingelöster Bonus = Erinnerung")
	assert_eq(str(out[0]["text_key"]), "soul.erinnerung.spotlight_a", "gerader Tag = Variante a")
	var ungerade := {"minigames": {"spotlightBonusDay": "2026-08-05"}}
	assert_eq(
		str(SoulMemories.candidates(ungerade)[0]["text_key"]),
		"soul.erinnerung.spotlight_b",
		"ungerader Tag = Variante b"
	)
	assert_eq(_ids({"minigames": {"spotlightBonusDay": ""}}).size(), 0, "nie eingelöst = still")


func test_keine_duplikat_ids_im_vollen_save() -> void:
	var ids := _ids(_voller_state())
	assert_true(ids.size() >= 14, "voller Save liefert alle Quellen (alt + neu): %s" % [ids])
	var gesehen: Dictionary = {}
	for id in ids:
		assert_false(gesehen.has(id), "Duplikat-Kandidaten-Id: %s" % id)
		gesehen[id] = true


func test_sprueche_de_en_paritaetisch() -> void:
	var de := _flat(DE_PATH)
	var en := _flat(EN_PATH)
	for key in NEUE_KEYS:
		assert_true(de.has(key), "DE fehlt: %s" % key)
		assert_true(en.has(key), "EN fehlt: %s" % key)
		if de.has(key) and en.has(key):
			assert_eq(
				_placeholders(str(en[key])),
				_placeholders(str(de[key])),
				"Platzhalter weichen ab: %s" % key
			)
	# Jeder Kandidat des vollen Saves zeigt auf einen existierenden Key.
	for kandidat in SoulMemories.candidates(_voller_state()):
		var key := str(kandidat["text_key"])
		assert_true(de.has(key) and en.has(key), "text_key ohne Strings: %s" % key)


func test_anti_wiederholung_gilt_auch_fuer_neue_quellen() -> void:
	var kandidaten := SoulMemories.candidates(
		{"dlc": {"goobye": {"umsatz": {"tage": 1, "gestern": 5, "gesamt": 5}}}}
	)
	assert_eq(kandidaten.size(), 1, "genau ein Kandidat")
	var now := 100 * MS_D
	var frisch := {"goobye_markttag": now - MS_D}
	assert_true(
		SoulMemories.pick(kandidaten, frisch, now, 0.0).is_empty(),
		"frisch gezeigt = Cooldown filtert (lieber Stille als Wiederholung)"
	)
	var alt := {"goobye_markttag": now - SoulMemories.MEMORY_COOLDOWN_MS}
	assert_eq(
		str(SoulMemories.pick(kandidaten, alt, now, 0.0)["id"]),
		"goobye_markttag",
		"nach 3 Tagen wieder erlaubt"
	)


## Save, in dem ALLE Quellen (Bestand + W20) etwas zu erzählen haben.
func _voller_state() -> Dictionary:
	return {
		"minigames":
		{
			"legacy": {"best": {"minigolf": 42, "sprint": 99}},
			"geist": {"golf": {"score": 80}, "sprint": {"score": 120}},
			"spotlightBonusDay": "2026-08-04",
		},
		"vacation": {"visited": {"beach": 1}, "heimkehrGefeiert": true, "heimkehrZiel": "beach"},
		"achievements": {"counters": {"tickles": 20, "harvests": 10}},
		"daily": {"streak": 7},
		"park": {"visits": 2},
		"profile": {"playtimeMin": 600},
		"soul": {"foodGiven": {"apple": 3}},
		"dlc":
		{
			"goobye":
			{
				"umsatz": {"tage": 4, "gestern": 40, "gesamt": 250},
				"transport": {"lieferwagen": true, "unterwegs": {}},
			}
		},
		"mcgooby": {"schichten": {"gespielt": 5, "bestwert": 130, "perfekt": 2}},
		"ranch":
		{"welt": {"funde": ["wasserfall", "hoehle", "steinkreis"], "karteGesehen": ["wasserfall"]}},
		"inventory": {"items": {"mitbringsel_beach_magnet": 1, "mitbringsel_space_wimpel": 1}},
	}


func _ids(state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for kandidat in SoulMemories.candidates(state):
		out.append(str(kandidat["id"]))
	return out


func _flat(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		fail_test("Strings-Datei kaputt: %s" % path)
		return {}
	var out := {}
	_flatten("", parsed, out)
	return out


func _flatten(prefix: String, node: Dictionary, out: Dictionary) -> void:
	for key: String in node:
		var full := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		if node[key] is Dictionary:
			_flatten(full, node[key], out)
		else:
			out[full] = node[key]


func _placeholders(text: String) -> Array[String]:
	var out: Array[String] = []
	var regex := RegEx.new()
	regex.compile("\\{(\\w+)\\}")
	for hit in regex.search_all(text):
		out.append(hit.get_string(1))
	out.sort()
	return out

extends TestCase  # gdlint: ignore=max-public-methods
## G8/IDEA-SEELE: Stimmungs-Herz + Morgen-/Abend-Ritual — die PUREN Hälften.
## Deckt die vier geforderten Achsen ab:
##  1. Laune-Band → Herz-Zustand (Farbe/Füllstand) deterministisch,
##  2. Sheet-Inhalt aus den ECHTEN Treibern (injizierte Zustände),
##  3. Morgen-Kette in fester Folge (Ritual VOR Bonus VOR Guide, nie gestapelt),
##  4. Einmal-pro-Tag-Gate mit INJIZIERTER Uhr (ctx statt Systemzeit).
## Dazu die Abend-Bilanz (Zeilen aus echten Tagesdaten, Deckel, Ruhig-Fall).

const GameStateScript := preload("res://scripts/state/game_state.gd")

const MS_H := 3_600_000
const MS_TAG := 86_400_000
## 2026-08-02 12:00 UTC — fester Anker, alle Zeiten leiten sich hieraus ab.
const T0 := 1_785_672_000_000
const HEUTE := "2026-08-02"

# ── 1. Laune-Band → Herz-Zustand ─────────────────────────────────────────────


func test_herz_farbe_folgt_dem_band() -> void:
	# Jedes Band hat seine Farbe; alle fünf sind paarweise verschieden.
	var farben: Array[Color] = []
	for band: String in SoulMood.BAND_ORDNUNG:
		var farbe := StimmungsHerz.farbe_fuer_band(band)
		assert_eq(farbe, StimmungsHerz.BAND_FARBEN[band], "Band %s hat feste Farbe" % band)
		for alt in farben:
			assert_ne(farbe, alt, "Band-Farben unterscheidbar (%s)" % band)
		farben.append(farbe)
	assert_eq(
		StimmungsHerz.farbe_fuer_band("quatsch"),
		StimmungsHerz.BAND_FARBEN["neutral"],
		"unbekanntes Band fällt auf neutral"
	)


func test_herz_wert_zu_band_und_fuellstand_deterministisch() -> void:
	# Wert → Band (bestehende §C1-Schwellen) → Farbe, plus linearer Füllstand.
	var faelle := [
		[85.0, "ecstatic"],
		[65.0, "happy"],
		[45.0, "neutral"],
		[30.0, "grumpy"],
		[10.0, "miserable"],
	]
	for fall: Array in faelle:
		var wert := float(fall[0])
		assert_eq(SoulMood.band(wert), str(fall[1]), "Band für wert=%f" % wert)
	assert_almost(StimmungsHerz.fuellstand(0.0), 0.0)
	assert_almost(StimmungsHerz.fuellstand(50.0), 0.5)
	assert_almost(StimmungsHerz.fuellstand(100.0), 1.0)
	assert_almost(StimmungsHerz.fuellstand(140.0), 1.0, 1e-6, "Klammer oben")
	assert_almost(StimmungsHerz.fuellstand(-5.0), 0.0, 1e-6, "Klammer unten")


func test_herz_umriss_liegt_im_quadrat() -> void:
	# Herz-Polygon deterministisch und innerhalb der Seitenlänge (Chip-Platz).
	var seite := 26.0
	var punkte := StimmungsHerz.herz_punkte(seite)
	assert_eq(punkte.size(), 28, "feste Punktzahl (deterministisch)")
	assert_eq(punkte, StimmungsHerz.herz_punkte(seite), "gleiche Eingabe → gleiche Punkte")
	for p: Vector2 in punkte:
		assert_true(p.x >= 0.0 and p.x <= seite, "x im Quadrat (%s)" % p)
		assert_true(p.y >= 0.0 and p.y <= seite, "y im Quadrat (%s)" % p)


# ── 2. Sheet-Inhalt aus Treibern (injizierte Zustände) ───────────────────────


func _basis_state(stats: Dictionary, extra := {}) -> Dictionary:
	var state := {
		"meta": {"goobyNickname": "Flauschi"},
		"gooby": {"stats": stats, "health": {"state": "healthy"}, "grumpyUntil": 0},
		"soul": {"stimmung": {"wert": 62.0, "aktualisiertMs": T0}},
	}
	for key: Variant in extra:
		state[key] = extra[key]
	return state


func test_sheet_hunger_treiber_und_tipp() -> void:
	var state := _basis_state({"hunger": 20.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0})
	var daten := StimmungsSheet.inhalt(state, T0)
	assert_eq(daten["gruende"], ["seele_tag.grund.hunger"], "niedriger Hunger wird benannt")
	assert_eq(daten["tipps"], ["seele_tag.tipp.hunger"], "Möhren-Tipp dazu")
	assert_eq(str(daten["args"]["gooby"]), "Flauschi", "Spitzname in den Args")


func test_sheet_kritischer_hunger_verschaerft_den_ton() -> void:
	var state := _basis_state({"hunger": 5.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0})
	var daten := StimmungsSheet.inhalt(state, T0)
	assert_eq((daten["gruende"] as Array)[0], "seele_tag.grund.hunger_stark", "kritisch → LAUT")


func test_sheet_krankheit_gewinnt_vor_stats() -> void:
	var state := _basis_state({"hunger": 20.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0})
	(state["gooby"] as Dictionary)["health"] = {"state": "sick"}
	var daten := StimmungsSheet.inhalt(state, T0)
	assert_eq((daten["gruende"] as Array)[0], "seele_tag.grund.krank", "krank steht zuerst")
	assert_eq((daten["tipps"] as Array)[0], "seele_tag.tipp.krank", "Medizin-Tipp zuerst")
	assert_eq((daten["gruende"] as Array).size(), 2, "Hunger passt noch mit rein")
	assert_eq((daten["gruende"] as Array)[1], "seele_tag.grund.hunger")


func test_sheet_niedrigster_treiber_zuerst_und_deckel() -> void:
	# fun=12 < hunger=20 — der dominante (niedrigste) Treiber wird zuerst
	# benannt; energy=24 wäre der dritte, fällt aber unter den 2er-Deckel.
	var state := _basis_state({"hunger": 20.0, "energy": 24.0, "hygiene": 90.0, "fun": 12.0})
	var daten := StimmungsSheet.inhalt(state, T0)
	assert_eq(
		daten["gruende"],
		["seele_tag.grund.langeweile", "seele_tag.grund.hunger"],
		"niedrigster zuerst, Deckel 2"
	)
	assert_eq(
		daten["tipps"],
		["seele_tag.tipp.langeweile", "seele_tag.tipp.hunger"],
		"Tipps folgen den Gründen"
	)


func test_sheet_frueh_geweckt_brummelt() -> void:
	var state := _basis_state({"hunger": 90.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0})
	(state["gooby"] as Dictionary)["grumpyUntil"] = T0 + MS_H
	var daten := StimmungsSheet.inhalt(state, T0)
	assert_eq(daten["gruende"], ["seele_tag.grund.frueh_geweckt"], "Brummel-Grund")
	assert_eq(daten["tipps"], ["seele_tag.tipp.weiter_so"], "ohne Stat-Tipp: weiter so")


func test_sheet_alles_gut_ohne_befund() -> void:
	var state := _basis_state({"hunger": 90.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0})
	var daten := StimmungsSheet.inhalt(state, T0)
	assert_eq(daten["gruende"], ["seele_tag.grund.alles_gut"], "warme Alles-gut-Zeile")
	assert_eq(daten["tipps"], ["seele_tag.tipp.weiter_so"])


func test_sheet_band_satz_folgt_der_laune() -> void:
	var state := _basis_state({"hunger": 90.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0})
	((state["soul"] as Dictionary)["stimmung"] as Dictionary)["wert"] = 85.0
	assert_eq(str(StimmungsSheet.inhalt(state, T0)["laune_key"]), "seele_tag.laune.ecstatic")
	((state["soul"] as Dictionary)["stimmung"] as Dictionary)["wert"] = 12.0
	assert_eq(str(StimmungsSheet.inhalt(state, T0)["laune_key"]), "seele_tag.laune.miserable")


func test_sheet_wunsch_nur_wenn_offen() -> void:
	var state := _basis_state(
		{"hunger": 90.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0}, {"park": {"visits": 0}}
	)
	(state["soul"] as Dictionary)["wunsch"] = {"id": "funkelpark", "seitMs": T0}
	assert_eq(
		str(StimmungsSheet.inhalt(state, T0)["wunsch_key"]),
		"seele_tag.wunsch.funkelpark",
		"offener Wunsch wird erwähnt"
	)
	# Park besucht → Wunsch erfüllt → keine Wunsch-Zeile mehr.
	(state["park"] as Dictionary)["visits"] = 1
	assert_eq(str(StimmungsSheet.inhalt(state, T0)["wunsch_key"]), "", "erfüllt → still")


# ── 3./4. Morgen-Kette: Reihenfolge + einmal pro Tag (injizierte Uhr) ────────


func _morgen_state(extra := {}) -> Dictionary:
	var state := {
		"onboarding": {"done": true},
		"soul":
		{
			"firstMetAt": T0 - 3 * MS_TAG,
			"lastVisitAt": T0 - 2 * MS_H,
			"celebrated": {},
		},
		"gooby": {"sleep": {"sleeping": false}},
	}
	for key: Variant in extra:
		state[key] = extra[key]
	return state


func _ctx(stunde := 8) -> Dictionary:
	return {"now_ms": T0, "heute": HEUTE, "stunde": stunde}


func test_morgen_kette_feste_reihenfolge() -> void:
	var plan := MorgenRitual.plan(_morgen_state(), _ctx())
	assert_eq(
		plan,
		[MorgenRitual.SCHRITT_RITUAL, MorgenRitual.SCHRITT_BONUS, MorgenRitual.SCHRITT_GUIDE],
		"Ritual VOR Bonus VOR Guide — nie gestapelt"
	)
	# Ritual nicht fällig (Mittag): Kette bleibt Bonus → Guide (alte Folge).
	var mittags := MorgenRitual.plan(_morgen_state(), _ctx(14))
	assert_eq(mittags, [MorgenRitual.SCHRITT_BONUS, MorgenRitual.SCHRITT_GUIDE])


func test_morgen_faellig_nur_im_fenster() -> void:
	assert_false(MorgenRitual.faellig(_morgen_state(), _ctx(4)), "4 Uhr: zu früh")
	assert_true(MorgenRitual.faellig(_morgen_state(), _ctx(5)), "5 Uhr: Fenster auf")
	assert_true(MorgenRitual.faellig(_morgen_state(), _ctx(10)), "10 Uhr: noch drin")
	assert_false(MorgenRitual.faellig(_morgen_state(), _ctx(11)), "11 Uhr: Fenster zu")


func test_morgen_einmal_pro_tag_mit_injizierter_uhr() -> void:
	var state := _morgen_state()
	var ctx := _ctx()
	assert_true(MorgenRitual.faellig(state, ctx), "erster Aufruf des Tages: fällig")
	# Buchen wie die Sequenz es tut — direkt auf der Slice-Kopie.
	var slice := SoulState.normalize_slice(state["soul"])
	MorgenRitual.stempeln(slice, ctx)
	state["soul"] = slice
	assert_false(MorgenRitual.faellig(state, ctx), "zweiter Aufruf am selben Tag: still")
	assert_eq(str(slice["lastGreetDay"]), HEUTE, "Gruß-Tag gestempelt (kein Doppel-Gruß)")
	assert_eq(str(slice["lastGreetKind"]), MorgenRitual.GATE_KEY)
	assert_eq(str((slice["celebrated"] as Dictionary)[MorgenRitual.GATE_KEY]), HEUTE)
	assert_eq(str((slice["ambient"] as Dictionary)["day"]), HEUTE, "Ambient-Bremse gebucht")
	# Nächster Tag (injizierte Uhr einen Tag weiter): wieder fällig.
	var morgen := {"now_ms": T0 + MS_TAG, "heute": "2026-08-03", "stunde": 8}
	assert_true(MorgenRitual.faellig(state, morgen), "neuer Tag → wieder fällig")


func test_morgen_gates_onboarding_tag0_schlaf_abwesenheit() -> void:
	# Onboarding offen → Tag gehört dem Onboarding.
	var frisch := _morgen_state({"onboarding": {"done": false}})
	assert_false(MorgenRitual.faellig(frisch, _ctx()), "ohne Onboarding kein Ritual")
	# Tag 0 (Einzug vor 2 h) → die Ankunft inszeniert der Guide.
	var einzug := _morgen_state()
	(einzug["soul"] as Dictionary)["firstMetAt"] = T0 - 2 * MS_H
	assert_false(MorgenRitual.faellig(einzug, _ctx()), "Einzugstag gehört der Ankunft")
	# Gooby schläft noch → Aufwachen gehört dem PflegeRunner.
	var schlaeft := _morgen_state()
	(schlaeft["gooby"] as Dictionary)["sleep"] = {"sleeping": true}
	assert_false(MorgenRitual.faellig(schlaeft, _ctx()), "schlafend kein zweites Kino")
	# Lange Lücke (50 h) → der Abwesenheits-Gruß (eingeschnappt) gewinnt.
	var luecke := _morgen_state()
	(luecke["soul"] as Dictionary)["lastVisitAt"] = T0 - 50 * MS_H
	assert_false(MorgenRitual.faellig(luecke, _ctx()), "eingeschnappt schlägt Guten-Morgen")


func test_morgen_begruessung_aus_echten_tagesdaten() -> void:
	var zeilen := (
		MorgenRitual
		. begruessung(
			{
				"player_name": "Mia",
				"wetter": {"typ": "regen"},
				"markt_heute": true,
				"quest_titel": "Möhrenfang",
			}
		)
	)
	assert_eq(zeilen.size(), MorgenRitual.MAX_ZEILEN, "Deckel: Gruß + Wetter + EIN Ausblick")
	assert_eq(str(zeilen[0]["key"]), "seele_tag.morgen.gruss")
	assert_eq(str((zeilen[0]["args"] as Dictionary)["namek"]), ", Mia", "Name im Gruß")
	assert_eq(str(zeilen[1]["key"]), "seele_tag.morgen.wetter.regen", "echtes Wetter")
	assert_eq(str(zeilen[2]["key"]), "seele_tag.morgen.markt", "seltener Markttag gewinnt")
	# Ohne Markt rückt die Quest nach; ohne Namen bleibt der Gruß pur.
	var ohne_markt := MorgenRitual.begruessung(
		{"player_name": "", "wetter": {"typ": "sonne"}, "quest_titel": "Möhrenfang"}
	)
	assert_eq(str(ohne_markt[0]["args"]["namek"]), "", "kein Name → kein Komma")
	assert_eq(str(ohne_markt[2]["key"]), "seele_tag.morgen.quest")
	assert_eq(str(ohne_markt[2]["args"]["quest"]), "Möhrenfang")


func test_morgen_lokale_zeit_mit_offset() -> void:
	# T0 = 12:00 UTC; Offset +120 min (injiziert wie clock.set_utc_offset).
	var utc := MorgenRitual.lokale_zeit(T0, 0)
	assert_eq(int(utc["hour"]), 12, "UTC-Stunde")
	var berlin := MorgenRitual.lokale_zeit(T0, 120)
	assert_eq(int(berlin["hour"]), 14, "Offset verschiebt die Stunde")
	assert_eq(int(berlin["weekday"]), 0, "2026-08-02 ist ein Sonntag")


# ── Abend-Bilanz ──────────────────────────────────────────────────────────────


func test_abend_fenster() -> void:
	assert_false(AbendBilanz.anzeigen(12), "mittags keine Bilanz")
	assert_false(AbendBilanz.anzeigen(17), "17 Uhr noch nicht")
	assert_true(AbendBilanz.anzeigen(18), "ab 18 Uhr")
	assert_true(AbendBilanz.anzeigen(23), "spätabends")
	assert_true(AbendBilanz.anzeigen(3), "Nachteulen bis 4")
	assert_false(AbendBilanz.anzeigen(4), "ab 4 gehört der Tag dem Morgen")


func test_abend_zeilen_aus_echten_tagesdaten() -> void:
	var state := {
		"achievements": {"counters": {"petsToday": 14, "petsDay": HEUTE}},
		"quests":
		{
			"day": HEUTE,
			"active": [{"claimed": true}, {"claimed": true}, {"claimed": false}],
		},
	}
	var zeilen := AbendBilanz.zeilen(state, HEUTE)
	assert_eq(zeilen.size(), 2)
	assert_eq(str(zeilen[0]["key"]), "seele_tag.abend.streicheln", "Streichler zuerst")
	assert_eq(int((zeilen[0]["args"] as Dictionary)["anzahl"]), 14, "echte Zahl aus dem Save")
	assert_eq(str(zeilen[1]["key"]), "seele_tag.abend.quest_viele")
	assert_eq(int((zeilen[1]["args"] as Dictionary)["anzahl"]), 2, "nur ABGEHOLTE zählen")


func test_abend_deckel_und_reihenfolge() -> void:
	# Alle vier Quellen liefern — es bleiben MAX_ZEILEN in Wärme-Reihenfolge.
	var state := {
		"achievements": {"counters": {"petsToday": 3, "petsDay": HEUTE}},
		"quests": {"day": HEUTE, "active": [{"claimed": true}]},
		"minigames": {"legacy": {"lastPlayDay": {"carrotCatch": HEUTE}}},
		"daily": {"streak": 5, "lastClaimDay": HEUTE},
	}
	var zeilen := AbendBilanz.zeilen(state, HEUTE)
	assert_eq(zeilen.size(), AbendBilanz.MAX_ZEILEN, "nie mehr als 3 Zeilen")
	assert_eq(str(zeilen[0]["key"]), "seele_tag.abend.streicheln")
	assert_eq(str(zeilen[1]["key"]), "seele_tag.abend.quest_eine")
	assert_eq(str(zeilen[2]["key"]), "seele_tag.abend.spiel")
	assert_eq(str(zeilen[2]["spiel_id"]), "carrotCatch", "Spiel-Id fürs Titel-Lookup")


func test_abend_gestern_zaehlt_nicht_und_ruhig_fall() -> void:
	# Gestrige Stempel bleiben stumm — und ohne Befund kommt die Ruhig-Zeile.
	var state := {
		"achievements": {"counters": {"petsToday": 9, "petsDay": "2026-08-01"}},
		"quests": {"day": "2026-08-01", "active": [{"claimed": true}]},
		"minigames": {"legacy": {"lastPlayDay": {"carrotCatch": "2026-08-01"}}},
		"daily": {"streak": 9, "lastClaimDay": "2026-08-01"},
	}
	var zeilen := AbendBilanz.zeilen(state, HEUTE)
	assert_eq(zeilen.size(), 1)
	assert_eq(str(zeilen[0]["key"]), "seele_tag.abend.ruhig", "leerer Tag → zusammen sein")
	assert_eq(AbendBilanz.zeilen({}, HEUTE).size(), 1, "leerer State crasht nicht")


# ── RewardHub-Gate: Onboarding-Slice-Hook nur bis zur ersten Ankunft ─────────


func _hub_gs(nr: int) -> Node:
	var dir := "user://idea_seele_tests/hub_%d_%d" % [Time.get_ticks_usec(), nr]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(T0)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	gs.update(func(s: Dictionary) -> void: (s["onboarding"] as Dictionary)["done"] = true)
	return gs


func test_bonus_hook_entschaerft_nach_ankunft() -> void:
	# PT1-B6-Kern: NACH der ersten Ankunft darf ein Onboarding-Slice-Write
	# (die Guide-Tour schreibt bei JEDEM Schritt-Fortschritt) den per
	# „Später“ weggelegten Bonus NICHT wieder über die Tour legen.
	var gs := _hub_gs(1)
	var host := Node.new()
	tree.root.add_child(host)
	var hub := RewardHub.attach_to(host, gs)
	await wait_frames(2)
	hub._on_travel_finished()
	await wait_frames(1)
	var popup: Control = hub._daily_popup
	assert_true(popup != null and is_instance_valid(popup), "erste Ankunft bietet den Bonus an")
	# „Später“: Popup schließt ungeclaimt — der Bonus bleibt abholbar.
	popup.queue_free()
	await wait_frames(2)
	# Guide-Schritt-Write (exakt der Pfad von OnboardingGuide._write_slice).
	gs.notify_slice_changed("onboarding")
	await wait_frames(3)
	assert_false(
		hub._daily_popup != null and is_instance_valid(hub._daily_popup),
		"kein Re-Angebot über der laufenden Tour (PT1-B6-Stapel)"
	)
	host.queue_free()
	await wait_frames(1)
	gs.free()


func test_bonus_hook_scharf_vor_der_ankunft() -> void:
	# VOR der ersten Ankunft bleibt der Hook scharf: der Onboarding-fertig-
	# Write darf den ersten Tagesbonus anstoßen (Web-Fluss).
	var gs := _hub_gs(2)
	var host := Node.new()
	tree.root.add_child(host)
	var hub := RewardHub.attach_to(host, gs)
	await wait_frames(2)
	gs.notify_slice_changed("onboarding")
	await wait_frames(3)
	assert_true(
		hub._daily_popup != null and is_instance_valid(hub._daily_popup),
		"Onboarding-fertig bietet den ersten Bonus an"
	)
	host.queue_free()
	await wait_frames(1)
	gs.free()

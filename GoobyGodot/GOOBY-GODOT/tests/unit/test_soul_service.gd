extends TestCase
## FB-6/SEELE: Orchestrator — Prioritäten beim Betreten, decide→book→decide
## muss gaten (Rituale 1x/Tag, Grüße 1x/Tag, Frequenzbremse), Überraschungs-
## Cooldowns, Geburtstags-Nachfrage. Alles mit hereingereichter Zeit — die
## Datumssprünge sind simulierte ctx-Änderungen, kein Warten.

const MS_D := 86_400_000


## Minimale Def-Liste — Tests hängen NICHT am Content-Pack.
func _defs() -> Array:
	return [
		{"id": "gruss_morgen", "kind": "gruss", "text_keys": ["k.morgen"]},
		{"id": "gruss_abend", "kind": "gruss", "text_keys": ["k.abend"]},
		{"id": "gruss_gefreut", "kind": "gruss", "text_keys": ["k.gefreut"]},
		{"id": "gruss_eingeschnappt", "kind": "gruss", "text_keys": ["k.miffed"]},
		{"id": "gruss_vermisst", "kind": "gruss", "text_keys": ["k.vermisst"]},
		{
			"id": "ritual_geburtstag_spieler",
			"kind": "ritual",
			"text_keys": ["k.geb"],
			"aktion": "konfetti",
		},
		{"id": "ritual_geburtstag_gooby", "kind": "ritual", "text_keys": ["k.ggeb"]},
		{"id": "ritual_jubilaeum", "kind": "ritual", "text_keys": ["k.jub"]},
		{"id": "ritual_halloween", "kind": "ritual", "text_keys": ["k.hallo"]},
		{"id": "ritual_erster_schnee", "kind": "ritual", "text_keys": ["k.schnee"]},
		{"id": "wetter_regen", "kind": "wetter", "text_keys": ["k.regen"]},
		{"id": "erinnerung", "kind": "erinnerung", "text_keys": []},
		{"id": "idle_doesen", "kind": "idle", "weight": 1},
		{"id": "idle_fernsehen", "kind": "idle", "weight": 1, "braucht": "hat_tv"},
		{"id": "sup_traum", "kind": "ueberraschung", "chance": 0.5, "cooldown_h": 72},
	]


func _slice() -> Dictionary:
	return SoulState.default_slice()


func _ctx(year: int, month: int, day: int, hour := 12, gap_ms := 0, wetter := {}) -> Dictionary:
	var date := {"year": year, "month": month, "day": day, "hour": hour}
	return {
		"now_ms": _ms_of(year, month, day, hour),
		"date": date,
		"hour": hour,
		"gap_ms": gap_ms,
		"wetter":
		wetter if not wetter.is_empty() else {"typ": "sonne", "regen": false, "schnee": false},
		"player_name": "Mira",
		"nickname": "Gooby",
	}


func _ms_of(year: int, month: int, day: int, hour: int) -> int:
	return (
		Time.get_unix_time_from_datetime_dict(
			{"year": year, "month": month, "day": day, "hour": hour, "minute": 0, "second": 0}
		)
		* 1000
	)


func test_geburtstag_schlaegt_gruss() -> void:
	var slice := _slice()
	slice["playerBirthday"] = {"month": 3, "day": 14}
	slice["firstMetAt"] = _ms_of(2026, 1, 1, 12)
	var ctx := _ctx(2026, 3, 14, 8)
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_eq(str(moment.get("id", "")), "ritual_geburtstag_spieler", "Ritual vor Gruß")
	assert_eq(str(moment.get("kind", "")), "ritual", "kind=ritual")
	assert_eq(str(moment.get("args", {}).get("name", "")), "Mira", "Name im Text")


func test_decide_book_decide_gatet_ritual_und_naechstes_jahr_wieder() -> void:
	var slice := _slice()
	slice["playerBirthday"] = {"month": 3, "day": 14}
	slice["firstMetAt"] = _ms_of(2026, 1, 1, 12)
	var ctx := _ctx(2026, 3, 14, 8)
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	SoulService.book_enter(slice, moment, ctx)
	var again := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_ne(str(again.get("id", "")), "ritual_geburtstag_spieler", "heute nicht doppelt")
	# Datumssprung: exakt ein Jahr später zündet der Geburtstag wieder.
	var ctx_next := _ctx(2027, 3, 14, 8)
	var next_year := SoulService.decide_enter({}, slice, _defs(), ctx_next, 0.9)
	assert_eq(str(next_year.get("id", "")), "ritual_geburtstag_spieler", "nächstes Jahr wieder")


func test_gooby_geburtstag_am_einzugstag() -> void:
	var slice := _slice()
	slice["firstMetAt"] = _ms_of(2025, 7, 26, 10)
	var ctx := _ctx(2026, 7, 26, 12)
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_eq(str(moment.get("id", "")), "ritual_geburtstag_gooby", "Einzugstag = Geburtstag")


func test_jubilaeum_100_tage_und_sprung_verfaellt() -> void:
	var slice := _slice()
	var start := _ms_of(2026, 1, 1, 12)
	slice["firstMetAt"] = start
	var ctx := _ctx(2026, 1, 1, 12)
	ctx["now_ms"] = start + 100 * MS_D
	ctx["date"] = {"year": 2026, "month": 4, "day": 11, "hour": 12}
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_eq(str(moment.get("id", "")), "ritual_jubilaeum", "Tag 100 gefeiert")
	assert_eq(int(moment.get("args", {}).get("tage", 0)), 100, "Meilenstein im Text")
	# Datumssprung ÜBER den Meilenstein (Tag 99 → Tag 104): kein Nachfeiern.
	var slice2 := _slice()
	slice2["firstMetAt"] = start
	var ctx2 := _ctx(2026, 1, 1, 12)
	ctx2["now_ms"] = start + 104 * MS_D
	ctx2["date"] = {"year": 2026, "month": 4, "day": 15, "hour": 12}
	var skipped := SoulService.decide_enter({}, slice2, _defs(), ctx2, 0.9)
	assert_ne(str(skipped.get("id", "")), "ritual_jubilaeum", "übersprungen = still")


func test_feiertag_und_erster_schnee_1x_pro_saison() -> void:
	var slice := _slice()
	slice["firstMetAt"] = _ms_of(2026, 1, 2, 12)
	var ctx := _ctx(2026, 10, 31, 18)
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_eq(str(moment.get("id", "")), "ritual_halloween", "Halloween")
	SoulService.book_enter(slice, moment, ctx)
	# Erster Schnee: zündet bei Schnee-Wetter, dann für die Saison gebucht.
	var schnee_ctx := _ctx(2026, 12, 10, 9, 0, {"typ": "schnee", "regen": false, "schnee": true})
	var schnee := SoulService.decide_enter({}, slice, _defs(), schnee_ctx, 0.9)
	assert_eq(str(schnee.get("id", "")), "ritual_erster_schnee", "erster Schnee")
	SoulService.book_enter(slice, schnee, schnee_ctx)
	# Januar, gleiche Saison: still. (Datumssprung über den Jahreswechsel!)
	var januar_ctx := _ctx(2027, 1, 20, 9, 0, {"typ": "schnee", "regen": false, "schnee": true})
	var januar := SoulService.decide_enter({}, slice, _defs(), januar_ctx, 0.9)
	assert_ne(str(januar.get("id", "")), "ritual_erster_schnee", "Saison schon gefeiert")


func test_gruss_tageszeit_und_1x_pro_tag() -> void:
	var slice := _slice()
	slice["firstMetAt"] = _ms_of(2026, 7, 20, 12)
	var ctx := _ctx(2026, 7, 26, 8)
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_eq(str(moment.get("id", "")), "gruss_morgen", "morgens Morgen-Gruß")
	SoulService.book_enter(slice, moment, ctx)
	# Abends am gleichen Tag: KEIN zweiter Gruß (lastGreetDay-Gate).
	var abend_ctx := _ctx(2026, 7, 26, 19)
	abend_ctx["now_ms"] = int(ctx["now_ms"]) + 11 * 3_600_000
	var abend := SoulService.decide_enter({}, slice, _defs(), abend_ctx, 0.9)
	assert_ne(str(abend.get("id", "")), "gruss_abend", "nur ein Gruß pro Tag")


func test_gruss_abwesenheit_vor_tageszeit() -> void:
	var slice := _slice()
	slice["firstMetAt"] = _ms_of(2026, 7, 1, 12)
	var ctx := _ctx(2026, 7, 26, 8, 3 * MS_D)
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_eq(str(moment.get("id", "")), "gruss_eingeschnappt", "48h+ = eingeschnappt")
	var ctx_lang := _ctx(2026, 7, 26, 8, 8 * MS_D)
	var lang := SoulService.decide_enter({}, slice, _defs(), ctx_lang, 0.9)
	assert_eq(str(lang.get("id", "")), "gruss_vermisst", "7 Tage+ = vermisst")


func test_frequenzbremse_blockt_ambiente_nicht_rituale() -> void:
	var slice := _slice()
	slice["playerBirthday"] = {"month": 7, "day": 26}
	slice["firstMetAt"] = _ms_of(2026, 7, 1, 12)
	# Bremse gerade eben benutzt:
	var ctx := _ctx(2026, 7, 26, 8)
	slice["ambient"] = {"day": "2026-07-26", "count": 3, "lastAt": int(ctx["now_ms"]) - 1_000}
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_eq(
		str(moment.get("id", "")),
		"ritual_geburtstag_spieler",
		"Ritual ignoriert die Frequenzbremse"
	)
	SoulService.book_enter(slice, moment, ctx)
	# Ohne Ritual wäre jetzt Stille (Gruß wird von der Bremse geblockt).
	var still := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_true(still.is_empty(), "ambienter Moment von der Bremse geblockt")


func test_wetter_kommentar_1x_pro_tag() -> void:
	var slice := _slice()
	slice["firstMetAt"] = _ms_of(2026, 7, 1, 12)
	slice["lastGreetDay"] = "2026-07-26"
	var ctx := _ctx(2026, 7, 26, 14, 0, {"typ": "regen", "regen": true, "schnee": false})
	var moment := SoulService.decide_enter({}, slice, _defs(), ctx, 0.9)
	assert_eq(str(moment.get("id", "")), "wetter_regen", "Regen-Kommentar")
	SoulService.book_enter(slice, moment, ctx)
	var ctx2 := _ctx(2026, 7, 26, 16, 0, {"typ": "regen", "regen": true, "schnee": false})
	var again := SoulService.decide_enter({}, slice, _defs(), ctx2, 0.9)
	assert_ne(str(again.get("id", "")), "wetter_regen", "gleicher Regen nur 1x kommentiert")


func test_erinnerung_nur_mit_echten_daten() -> void:
	var slice := _slice()
	slice["firstMetAt"] = _ms_of(2026, 7, 1, 12)
	slice["lastGreetDay"] = "2026-07-26"
	var ctx := _ctx(2026, 7, 26, 14)
	# Leerer State → keine Kandidaten → Stille (roll unter MEMORY_CHANCE).
	var leer := SoulService.decide_enter({}, slice, _defs(), ctx, 0.1)
	assert_true(leer.is_empty(), "keine Erinnerung ohne echte Daten")
	# Echter Rekord im State → Erinnerung mit echten Zahlen.
	var state := {"minigames": {"legacy": {"best": {"minigolf": 42}}}}
	var moment := SoulService.decide_enter(state, slice, _defs(), ctx, 0.1)
	assert_eq(str(moment.get("kind", "")), "erinnerung", "Erinnerung gewählt")
	assert_eq(str(moment.get("memory_id", "")), "rekord_minigolf", "aus echten Daten")
	assert_eq(int(moment.get("args", {}).get("punkte", 0)), 42, "echter Punktestand")
	# Hoher roll → bewusst Stille (Erinnerungen sind selten).
	var selten := SoulService.decide_enter(state, slice, _defs(), ctx, 0.9)
	assert_true(selten.is_empty(), "roll über MEMORY_CHANCE = Stille")


func test_idle_braucht_und_cooldown() -> void:
	var ctx := _ctx(2026, 7, 26, 14)
	ctx["hat_tv"] = false
	var act := SoulService.pick_idle(_defs(), ctx, {}, 0.9)
	assert_eq(str(act.get("id", "")), "idle_doesen", "ohne TV nur dösen")
	ctx["hat_tv"] = true
	var mit_tv := SoulService.pick_idle(_defs(), ctx, {}, 0.9)
	assert_eq(str(mit_tv.get("id", "")), "idle_fernsehen", "mit TV bei hohem roll TV")
	# Cooldown sperrt einzelne Akte.
	var cooldowns := {"idle_fernsehen": int(ctx["now_ms"]) + 60_000}
	var gesperrt := SoulService.pick_idle(_defs(), ctx, cooldowns, 0.9)
	assert_eq(str(gesperrt.get("id", "")), "idle_doesen", "Cooldown filtert")


func test_ueberraschung_chance_und_cooldown() -> void:
	var slice := _slice()
	var ctx := _ctx(2026, 7, 26, 14)
	# roll_gate über der Chance: nichts.
	var nix := SoulService.pick_surprise(slice, _defs(), ctx, 0.0, 0.9)
	assert_true(nix.is_empty(), "Gate hält dicht")
	# roll_gate unter der Chance: Überraschung.
	var moment := SoulService.pick_surprise(slice, _defs(), ctx, 0.0, 0.1)
	assert_eq(str(moment.get("id", "")), "sup_traum", "Überraschung gewählt")
	SoulService.book_surprise(slice, moment, int(ctx["now_ms"]))
	# Direkt danach: Cooldown (72 h) sperrt.
	var wieder := SoulService.pick_surprise(slice, _defs(), ctx, 0.0, 0.1)
	assert_true(wieder.is_empty(), "Cooldown nach Buchung")
	# Nach Ablauf des Cooldowns wieder möglich (Zeit hereingereicht).
	var ctx_spaet := _ctx(2026, 7, 30, 14)
	var spaeter := SoulService.pick_surprise(slice, _defs(), ctx_spaet, 0.0, 0.1)
	assert_eq(str(spaeter.get("id", "")), "sup_traum", "nach Cooldown wieder")


func test_geburtstags_nachfrage_nie_draengeln() -> void:
	var slice := _slice()
	var ctx := _ctx(2026, 7, 26, 14)
	slice["firstMetAt"] = int(ctx["now_ms"]) - 1 * MS_D
	assert_false(SoulService.should_ask_birthday(slice, ctx), "zu früh (Tag 1)")
	slice["firstMetAt"] = int(ctx["now_ms"]) - 5 * MS_D
	assert_true(SoulService.should_ask_birthday(slice, ctx), "ab Tag 3 okay")
	slice["askedBirthdayAt"] = int(ctx["now_ms"]) - 2 * MS_D
	assert_false(SoulService.should_ask_birthday(slice, ctx), "vor 7 Tagen gefragt")
	slice["askedBirthdayAt"] = int(ctx["now_ms"]) - 8 * MS_D
	assert_true(SoulService.should_ask_birthday(slice, ctx), "nach 7 Tagen wieder")
	slice["playerBirthday"] = {"month": 3, "day": 14}
	assert_false(SoulService.should_ask_birthday(slice, ctx), "Geburtstag bekannt = nie")


func test_tap_stufen() -> void:
	assert_eq(GoobyReactions.tap_stage(1), "tipp_kicher", "1. Tipp kichert")
	assert_eq(GoobyReactions.tap_stage(2), "", "2. Tipp still")
	assert_eq(GoobyReactions.tap_stage(3), "tipp_kitzlig", "3. Tipp kitzlig")
	assert_eq(GoobyReactions.tap_stage(6), "tipp_schwindelig", "6. Tipp schwindelig")

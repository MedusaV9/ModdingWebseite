extends TestCase
## FB-6/SEELE: Trigger-Logik — alles PURE, Zeit/Datum werden hereingereicht.
## Schwerpunkt laut DoD: deterministische Auslöser, Frequenzbremse,
## Jubiläums-/Geburtstagslogik über Datumssprünge.

const MS_H := 3_600_000
const MS_D := 86_400_000


func _date(year: int, month: int, day: int, hour := 12) -> Dictionary:
	return {"year": year, "month": month, "day": day, "hour": hour}


func test_daypart_grenzen() -> void:
	assert_eq(SoulTriggers.daypart(5), "morgen", "5 Uhr")
	assert_eq(SoulTriggers.daypart(10), "morgen", "10 Uhr")
	assert_eq(SoulTriggers.daypart(11), "mittag", "11 Uhr")
	assert_eq(SoulTriggers.daypart(14), "mittag", "14 Uhr")
	assert_eq(SoulTriggers.daypart(15), "nachmittag", "15 Uhr")
	assert_eq(SoulTriggers.daypart(18), "abend", "18 Uhr")
	assert_eq(SoulTriggers.daypart(22), "abend", "22 Uhr")
	assert_eq(SoulTriggers.daypart(23), "nacht", "23 Uhr")
	assert_eq(SoulTriggers.daypart(0), "nacht", "0 Uhr")
	assert_eq(SoulTriggers.daypart(4), "nacht", "4 Uhr")


func test_absence_kind_schwellen() -> void:
	assert_eq(SoulTriggers.absence_kind(0), "", "kein Gap")
	assert_eq(SoulTriggers.absence_kind(5 * MS_H), "", "unter 6 h")
	assert_eq(SoulTriggers.absence_kind(6 * MS_H), "gefreut", "genau 6 h")
	assert_eq(SoulTriggers.absence_kind(47 * MS_H), "gefreut", "unter 48 h")
	assert_eq(SoulTriggers.absence_kind(48 * MS_H), "eingeschnappt", "genau 48 h")
	assert_eq(SoulTriggers.absence_kind(7 * 24 * MS_H), "vermisst", "genau 7 Tage")
	assert_eq(SoulTriggers.absence_kind(30 * 24 * MS_H), "vermisst", "30 Tage")


func test_days_known() -> void:
	assert_eq(SoulTriggers.days_known(0, 5 * MS_D), 0, "firstMet 0 = unbekannt")
	assert_eq(SoulTriggers.days_known(10 * MS_D, 5 * MS_D), 0, "Uhr rückwärts = 0, kein Crash")
	assert_eq(SoulTriggers.days_known(MS_D, MS_D + 100 * MS_D), 100, "genau 100 Tage")
	assert_eq(SoulTriggers.days_known(MS_D, MS_D + 100 * MS_D - 1), 99, "kurz davor 99")


func test_jubilaeum_nur_am_meilenstein_datumssprung() -> void:
	assert_eq(SoulTriggers.anniversary_milestone(100), 100, "Tag 100 ist Meilenstein")
	assert_eq(SoulTriggers.anniversary_milestone(7), 7, "Tag 7 ist Meilenstein")
	# Datumssprung: Pause von Tag 95 bis Tag 103 — der 100er wird NICHT
	# nachgefeiert (kein Spam nach Pausen, bewusste Entscheidung).
	assert_eq(SoulTriggers.anniversary_milestone(103), 0, "übersprungener Meilenstein still")
	assert_eq(SoulTriggers.anniversary_milestone(0), 0, "Tag 0 nichts")
	assert_eq(SoulTriggers.anniversary_milestone(99), 0, "Tag 99 nichts")


func test_geburtstag_ueber_datumssprung() -> void:
	var birthday := {"month": 3, "day": 14}
	assert_true(SoulTriggers.is_birthday(birthday, _date(2026, 3, 14)), "Geburtstag 2026")
	assert_false(SoulTriggers.is_birthday(birthday, _date(2026, 3, 15)), "Tag danach nicht")
	# Datumssprung um ein ganzes Jahr: gleicher Monat/Tag zündet wieder.
	assert_true(SoulTriggers.is_birthday(birthday, _date(2027, 3, 14)), "Geburtstag 2027 wieder")
	assert_false(SoulTriggers.is_birthday({"month": 0, "day": 0}, _date(2026, 3, 14)), "ungesetzt")


func test_geburtstag_aus_ms() -> void:
	# 2026-07-26 12:00 UTC → Gooby-Geburtstag ist der Einzugstag.
	var ms := 1_785_067_200_000
	var birthday := SoulTriggers.birthday_from_ms(ms)
	assert_eq(int(birthday["month"]), 7, "Monat aus Einzugs-Stempel")
	assert_eq(int(birthday["day"]), 26, "Tag aus Einzugs-Stempel")


func test_ostern_gauss_bekannte_jahre() -> void:
	assert_eq(SoulTriggers.easter_month_day(2024), {"month": 3, "day": 31}, "Ostern 2024")
	assert_eq(SoulTriggers.easter_month_day(2025), {"month": 4, "day": 20}, "Ostern 2025")
	assert_eq(SoulTriggers.easter_month_day(2026), {"month": 4, "day": 5}, "Ostern 2026")
	assert_eq(SoulTriggers.easter_month_day(2027), {"month": 3, "day": 28}, "Ostern 2027")


func test_feiertage() -> void:
	assert_eq(SoulTriggers.holiday_for(_date(2026, 1, 1)), "neujahr", "Neujahr")
	assert_eq(SoulTriggers.holiday_for(_date(2026, 10, 31)), "halloween", "Halloween")
	assert_eq(SoulTriggers.holiday_for(_date(2026, 12, 6)), "nikolaus", "Nikolaus")
	assert_eq(SoulTriggers.holiday_for(_date(2026, 12, 24)), "heiligabend", "Heiligabend")
	assert_eq(SoulTriggers.holiday_for(_date(2026, 12, 25)), "weihnachten", "1. Weihnachtstag")
	assert_eq(SoulTriggers.holiday_for(_date(2026, 12, 26)), "weihnachten", "2. Weihnachtstag")
	assert_eq(SoulTriggers.holiday_for(_date(2026, 12, 31)), "silvester", "Silvester")
	assert_eq(SoulTriggers.holiday_for(_date(2026, 4, 5)), "ostern", "Ostersonntag 2026")
	assert_eq(SoulTriggers.holiday_for(_date(2026, 7, 26)), "", "normaler Tag")


func test_schnee_saison_ueber_jahreswechsel() -> void:
	# Dez 2026 + Jan/Feb 2027 sind EINE Saison → erster Schnee 1x pro Winter.
	assert_eq(SoulTriggers.snow_season(_date(2026, 12, 15)), "2026", "Dezember")
	assert_eq(SoulTriggers.snow_season(_date(2027, 1, 10)), "2026", "Januar danach")
	assert_eq(SoulTriggers.snow_season(_date(2027, 2, 28)), "2026", "Februar danach")
	assert_eq(SoulTriggers.snow_season(_date(2027, 12, 1)), "2027", "nächster Winter neu")


func test_frequenzbremse_mindestabstand() -> void:
	var ambient := {"day": "", "count": 0, "lastAt": 0}
	var now := 1_000_000_000
	assert_true(SoulTriggers.ambient_allowed(ambient, now, "2026-07-26"), "frisch = erlaubt")
	ambient = SoulTriggers.note_ambient(ambient, now, "2026-07-26")
	assert_false(
		SoulTriggers.ambient_allowed(ambient, now + 1_000, "2026-07-26"),
		"direkt danach gesperrt (Mindestabstand)"
	)
	assert_true(
		SoulTriggers.ambient_allowed(ambient, now + SoulTriggers.AMBIENT_MIN_GAP_MS, "2026-07-26"),
		"nach dem Mindestabstand wieder erlaubt"
	)


func test_frequenzbremse_tagesdeckel_und_neuer_tag() -> void:
	var ambient := {"day": "", "count": 0, "lastAt": 0}
	var now := 1_000_000_000
	for _i in SoulTriggers.AMBIENT_MAX_PER_DAY:
		assert_true(SoulTriggers.ambient_allowed(ambient, now, "2026-07-26"), "unter Deckel")
		ambient = SoulTriggers.note_ambient(ambient, now, "2026-07-26")
		now += SoulTriggers.AMBIENT_MIN_GAP_MS
	assert_false(SoulTriggers.ambient_allowed(ambient, now, "2026-07-26"), "Tagesdeckel erreicht")
	# Neuer Tag (auch nach Datumssprung): Zähler startet neu.
	assert_true(
		SoulTriggers.ambient_allowed(ambient, now + MS_D, "2026-07-28"),
		"neuer Tag setzt den Deckel zurück"
	)
	ambient = SoulTriggers.note_ambient(ambient, now + MS_D, "2026-07-28")
	assert_eq(int(ambient["count"]), 1, "Zähler beginnt am neuen Tag bei 1")


func test_celebrated_gate() -> void:
	var celebrated := {"geburtstag_spieler": "2026-03-14"}
	assert_true(
		SoulTriggers.celebrated_today(celebrated, "geburtstag_spieler", "2026-03-14"),
		"heute schon gefeiert"
	)
	assert_false(
		SoulTriggers.celebrated_today(celebrated, "geburtstag_spieler", "2027-03-14"),
		"nächstes Jahr wieder frei"
	)
	assert_false(SoulTriggers.celebrated_today(celebrated, "unbekannt", "2026-03-14"), "neu")


func test_zuhause_wetter_deterministisch() -> void:
	var a := SoulWetter.zustand("2026-07-26", 12.0)
	var b := SoulWetter.zustand("2026-07-26", 12.0)
	assert_eq(a, b, "gleicher Tag + Stunde = gleiches Wetter")
	assert_true(a.has("typ") and a.has("regen") and a.has("schnee"), "Formvertrag")


func test_winter_macht_schnee() -> void:
	# Im Winter wird JEDER Niederschlag zu Schnee (regen=false, schnee=true).
	for tag in ["2026-12-01", "2027-01-15", "2027-02-20"]:
		for stunde in 24:
			var zustand := SoulWetter.zustand(str(tag), float(stunde))
			assert_false(bool(zustand["regen"]), "kein Regen im Winter (%s %d h)" % [tag, stunde])
			if str(zustand["typ"]) == "schnee":
				assert_true(bool(zustand["schnee"]), "Schnee-Typ hat schnee=true")
	# Im Sommer gibt es nie Schnee.
	for stunde in 24:
		var sommer := SoulWetter.zustand("2026-07-26", float(stunde))
		assert_false(bool(sommer["schnee"]), "kein Schnee im Juli (%d h)" % stunde)

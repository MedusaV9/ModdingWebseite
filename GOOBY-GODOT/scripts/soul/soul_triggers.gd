class_name SoulTriggers
extends RefCounted
## Trigger-Logik der Seele (FB-6/SEELE) — PURE Statics, Zeit/Datum werden
## IMMER hereingereicht (Datumssprung-Tests!). Entscheidet deterministisch:
## Abwesenheits-Reaktion, Tageszeit-Gruß, Jubiläen („Wir kennen uns 100
## Tage!“), Geburtstage (Spieler UND Gooby), Feiertage (inkl. beweglichem
## Ostern nach Gauß) und die globale Frequenzbremse (nie aufdringlich).

const MS_PER_HOUR := 3_600_000
const MS_PER_DAY := 86_400_000

## Jubiläums-Meilensteine in Kennen-Tagen.
const MILESTONES: Array[int] = [7, 30, 50, 100, 200, 365, 500, 730, 1000]

## Frequenzbremse: ambiente Momente (Gruß/Wetter/Erinnerung/Kommentar)
## frühestens alle MIN_GAP, höchstens MAX_PER_DAY pro Tag. Rituale
## (Geburtstag/Jubiläum/Feiertag/erster Schnee) sind davon ausgenommen,
## feuern aber je Schlüssel höchstens 1× pro Tag (celebrated-Map).
const AMBIENT_MIN_GAP_MS := 90_000
const AMBIENT_MAX_PER_DAY := 12

## Abwesenheits-Schwellen (Task: freut sich / ist etwas eingeschnappt;
## Vernachlässigung = traurige Blicke, NIE Strafen).
const ABSENCE_HAPPY_H := 6.0
const ABSENCE_MIFFED_H := 48.0
const ABSENCE_MISSED_H := 168.0


## "YYYY-MM-DD" aus einem Godot-Datetime-Dict.
static func day_string(date: Dictionary) -> String:
	return (
		"%04d-%02d-%02d"
		% [int(date.get("year", 0)), int(date.get("month", 0)), int(date.get("day", 0))]
	)


## Tageszeit-Kategorie für Begrüßungen.
static func daypart(hour: int) -> String:
	if hour >= 5 and hour <= 10:
		return "morgen"
	if hour >= 11 and hour <= 14:
		return "mittag"
	if hour >= 15 and hour <= 17:
		return "nachmittag"
	if hour >= 18 and hour <= 22:
		return "abend"
	return "nacht"


## Abwesenheits-Kategorie aus der Besuchslücke: "" = normal weiter,
## "gefreut" (>6 h), "eingeschnappt" (>48 h, schnell versöhnt),
## "vermisst" (>7 Tage, große Freude + ein bisschen Wehmut).
static func absence_kind(gap_ms: int) -> String:
	var hours := float(gap_ms) / float(MS_PER_HOUR)
	if hours >= ABSENCE_MISSED_H:
		return "vermisst"
	if hours >= ABSENCE_MIFFED_H:
		return "eingeschnappt"
	if hours >= ABSENCE_HAPPY_H:
		return "gefreut"
	return ""


## Volle Kennen-Tage seit dem ersten Treffen (kalendertag-genau ist nicht
## nötig — 24-h-Fenster reichen und sind sprungfest).
static func days_known(first_met_ms: int, now_ms: int) -> int:
	if first_met_ms <= 0 or now_ms < first_met_ms:
		return 0
	return int(float(now_ms - first_met_ms) / float(MS_PER_DAY))


## Beziehungs-Stufe (SEELE-2): färbt Grüße/Texte — Gooby redet mit einem
## Menschen, den er 100 Tage kennt, anders als am dritten Tag.
static func beziehung_stufe(days: int) -> String:
	if days >= 50:
		return "beste_freunde"
	if days >= 7:
		return "vertraut"
	return "neu"


## Meilenstein, der GENAU heute erreicht ist (0 = keiner). „Heute erreicht“
## heißt: days_known trifft den Meilenstein — über Datumssprünge hinweg wird
## ein verpasster Meilenstein NICHT nachgefeiert (kein Spam nach Pausen),
## dafür sorgt der celebrated-Schlüssel je Meilenstein zusätzlich.
static func anniversary_milestone(days: int) -> int:
	return days if MILESTONES.has(days) else 0


## Geburtstag {month, day} aus einem Unix-ms-Zeitstempel (Goobys Geburtstag =
## Einzugstag, meta.createdAt).
static func birthday_from_ms(ms: int) -> Dictionary:
	var date := Time.get_datetime_dict_from_unix_time(int(ms / 1000.0))
	return {"month": int(date["month"]), "day": int(date["day"])}


static func is_birthday(birthday: Dictionary, date: Dictionary) -> bool:
	var month := int(birthday.get("month", 0))
	var day := int(birthday.get("day", 0))
	if month <= 0 or day <= 0:
		return false
	return int(date.get("month", 0)) == month and int(date.get("day", 0)) == day


## Ostersonntag (Monat, Tag) nach der Gauß-Osterformel — beweglicher
## Feiertag, deterministisch pro Jahr, headless testbar.
static func easter_month_day(year: int) -> Dictionary:
	var a := year % 19
	var b := int(year / 100.0)
	var c := year % 100
	var d := int(b / 4.0)
	var e := b % 4
	var f := int((b + 8) / 25.0)
	var g := int((b - f + 1) / 3.0)
	var h := (19 * a + b - d - g + 15) % 30
	var i := int(c / 4.0)
	var k := c % 4
	var l := (32 + 2 * e + 2 * i - h - k) % 7
	var m := int((a + 11 * h + 22 * l) / 451.0)
	var month := int((h + l - 7 * m + 114) / 31.0)
	var day := ((h + l - 7 * m + 114) % 31) + 1
	return {"month": month, "day": day}


## Feiertags-Id für ein Datum ("" = keiner). Feste Tage + Gauß-Ostern.
static func holiday_for(date: Dictionary) -> String:
	var month := int(date.get("month", 0))
	var day := int(date.get("day", 0))
	match [month, day]:
		[1, 1]:
			return "neujahr"
		[10, 31]:
			return "halloween"
		[12, 6]:
			return "nikolaus"
		[12, 24]:
			return "heiligabend"
		[12, 25], [12, 26]:
			return "weihnachten"
		[12, 31]:
			return "silvester"
	var easter := easter_month_day(int(date.get("year", 0)))
	if month == int(easter["month"]) and day == int(easter["day"]):
		return "ostern"
	return ""


## Saison-Schlüssel für den „ersten Schnee“: ein Winter läuft über den
## Jahreswechsel (Dez 2026 + Jan/Feb 2027 = Saison "2026"), damit der erste
## Schnee GENAU 1× pro Winter gefeiert wird.
static func snow_season(date: Dictionary) -> String:
	var year := int(date.get("year", 0))
	var month := int(date.get("month", 0))
	return str(year if month == 12 else year - 1)


## Globale Frequenzbremse für ambiente Momente: Mindestabstand + Tagesdeckel.
static func ambient_allowed(ambient: Dictionary, now_ms: int, today: String) -> bool:
	var last := int(ambient.get("lastAt", 0))
	if last > 0 and now_ms - last < AMBIENT_MIN_GAP_MS:
		return false
	var count := int(ambient.get("count", 0)) if str(ambient.get("day", "")) == today else 0
	return count < AMBIENT_MAX_PER_DAY


## Buchung eines ambienten Moments (neuer Tag setzt den Zähler zurück).
static func note_ambient(ambient: Dictionary, now_ms: int, today: String) -> Dictionary:
	var count := int(ambient.get("count", 0)) if str(ambient.get("day", "")) == today else 0
	return {"day": today, "count": count + 1, "lastAt": now_ms}


## Ritual-Gate: Schlüssel heute schon gefeiert? (celebrated: {key: "YYYY-MM-DD"}
## bzw. {key: saison} beim ersten Schnee — der Vergleichswert kommt herein.)
static func celebrated_today(celebrated: Dictionary, key: String, stamp: String) -> bool:
	return str(celebrated.get(key, "")) == stamp

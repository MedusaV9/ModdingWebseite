class_name NotifyRules
extends RefCounted
## RW-7 — pure Regeln des Benachrichtigungsdienstes (Doc §3.4 Produktregeln):
## Kategorie-Zuordnung über ID-Präfixe (auch für Alt-Aufrufer, die direkt
## `NotifyStub.schedule_local` nutzen), Ruhezeiten-Fenster und das
## Verschieben fälliger Meldungen in die nächste erlaubte Zeit.
##
## Kategorien (Settings-Gates `notifications.<kategorie>`):
##   pflege  — Pflege-Erinnerung (Gooby/Pferd braucht etwas)
##   warte   — Warte-Quest fertig (rquest_*, liveact_*)
##   fohlen  — Fohlen geboren
##   turnier — Turniertag
##   freund  — Freund besucht/Soziales

const KATEGORIEN: Array[String] = ["pflege", "warte", "fohlen", "turnier", "freund"]
## ID-Präfix → Kategorie. Bestehende Aufrufer (rquest_warte.gd,
## ranch_live_activity.gd, random_events.gd) bleiben unangefasst und werden
## über ihre Präfixe einsortiert.
const PREFIX_KATEGORIE := {
	"pflege_": "pflege",
	"event_": "pflege",
	"rquest_": "warte",
	"liveact_": "warte",
	"warte_": "warte",
	"fohlen_": "fohlen",
	"turnier_": "turnier",
	"freund_": "freund",
}


## Kategorie einer Notification-ID ("" = System/unbekannt, nur Master-Gate).
static func category_of_id(id: String) -> String:
	for prefix: String in PREFIX_KATEGORIE:
		if id.begins_with(prefix):
			return PREFIX_KATEGORIE[prefix]
	return ""


## Liegt die Stunde im Ruhefenster? Fenster darf über Mitternacht gehen
## (Default 21 → 8). from == to bedeutet: kein Fenster.
static func in_quiet_hours(hour: int, from_h: int, to_h: int) -> bool:
	if from_h == to_h:
		return false
	if from_h < to_h:
		return hour >= from_h and hour < to_h
	return hour >= from_h or hour < to_h


## Zeitstempel (Unix-ms) in die nächste erlaubte Zeit verschieben:
## innerhalb der Ruhezeit → auf to_h:00 des passenden Tages, sonst
## unverändert. `utc_offset_min` = lokale Zeitzone (Minuten).
static func defer_out_of_quiet(at_ms: int, from_h: int, to_h: int, utc_offset_min: int) -> int:
	var local_s := int(at_ms / 1000.0) + utc_offset_min * 60
	var seconds_of_day := int(posmod(local_s, 86400))
	var hour := int(seconds_of_day / 3600.0)
	if not in_quiet_hours(hour, from_h, to_h):
		return at_ms
	var target_s := to_h * 3600
	var delta := target_s - seconds_of_day
	if delta <= 0:
		delta += 86400
	return at_ms + delta * 1000


## Komplette Zustellentscheidung für einen fälligen Eintrag:
## {"action": "zeigen"|"verwerfen"|"verschieben", "at_ms": int}.
## settings wird duck-typed gelesen (AppSettings-API notify_allowed/is_on/
## value_of) — null = alles erlauben (Tests ohne Settings).
static func decide(entry: Dictionary, now_ms: int, settings: Object) -> Dictionary:
	var id := str(entry.get("id", ""))
	var category := category_of_id(id)
	if settings != null:
		if not settings.is_on("notifications.enabled"):
			return {"action": "verwerfen", "at_ms": 0}
		if not category.is_empty() and not settings.notify_allowed(category):
			return {"action": "verwerfen", "at_ms": 0}
		if settings.is_on("notifications.quiet_hours"):
			var from_h := int(settings.value_of("notifications.quiet_from"))
			var to_h := int(settings.value_of("notifications.quiet_to"))
			var offset_min := local_utc_offset_min()
			var deferred := defer_out_of_quiet(now_ms, from_h, to_h, offset_min)
			if deferred > now_ms:
				return {"action": "verschieben", "at_ms": deferred}
	return {"action": "zeigen", "at_ms": now_ms}


## Lokaler UTC-Offset in Minuten (headless-sicher).
static func local_utc_offset_min() -> int:
	var bias: Variant = Time.get_time_zone_from_system().get("bias", 0)
	return int(bias)

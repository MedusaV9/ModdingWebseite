class_name MorgenRitual
extends RefCounted
## Morgen-Ritual-Logik (G8/IDEA-SEELE, Idee 1 — PURE Hälfte): entscheidet,
## ob beim ersten Öffnen des Tages die kurze Aufwach-Klammer spielt
## (Licht-Sweep + Strecken + EIN warmer Tages-Gruß), und baut den Gruß aus
## ECHTEN Tagesdaten (Wetter aus SoulWetter, anstehende Tagesquest,
## Markttag aus dem Orte-Katalog). Zeit/Zufall werden IMMER hereingereicht
## (AGENTS.md-Regel) — headless testbar mit injizierter Uhr.
##
## Die Bühne (Tween/Bubble/Skip) orchestriert scripts/home/morgen_sequenz.gd;
## hier leben nur Entscheidungen und Daten:
##  - plan(): die Morgen-KETTE in fester Folge (Ritual? → Bonus → Guide) —
##    genau die Entzerrung des PT4-B7/PT1-B6-Overlay-Staus. Bonus/Guide
##    stehen IMMER im Plan (sie gaten sich zur Laufzeit selbst über
##    should_offer/attach_to) — nur das Ritual entscheidet sich hier.
##  - faellig(): einmal pro Tag (celebrated-Gate), nur morgens (5–11 Uhr),
##    nicht an Goobys Einzugstag (Tag 0 gehört der Guide-Ankunft), nicht
##    während Gooby schläft (das Aufwachen gehört dem PflegeRunner).
##  - stempeln(): bucht Gate + Gruß-Tag + Ambient-Bremse VOR der Ankunft —
##    GoobyReactions._run_enter sieht lastGreetDay == heute und grüßt nicht
##    doppelt, die 90-s-Bremse hält Wetter-/Erinnerungs-Bubbles fern.

const Sleep := preload("res://scripts/logic/sleep.gd")

## celebrated-Schlüssel (einmal pro Tag) und lastGreetKind-Stempel.
const GATE_KEY := "morgen_ritual"
## Ritual-Fenster: lokale Stunde [von, bis).
const STUNDE_VON := 5
const STUNDE_BIS := 11
## Ketten-Schritte (Reihenfolge = Anzeige-Reihenfolge, nie gestapelt).
const SCHRITT_RITUAL := "ritual"
const SCHRITT_BONUS := "bonus"
const SCHRITT_GUIDE := "guide"
## Höchstens so viele Gruß-Zeilen (Gruß + Wetter + EIN Ausblick).
const MAX_ZEILEN := 3


## Die Morgen-Kette in fester Folge. ctx: {now_ms, heute, stunde}.
static func plan(state: Dictionary, ctx: Dictionary) -> Array[String]:
	var schritte: Array[String] = []
	if faellig(state, ctx):
		schritte.append(SCHRITT_RITUAL)
	schritte.append(SCHRITT_BONUS)
	schritte.append(SCHRITT_GUIDE)
	return schritte


## Spielt die Aufwach-Klammer heute? Deterministisch aus State + ctx
## ({now_ms, heute: "YYYY-MM-DD", stunde: 0..23}).
static func faellig(state: Dictionary, ctx: Dictionary) -> bool:
	var onboarding: Variant = state.get("onboarding", {})
	if not (onboarding is Dictionary) or not bool((onboarding as Dictionary).get("done", false)):
		return false
	var stunde := int(ctx.get("stunde", 12))
	if stunde < STUNDE_VON or stunde >= STUNDE_BIS:
		return false
	var slice := SoulState.normalize_slice(state.get("soul"))
	if SoulTriggers.celebrated_today(slice["celebrated"], GATE_KEY, str(ctx.get("heute", ""))):
		return false
	# Tag 0 = Einzugstag: die Ankunft inszeniert der OnboardingGuide.
	if SoulTriggers.days_known(int(slice["firstMetAt"]), int(ctx.get("now_ms", 0))) < 1:
		return false
	# Eingeschnappt/vermisst nach langer Lücke: der Abwesenheits-Gruß der
	# Seele gewinnt — ein fröhliches „Guten Morgen“ würde das Schmollen
	# überspielen.
	var letzter := int(slice["lastVisitAt"])
	var luecke := maxi(0, int(ctx.get("now_ms", 0)) - letzter) if letzter > 0 else 0
	var art := SoulTriggers.absence_kind(luecke)
	if art == "eingeschnappt" or art == "vermisst":
		return false
	# Schläft Gooby noch, gehört das Aufwachen dem PflegeRunner
	# (wake_morning-Cutscene) — keine zweite Inszenierung darüber.
	return not Sleep.is_sleeping(Sleep.flat_of(state))


## Einmal-pro-Tag-Buchung (mutiert die hereingereichte Slice-Kopie — Muster
## SoulService.book_enter; der Aufrufer persistiert via SoulState.mutate).
static func stempeln(slice: Dictionary, ctx: Dictionary) -> void:
	var heute := str(ctx.get("heute", ""))
	var now_ms := int(ctx.get("now_ms", 0))
	slice["celebrated"][GATE_KEY] = heute
	slice["lastGreetDay"] = heute
	slice["lastGreetKind"] = GATE_KEY
	slice["ambient"] = SoulTriggers.note_ambient(slice["ambient"], now_ms, heute)
	slice["totalMoments"] = int(slice.get("totalMoments", 0)) + 1


## Gruß-Zeilen [{key, args}] aus echten Tagesdaten. ctx:
## {player_name, wetter: {typ,...}, markt_heute: bool, quest_titel: String}.
## Deckel MAX_ZEILEN: Gruß + Wetter immer, dann EIN Ausblick — der seltene
## Markttag gewinnt gegen die (fast tägliche) Quest-Zeile.
static func begruessung(ctx: Dictionary) -> Array[Dictionary]:
	var zeilen: Array[Dictionary] = []
	var player_name := str(ctx.get("player_name", ""))
	var namek := (", " + player_name) if not player_name.is_empty() else ""
	zeilen.append({"key": "seele_tag.morgen.gruss", "args": {"namek": namek}})
	var wetter: Variant = ctx.get("wetter", {})
	var typ := str((wetter as Dictionary).get("typ", "sonne")) if wetter is Dictionary else "sonne"
	zeilen.append({"key": "seele_tag.morgen.wetter." + typ, "args": {}})
	if bool(ctx.get("markt_heute", false)):
		zeilen.append({"key": "seele_tag.morgen.markt", "args": {}})
	var quest := str(ctx.get("quest_titel", ""))
	if not quest.is_empty() and zeilen.size() < MAX_ZEILEN:
		zeilen.append({"key": "seele_tag.morgen.quest", "args": {"quest": quest}})
	return zeilen


## Lokale Datetime aus Epoch-ms — dieselbe Offset-Regel wie Clock.local_day
## (OS-Bias, außer der Test reicht `offset_min` herein).
static func lokale_zeit(now_ms: int, offset_min: Variant = null) -> Dictionary:
	var offset: int = (
		int(offset_min)
		if offset_min is int or offset_min is float
		else int(Time.get_time_zone_from_system().get("bias", 0))
	)
	var local_secs := int(floor(now_ms / 1000.0)) + offset * 60
	return Time.get_datetime_dict_from_unix_time(local_secs)

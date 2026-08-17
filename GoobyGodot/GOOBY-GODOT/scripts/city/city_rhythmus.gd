class_name CityRhythmus
extends RefCounted
## Rhythmus-Schicht der Stadt (W18/J4 „Stadt-Tagesrhythmus", Idee I-07):
## PURE + headless-testbar — die EINE Quelle für „wie lebendig ist die
## Stadt zur Stunde X?". Tagesphasen (morgen/mittag/abend/nacht),
## Dichte-Kurven für Verkehr und Fußgänger (stückweise linear zwischen
## Anker-Stunden, 24-h-Wrap), der Anteil leuchtender Fenster (tief in der
## Nacht schlafen die meisten Goobys) und die Uhrzeit aus der INJIZIERTEN
## GameState-Clock (AGENTS-Regel: Zeit wird injiziert — der DEV-Zeit-
## Override pinnt genau diese Uhr, damit ist alles deterministisch
## testbar). CityScene wendet die Ziele mit weichen Übergängen an
## (Skalen-Fade, Reduced-Motion = sofort); hier stehen nur ZAHLEN.

## Phasen-Grenzen (Stunde): nacht → morgen → mittag → abend → nacht.
const MORGEN_AB := 5.0
const MITTAG_AB := 10.0
const ABEND_AB := 17.0
const NACHT_AB := 22.0

## Dichte-Anker (Stunde → Anzahl), dazwischen linear, hinter dem letzten
## Anker bis 24 h konstant weiter (Nacht-Niveau = erster Anker, 24-h-Wrap).
## Endpunkte decken die eingespielten Konstanten: mittags TAG_AUTOS = 9 /
## TAG_ANZAHL = 11, nachts NACHT_AUTOS = 3 / NACHT_ANZAHL = 4.
const VERKEHR_ANKER: Array[Vector2] = [
	Vector2(0.0, 3.0),
	Vector2(5.0, 3.0),
	Vector2(8.0, 5.0),
	Vector2(11.0, 9.0),
	Vector2(16.0, 9.0),
	Vector2(19.0, 7.0),
	Vector2(22.0, 3.0),
]
const FUSSGAENGER_ANKER: Array[Vector2] = [
	Vector2(0.0, 4.0),
	Vector2(5.0, 4.0),
	Vector2(8.0, 6.0),
	Vector2(11.0, 11.0),
	Vector2(16.0, 11.0),
	Vector2(19.0, 8.0),
	Vector2(22.0, 4.0),
]

## Anteil leuchtender Fenster tief in der Nacht (die meisten schlafen).
const FENSTER_TIEFNACHT_ANTEIL := 0.35
const TIEFNACHT_AB := 23.0
const TIEFNACHT_BIS := 5.0

## Weicher Übergang beim Ein-/Ausblenden von Autos/Goobys (s); Reduced
## Motion schaltet stattdessen sofort.
const UEBERGANG_S := 1.2

## So oft prüft CityScene die Rhythmus-Ziele (s) — die Uhr kriecht,
## häufiger lohnt nicht (Low-End-Budget: kein Datetime-Dict pro Frame).
const TICK_S := 0.5


## Tagesphase zur Stunde: "morgen" | "mittag" | "abend" | "nacht".
static func phase(stunde: float) -> String:
	var s := fposmod(stunde, 24.0)
	if s < MORGEN_AB or s >= NACHT_AB:
		return "nacht"
	if s < MITTAG_AB:
		return "morgen"
	if s < ABEND_AB:
		return "mittag"
	return "abend"


## Wie viele Ambient-Autos fahren zur Stunde? (morgens ruhig, mittags
## voll, abends golden-belebt, nachts nur Nachtschwärmer.)
static func verkehr_anzahl(stunde: float) -> int:
	return roundi(_kurve(VERKEHR_ANKER, stunde))


## Wie viele Fußgänger-Goobys schlendern zur Stunde?
static func fussgaenger_anzahl(stunde: float) -> int:
	return roundi(_kurve(FUSSGAENGER_ANKER, stunde))


## Flotten-Maximum über den Tag (CityScene baut EINMAL so viele Wagen und
## blendet dann nur noch — kein Instanzieren im Rhythmus-Tick).
static func verkehr_max() -> int:
	return _kurven_max(VERKEHR_ANKER)


static func fussgaenger_max() -> int:
	return _kurven_max(FUSSGAENGER_ANKER)


## Morgens liest ein Gooby Zeitung an seiner Schaufenster-Pause.
static func zeitungs_gooby_aktiv(stunde: float) -> bool:
	return phase(stunde) == "morgen"


## Anteil der gebauten Nacht-Fenster, der wirklich leuchtet: 0 solange die
## Lichter aus sind, voll am Abend, tief in der Nacht nur noch wenige.
static func fenster_anteil(stunde: float) -> float:
	if not CityAmbiente.lichter_an(stunde):
		return 0.0
	var s := fposmod(stunde, 24.0)
	if s >= TIEFNACHT_AB or s < TIEFNACHT_BIS:
		return FENSTER_TIEFNACHT_ANTEIL
	return 1.0


## Uhrzeit mit Bruchteilen aus einer Epoch-ms-Zeit (LOKAL über den
## injizierten Zeitzonen-Offset in Minuten, wie Clock.local_day) — PURE.
static func stunde_von_ms(now_ms: int, bias_min: int) -> float:
	var lokal_s := int(floor(now_ms / 1000.0)) + bias_min * 60
	var d := Time.get_datetime_dict_from_unix_time(lokal_s)
	return float(d["hour"]) + float(d["minute"]) / 60.0 + float(d["second"]) / 3600.0


static func _kurven_max(anker: Array[Vector2]) -> int:
	var top := 0.0
	for punkt in anker:
		top = maxf(top, punkt.y)
	return roundi(top)


## Stückweise lineare Kurve über die Anker (x = Stunde, y = Wert); nach dem
## letzten Anker bleibt der Wert bis zum 24-h-Wrap auf dem letzten Niveau.
static func _kurve(anker: Array[Vector2], stunde: float) -> float:
	var s := fposmod(stunde, 24.0)
	var letzte := anker[anker.size() - 1]
	if s >= letzte.x:
		return letzte.y
	if s <= anker[0].x:
		return anker[0].y
	for i in range(1, anker.size()):
		if s <= anker[i].x:
			var a := anker[i - 1]
			var b := anker[i]
			var t := (s - a.x) / maxf(0.0001, b.x - a.x)
			return lerpf(a.y, b.y, t)
	return letzte.y

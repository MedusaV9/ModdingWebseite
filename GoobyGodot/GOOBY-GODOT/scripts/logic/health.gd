extends RefCounted
## Krankheits-Zustandsmaschine — Port von GOOBY/src/systems/health.js (§B5/§C3).
##
## Zustaende in Eskalations-Reihenfolge: healthy → queasy → sick. Aufwaerts nie
## eine Stufe ueberspringen (EIN Uebergang pro Tick); Heilungen springen runter.
## Alle Funktionen sind PURE Slice-in/Slice-out auf dem `gooby.health`-Slice
## {state, junkScore, neglectMin, recoverMin, since} (+ tummyWarnPending
## intern) — sie liefern NEUE Dictionaries und mutieren nie ihre Eingabe.
##
## REST-3-Erweiterung (additiv, Web-Parity bleibt bei Default-Optionen exakt):
## zwei zusaetzliche Ausloeser-Zaehler im Slice —
##   tiredMin: Minuten am Stueck erschoepft wach (energy <= 15, §C1) — "zu
##             wenig Schlaf" macht erst kraenklich, dann krank.
##   chillMin: Minuten am Stueck durchgefroren (Regen/Gewitter/Schnee bei
##             niedriger Hygiene) — "Kaelte" als Ausloeser.
## Beide Zaehler setzen sich (wie neglectMin im Web) sofort zurueck, wenn die
## Bedingung endet — Krankheit ist nie eine Strafe, nur eine Folge.
##
## Zusaetzlich hier (weil health.gd der eine Pflege-Logikort ist): die puren
## v5-State-Transformationen fuer Medizin (Web economy.useMedicine) und
## Tierarzt (Web economy.payVet, VET-Konstanten aus data/constants.js).

const Stats := preload("res://scripts/logic/stats.gd")
const Economy := preload("res://scripts/logic/economy.gd")

const STATES: Array[String] = ["healthy", "queasy", "sick"]

## on_eat: Junkfood addiert +1 junkScore (§B5).
const JUNK_EAT := 1.0
## on_eat: gesundes Essen subtrahiert 0.5 junkScore, Boden bei 0 (§B5).
const HEALTHY_EAT := -0.5
## Tick-Zerfall: junkScore −1 pro 120 min (§B5).
const JUNK_DECAY_PER_MIN := 1.0 / 120.0
## neglectMin waechst, solange >= 2 Stats < 15 sind (§B5).
const NEGLECT_MIN_STATS := 2
const NEGLECT_STAT_BELOW := 15.0
## healthy → queasy bei junkScore >= 5 (§B5).
const QUEASY_JUNK := 5.0
## healthy → queasy bei neglectMin >= 120 (§B5).
const QUEASY_NEGLECT_MIN := 120.0
## queasy → sick bei junkScore >= 8 (§B5).
const SICK_JUNK := 8.0
## queasy → sick bei neglectMin >= 360 (§B5).
const SICK_NEGLECT_MIN := 360.0
## queasy → healthy nach 60 durchgehend sauberen Minuten (§B5).
const RECOVER_MIN := 60.0
## "Sauber" verlangt junkScore < 3 (und alle Druck-Zaehler auf 0) (§B5).
const RECOVER_JUNK_BELOW := 3.0
## Warnrampe (§C3.2): junkScore erreicht 4 → 'tummyWarning'.
const WARN_JUNK := 4.0
## Queasy-Effekt (§C3.3): fun verfaellt x1.25 (wendet der Ticker an).
const QUEASY_FUN_DECAY_MULT := 1.25
## REST-3 (additiv): Erschoepfungs-Druck — healthy→queasy / queasy→sick.
const TIRED_QUEASY_MIN := 240.0
const TIRED_SICK_MIN := 720.0
## REST-3 (additiv): Kaelte-Druck — healthy→queasy / queasy→sick.
const CHILL_QUEASY_MIN := 180.0
const CHILL_SICK_MIN := 540.0

## Tierarzt (Web data/constants.js VET): Vollheilung 120 c (+10 alle Stats),
## Check-up 30 c (neglectMin-Reset).
const VET_CURE_PRICE := 120
const VET_CURE_STAT_BONUS := 10.0
const VET_CHECKUP_PRICE := 30


## Normalisierte Kopie eines health-Slices (fehlende Felder → §B2-Defaults).
static func normalize(h: Variant) -> Dictionary:
	var src: Dictionary = h if h is Dictionary else {}
	var state := str(src.get("state", "healthy"))
	if not STATES.has(state):
		state = "healthy"
	return {
		"state": state,
		"junkScore": maxf(0.0, _num(src.get("junkScore"))),
		"neglectMin": maxf(0.0, _num(src.get("neglectMin"))),
		"recoverMin": maxf(0.0, _num(src.get("recoverMin"))),
		"since": maxf(0.0, _num(src.get("since"))),
		"tiredMin": maxf(0.0, _num(src.get("tiredMin"))),
		"chillMin": maxf(0.0, _num(src.get("chillMin"))),
		"tummyWarnPending": _truthy(src.get("tummyWarnPending")),
	}


## Fuetterung auf den Slice anwenden (§B5). Pure — neuer Slice.
## Junk: junkScore +1 UND das 60-min-Erholungsfenster startet neu;
## gesund: junkScore −0.5 (Boden 0). Zustandswechsel passieren nur in tick().
static func on_eat(h: Variant, junk: bool) -> Dictionary:
	var s := normalize(h)
	if junk:
		var before: float = s["junkScore"]
		s["junkScore"] = before + JUNK_EAT
		s["recoverMin"] = 0.0
		if s["state"] == "healthy" and before < WARN_JUNK and float(s["junkScore"]) >= WARN_JUNK:
			s["tummyWarnPending"] = true
	else:
		s["junkScore"] = maxf(0.0, float(s["junkScore"]) + HEALTHY_EAT)
	return s


## Krankheits-Maschine um dt_min Minuten vorruecken (§B5). Pure — liefert
## {"h": Dictionary, "events": Array[String]}.
##
## Pro Tick: junkScore zerfaellt 1/120 min; neglectMin +1/min solange
## low_stat_count >= 2, sonst Reset auf 0; tiredMin/chillMin analog ueber
## opts.exhausted/opts.chill. Das queasy-Erholungsfenster (junk < 3 und alle
## Druck-Zaehler 0) laeuft auf 60 min zu und bricht sofort ab, wenn die
## Bedingung reisst. Danach EIN Uebergang: healthy→queasy ('becameQueasy'),
## queasy→sick ('becameSick'), queasy→healthy ('recovered'). sick heilt NIE
## von selbst — nur Medizin/Tierarzt.
## Offline-Sim (§E4): Aufrufer geben opts.mult = 0.3 und deckeln dt_min
## selbst bei 480 Sim-Minuten (gleicher Vertrag wie Stats.apply_tick).
static func tick(
	h: Variant, dt_min: float, low_stat_count: int, opts: Dictionary = {}
) -> Dictionary:
	var s := normalize(h)
	var events: Array = []
	var mult := _num_or(opts.get("mult"), 1.0)
	var eff_min := maxf(0.0, dt_min) * mult

	s["junkScore"] = maxf(0.0, float(s["junkScore"]) - eff_min * JUNK_DECAY_PER_MIN)
	if low_stat_count >= NEGLECT_MIN_STATS:
		s["neglectMin"] = float(s["neglectMin"]) + eff_min
	else:
		s["neglectMin"] = 0.0
	if _truthy(opts.get("exhausted")):
		s["tiredMin"] = float(s["tiredMin"]) + eff_min
	else:
		s["tiredMin"] = 0.0
	if _truthy(opts.get("chill")):
		s["chillMin"] = float(s["chillMin"]) + eff_min
	else:
		s["chillMin"] = 0.0
	var clean: bool = (
		float(s["junkScore"]) < RECOVER_JUNK_BELOW
		and float(s["neglectMin"]) == 0.0
		and float(s["tiredMin"]) == 0.0
		and float(s["chillMin"]) == 0.0
	)
	if s["state"] == "queasy" and clean:
		s["recoverMin"] = float(s["recoverMin"]) + eff_min
	else:
		s["recoverMin"] = 0.0

	var from: String = s["state"]
	if from == "healthy":
		if _queasy_due(s):
			s["state"] = "queasy"
			events.append("becameQueasy")
	elif from == "queasy":
		if _sick_due(s):
			s["state"] = "sick"
			s["recoverMin"] = 0.0
			events.append("becameSick")
		elif float(s["recoverMin"]) >= RECOVER_MIN:
			s["state"] = "healthy"
			s["recoverMin"] = 0.0
			events.append("recovered")

	if s["state"] != from and opts.has("now_ms"):
		s["since"] = _num(opts.get("now_ms"))

	if _truthy(s.get("tummyWarnPending")):
		s["tummyWarnPending"] = false
		if s["state"] == "healthy":
			events.append("tummyWarning")
	return {"h": s, "events": events}


static func _queasy_due(s: Dictionary) -> bool:
	return (
		float(s["junkScore"]) >= QUEASY_JUNK
		or float(s["neglectMin"]) >= QUEASY_NEGLECT_MIN
		or float(s["tiredMin"]) >= TIRED_QUEASY_MIN
		or float(s["chillMin"]) >= CHILL_QUEASY_MIN
	)


static func _sick_due(s: Dictionary) -> bool:
	return (
		float(s["junkScore"]) >= SICK_JUNK
		or float(s["neglectMin"]) >= SICK_NEGLECT_MIN
		or float(s["tiredMin"]) >= TIRED_SICK_MIN
		or float(s["chillMin"]) >= CHILL_SICK_MIN
	)


## Eine Medizin anwenden (§B5/§C3.5): sick → queasy, queasy → healthy.
## ok=false solange healthy (Aufrufer darf das Item dann NICHT verbrauchen).
## Zaehler werden NICHT zurueckgesetzt — das ist der Tierarzt-Job.
static func use_medicine(h: Variant, now_ms := 0) -> Dictionary:
	var s := normalize(h)
	if s["state"] == "healthy":
		return {"h": s, "ok": false}
	s["state"] = "queasy" if s["state"] == "sick" else "healthy"
	s["recoverMin"] = 0.0
	if now_ms > 0:
		s["since"] = now_ms
	return {"h": s, "ok": true}


## Tierarzt-Vollheilung (§B5/§C3.5): jeder Zustand → healthy; alle
## Druck-Zaehler auf 0. Der +10-Stat-Bonus laeuft ueber pay_vet (nie hier).
static func vet_cure(h: Variant, now_ms := 0) -> Dictionary:
	var s := normalize(h)
	if s["state"] != "healthy" and now_ms > 0:
		s["since"] = now_ms
	s["state"] = "healthy"
	s["junkScore"] = 0.0
	s["neglectMin"] = 0.0
	s["recoverMin"] = 0.0
	s["tiredMin"] = 0.0
	s["chillMin"] = 0.0
	s["tummyWarnPending"] = false
	return s


## Tierarzt-Check-up (§C3.5): neglectMin (und die additiven Druck-Zaehler)
## auf 0; sonst aendert sich nichts.
static func vet_checkup(h: Variant) -> Dictionary:
	var s := normalize(h)
	s["neglectMin"] = 0.0
	s["tiredMin"] = 0.0
	s["chillMin"] = 0.0
	return s


## Minispiel-Gate (§C3.4): Spiele lehnen NUR bei sick ab — sanft, nie hart
## (queasy Gooby spielt weiter; der Aufrufer zeigt eine freundliche Zeile).
static func can_play_minigame(h: Variant) -> bool:
	return normalize(h)["state"] != "sick"


## Krankheitsgrad fuers Modell/UI: 0 = healthy, 1 = queasy, 2 = sick.
static func grade(h: Variant) -> int:
	return STATES.find(str(normalize(h)["state"]))


## Wie viele der 4 Stats liegen unter der Vernachlaessigungs-Schwelle (< 15)?
static func low_stat_count(stats: Dictionary) -> int:
	var count := 0
	for k in Stats.KEYS:
		if _num(stats.get(k)) < NEGLECT_STAT_BELOW:
			count += 1
	return count


# ── v5-State-Transformationen (Medizin/Tierarzt, Web economy.js) ─────────────


## Eine Medizin aus dem Inventar geben (Web economy.useMedicine): verbraucht
## items.medicine −1, health-Slice-Uebergang, medsGiven/cures-Zaehler.
## Mutiert `state` in place (im gs.update laufen lassen).
## Rueckgabe {"ok": bool, "reason": ""|"none"|"healthy"}.
static func use_medicine_state(state: Dictionary, now_ms: int) -> Dictionary:
	var items: Dictionary = _dict(_dict(state.get("inventory")).get("items"))
	if int(_num(items.get("medicine"))) < 1:
		return {"ok": false, "reason": "none"}
	var gooby := _dict(state.get("gooby"))
	var res := use_medicine(gooby.get("health"), now_ms)
	if not bool(res["ok"]):
		return {"ok": false, "reason": "healthy"}
	items["medicine"] = int(_num(items.get("medicine"))) - 1
	gooby["health"] = res["h"]
	var counters := _counters(state)
	counters["medsGiven"] = int(_num(counters.get("medsGiven"))) + 1
	counters["cures"] = int(_num(counters.get("cures"))) + 1
	return {"ok": true, "reason": ""}


## Tierarzt bezahlen (Web economy.payVet): kind = "cure" (120 c, nur wenn
## queasy/sick; Vollheilung + +10 alle Stats + cures-Zaehler) oder "checkup"
## (30 c, jederzeit; neglect-Reset). Mutiert `state` in place.
## Rueckgabe {"ok": bool, "reason": ""|"unknown"|"healthy"|"coins", "total": int}.
static func pay_vet(state: Dictionary, kind: String, now_ms: int) -> Dictionary:
	if kind != "cure" and kind != "checkup":
		return {"ok": false, "reason": "unknown", "total": 0}
	var gooby := _dict(state.get("gooby"))
	var health := normalize(gooby.get("health"))
	if kind == "cure" and health["state"] == "healthy":
		return {"ok": false, "reason": "healthy", "total": 0}
	var price := VET_CURE_PRICE if kind == "cure" else VET_CHECKUP_PRICE
	var econ := _dict(state.get("economy"))
	if not Economy.spend(econ, price, "vet:%s" % kind):
		return {"ok": false, "reason": "coins", "total": 0}
	if kind == "cure":
		gooby["health"] = vet_cure(health, now_ms)
		var stats := _dict(gooby.get("stats"))
		gooby["stats"] = (
			Stats
			. apply_deltas(
				stats,
				{
					"hunger": VET_CURE_STAT_BONUS,
					"energy": VET_CURE_STAT_BONUS,
					"hygiene": VET_CURE_STAT_BONUS,
					"fun": VET_CURE_STAT_BONUS,
				}
			)
		)
		var counters := _counters(state)
		counters["cures"] = int(_num(counters.get("cures"))) + 1
	else:
		gooby["health"] = vet_checkup(health)
	return {"ok": true, "reason": "", "total": price}


static func _counters(state: Dictionary) -> Dictionary:
	if not (state.get("achievements") is Dictionary):
		state["achievements"] = {"counters": {}}
	var achievements: Dictionary = state["achievements"]
	if not (achievements.get("counters") is Dictionary):
		achievements["counters"] = {}
	return achievements["counters"]


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _truthy(value: Variant) -> bool:
	return value is bool and value


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0


static func _num_or(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback

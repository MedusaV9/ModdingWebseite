class_name TeaPartyLogic
extends RefCounted
## Pure Teestube-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/teaParty.logic.js (§V5.1/G06). Halten gießt Tee,
## Loslassen im Band punktet (perfect +6 / good +3), außerhalb/Überlauf =
## Spill; jeder 3. Perfect in Folge zahlt +2. Tune-Dictionaries behalten die
## Web-Key-Namen, damit die Bot-Zertifizierung (tests/expected/teaParty.json
## aus tools/cross_check.mjs) schlüsselgleich vergleicht. Alle Float-Pfade
## sind double-identisch zum Web (gleiche Literale, gleiche Op-Reihenfolge).

## Bindende §V5.1-Zahlen + G06-Tuning (Coin-Zeile: divisor 4, min 4, max 26).
const TEA := {
	"DURATION_SEC": 60.0,
	"FILL_RATE": 0.5,
	"BAND_CENTER_MIN": 0.55,
	"BAND_CENTER_MAX": 0.85,
	"BAND_HALF_W": 0.075,
	"PERFECT_HALF_W": 0.028,
	"PERFECT_PTS": 6,
	"GOOD_PTS": 3,
	"STREAK_EVERY": 3,
	"STREAK_BONUS": 2,
	"SERVE_SEC_START": 1.7,
	"SERVE_SEC_END": 1.1,
	"OVERFLOW_LEVEL": 1.0,
	"ENDLESS": false,
	"ENDLESS_MAX_SPILLS": 3,
	"AUTOPLAY_AIM_ERR": 0.06,
}

## §G5.3 Timed-Arena-Zeilen (Fenster/Speed/Dauer); Endlos = Schwer-Parameter.
const TEA_DIFFICULTY := {
	"easy":
	{"fillMult": 0.8, "bandMult": 1.25, "durationMult": 1.2, "serveMult": 1.0, "botErr": 0.05},
	"hard":
	{"fillMult": 1.2, "bandMult": 0.8, "durationMult": 1.0, "serveMult": 0.85, "botErr": 0.068},
	"endless":
	{"fillMult": 1.2, "bandMult": 0.8, "durationMult": 1.0, "serveMult": 0.85, "botErr": 0.068},
}


## Abgeleitetes Tune; `normal` liefert exakt das Mittel-Objekt (§G5.3).
static func apply_difficulty(tune: Dictionary = TEA, mode := "normal") -> Dictionary:
	if mode == "normal" or not TEA_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = TEA_DIFFICULTY[mode]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["durationMult"])
	out["FILL_RATE"] = float(tune["FILL_RATE"]) * float(row["fillMult"])
	out["BAND_HALF_W"] = float(tune["BAND_HALF_W"]) * float(row["bandMult"])
	out["PERFECT_HALF_W"] = float(tune["PERFECT_HALF_W"]) * float(row["bandMult"])
	out["SERVE_SEC_START"] = float(tune["SERVE_SEC_START"]) * float(row["serveMult"])
	out["SERVE_SEC_END"] = float(tune["SERVE_SEC_END"]) * float(row["serveMult"])
	out["AUTOPLAY_AIM_ERR"] = float(row["botErr"])
	out["ENDLESS"] = mode == "endless"
	return out


## Frische Tasse: Zielband (Center innerhalb der §TEA-Spanne) würfeln.
static func roll_band(rng: GoobyRng, tune: Dictionary = TEA) -> Dictionary:
	var span := float(tune["BAND_CENTER_MAX"]) - float(tune["BAND_CENTER_MIN"])
	return {
		"center": float(tune["BAND_CENTER_MIN"]) + rng.next() * span,
		"half": float(tune["BAND_HALF_W"]),
		"perfectHalf": float(tune["PERFECT_HALF_W"]),
	}


## Füllstand nach dt Sekunden Gießen (ungedeckelt — Overflow prüft der Caller).
static func fill_after(level: float, dt: float, tune: Dictionary = TEA) -> float:
	return maxf(0.0, level) + float(tune["FILL_RATE"]) * maxf(0.0, dt)


## Losgelassene (oder übergelaufene) Tasse gegen ihr Band auswerten.
static func pour_result(level: float, band: Dictionary, tune: Dictionary = TEA) -> Dictionary:
	var overflow := level >= float(tune["OVERFLOW_LEVEL"])
	var dist := absf(level - float(band["center"]))
	if not overflow and dist <= float(band["perfectHalf"]):
		return {"result": "perfect", "points": int(tune["PERFECT_PTS"]), "overflow": false}
	if not overflow and dist <= float(band["half"]):
		return {"result": "good", "points": int(tune["GOOD_PTS"]), "overflow": false}
	return {"result": "miss", "points": 0, "overflow": overflow}


## Streak-Bonus des n-ten Perfects IN FOLGE (jeder 3. zahlt +2).
static func streak_bonus_at(streak: int, tune: Dictionary = TEA) -> int:
	if streak > 0 and streak % int(tune["STREAK_EVERY"]) == 0:
		return int(tune["STREAK_BONUS"])
	return 0


## Tassenwechsel-Zeit im Rundenverlauf (Kadenz zieht linear an).
static func serve_interval_at(elapsed: float, duration := 60.0, tune: Dictionary = TEA) -> float:
	var t := minf(1.0, maxf(0.0, elapsed / duration))
	var start := float(tune["SERVE_SEC_START"])
	return start + (float(tune["SERVE_SEC_END"]) - start) * t


## Score-Delta anwenden, bei 0 gefloort.
static func apply_score(score: int, delta: int) -> int:
	return maxi(0, score + delta)


## §G5.4 Endlos endet mit der 3. verschütteten/verpassten Tasse.
static func endless_should_end(spills: int, tune: Dictionary = TEA) -> bool:
	return tune["ENDLESS"] == true and spills >= int(tune["ENDLESS_MAX_SPILLS"])


## Deterministische Bot-Zertifizierung (identisch zum Web-Release-Bot).
static func simulate_autoplay(mode := "normal", seed_value := 1) -> Dictionary:
	var tune := apply_difficulty(TEA, mode)
	var rng := GoobyRng.new(seed_value)
	var elapsed := 0.0
	var score := 0
	var cups := 0
	var spills := 0
	var streak := 0
	var limit := 600.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	while elapsed < limit and not endless_should_end(spills, tune):
		var band := roll_band(rng, tune)
		# Der Bot zielt auf die Bandmitte und lässt mit Uniform-Fehler los.
		var level: float = (
			float(band["center"]) + (rng.next() * 2.0 - 1.0) * float(tune["AUTOPLAY_AIM_ERR"])
		)
		var res := pour_result(level, band, tune)
		score = apply_score(score, int(res["points"]))
		if res["result"] == "perfect":
			streak += 1
			score = apply_score(score, streak_bonus_at(streak, tune))
		else:
			streak = 0
			if res["result"] == "miss":
				spills += 1
		cups += 1
		# Zeitkosten: bis zum losgelassenen Level gießen, dann Tassenwechsel.
		elapsed += (
			level / float(tune["FILL_RATE"])
			+ serve_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
		)
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"cups": cups,
		"spills": spills,
		"elapsed": elapsed,
	}

class_name HideSeekLogic
extends RefCounted
## Pure Guck-guck-Garten-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/hideSeek.logic.js (PLAN5 §V5.2).
## Tierchen verstecken sich hinter einem 3×4-Raster aus Büschen/Kisten/Töpfen
## und lugen periodisch hervor; ein Tipp auf das richtige Versteck findet sie
## (+2). Eine komplett geräumte Welle zahlt +3. Coin-Zeile /5, 4..20, Ziel 80.

## Bindende §V5.2-Zahlen + G06-Tuning (Raster, Wellen, Guck-Takt, Bot).
const SEEK := {
	"DURATION_SEC": 60.0,
	"COLS": 3,
	"ROWS": 4,
	"WAVE_HIDERS_START": 3,
	"WAVE_HIDERS_MAX": 5,
	"WAVE_RAMP_WAVES": 4,
	"FIND_PTS": 2,
	"WAVE_BONUS": 3,
	"WAVE_SEC_START": 13.0,
	"WAVE_SEC_END": 9.0,
	"SERVE_SEC": 1.0,
	"PEEK_EVERY_SEC": 2.4,
	"PEEK_DURATION_SEC": 0.75,
	"ENDLESS": false,
	"ENDLESS_MAX_EXPIRED": 3,
	"AUTOPLAY_TAP_SEC": 1.2,
	"AUTOPLAY_FIND_RATE": 0.9,
}

## §G5.3-Zeilen der Timed-Arena-Familie (Fenster/Takt/Dauer).
const SEEK_DIFFICULTY := {
	"easy":
	{
		"waveSecMult": 1.25,
		"peekDurMult": 1.3,
		"peekEveryMult": 1.0,
		"durationMult": 1.2,
		"botRate": 0.97,
	},
	"hard":
	{
		"waveSecMult": 0.8,
		"peekDurMult": 0.8,
		"peekEveryMult": 1.25,
		"durationMult": 1.0,
		"botRate": 0.82,
	},
	"endless":
	{
		"waveSecMult": 0.8,
		"peekDurMult": 0.8,
		"peekEveryMult": 1.25,
		"durationMult": 1.0,
		"botRate": 0.82,
	},
}


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle (§G5.3).
static func apply_difficulty(tune := SEEK, mode := "normal") -> Dictionary:
	if mode == "normal" or not SEEK_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = SEEK_DIFFICULTY[mode]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["durationMult"])
	out["WAVE_SEC_START"] = float(tune["WAVE_SEC_START"]) * float(row["waveSecMult"])
	out["WAVE_SEC_END"] = float(tune["WAVE_SEC_END"]) * float(row["waveSecMult"])
	out["PEEK_DURATION_SEC"] = float(tune["PEEK_DURATION_SEC"]) * float(row["peekDurMult"])
	out["PEEK_EVERY_SEC"] = float(tune["PEEK_EVERY_SEC"]) * float(row["peekEveryMult"])
	out["AUTOPLAY_FIND_RATE"] = float(row["botRate"])
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## Anzahl der Verstecke auf dem Raster.
static func spot_count(tune := SEEK) -> int:
	return int(tune["COLS"]) * int(tune["ROWS"])


## Verstecker der 0-basierten Welle (Rampe Start → Max, danach konstant).
static func hiders_for_wave(wave: int, tune := SEEK) -> int:
	var t := minf(1.0, maxf(0.0, float(wave) / float(tune["WAVE_RAMP_WAVES"])))
	var start := float(tune["WAVE_HIDERS_START"])
	return MinigameFrameworkLogic.js_round(start + (float(tune["WAVE_HIDERS_MAX"]) - start) * t)


## Wellenuhr der 0-basierten Welle (Rampe Start → Ende, danach konstant).
static func wave_sec_for(wave: int, tune := SEEK) -> float:
	var t := minf(1.0, maxf(0.0, float(wave) / float(tune["WAVE_RAMP_WAVES"])))
	var start := float(tune["WAVE_SEC_START"])
	return start + (float(tune["WAVE_SEC_END"]) - start) * t


## Versteck-Indizes einer Welle würfeln: eindeutig, gleichverteilt, aufsteigend.
## Partielles Fisher-Yates — verbraucht GENAU n rng()-Werte wie im Web.
static func roll_hiders(rng: GoobyRng, wave: int, tune := SEEK) -> Array[int]:
	var total := spot_count(tune)
	var n := mini(hiders_for_wave(wave, tune), total)
	var pool: Array[int] = []
	for i in total:
		pool.append(i)
	for i in n:
		var j := i + int(floor(rng.next() * (total - i)))
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var out := pool.slice(0, n)
	out.sort()
	return out


## Punkte-Delta anwenden, bei 0 abgeschnitten.
static func apply_score(score: int, delta: int) -> int:
	return maxi(0, score + delta)


## §G5.4 Endlos endet an der dritten abgelaufenen (ungeräumten) Welle.
static func endless_should_end(expired: int, tune := SEEK) -> bool:
	return bool(tune["ENDLESS"]) and expired >= int(tune["ENDLESS_MAX_EXPIRED"])


## Deterministische Bot-Zertifizierung (identisch zum Web-Release-Bot).
static func simulate_autoplay(mode := "normal", seed_value := 1) -> Dictionary:
	var tune := apply_difficulty(SEEK, mode)
	var rng := GoobyRng.new(seed_value)
	var elapsed := 0.0
	var score := 0
	var wave := 0
	var expired := 0
	var found := 0
	var limit := 600.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	while elapsed < limit and not endless_should_end(expired, tune):
		var left := roll_hiders(rng, wave, tune).size()
		var wave_sec := wave_sec_for(wave, tune)
		var wave_t := 0.0
		while left > 0 and wave_t < wave_sec and elapsed + wave_t < limit:
			wave_t += float(tune["AUTOPLAY_TAP_SEC"])
			if rng.next() < float(tune["AUTOPLAY_FIND_RATE"]):
				left -= 1
				found += 1
				score = apply_score(score, int(tune["FIND_PTS"]))
		if left == 0:
			score = apply_score(score, int(tune["WAVE_BONUS"]))
		elif wave_t >= wave_sec:
			expired += 1
		elapsed += wave_t + float(tune["SERVE_SEC"])
		wave += 1
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"waves": wave,
		"found": found,
		"expired": expired,
		"elapsed": elapsed,
	}

class_name GoalieGoobyLogic
extends RefCounted
## Pure Torwart-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/goalieGooby.logic.js (PLAN2 §C1.2 #7, §C10.2).
## 5 Bahnen, Ankündigung 0.9 s → 0.45 s, Heber (nach oben wischen) und Roller
## (nach unten), Parade +4 (+2 Superparade in den letzten 0.15 s), 3 Gegentore
## beenden früh, sonst 60 s; alle 10 Paraden jubelt die Menge und alles wird
## 10 % schneller. Die letzten zehn Sekunden sind ein Fünf-Schuss-Elfmeterfinale.

## Bindende §C1.2-#7-Zahlen; Coin-Zeile 3/4/26, Ziel 65.
const GOALIE := {
	"DURATION_SEC": 60.0,
	"LANES": 5,
	"TELEGRAPH_START_SEC": 0.9,
	"TELEGRAPH_END_SEC": 0.45,
	"TELEGRAPH_RAMP_SEC": 60.0,
	"SAVE_PTS": 4,
	"SUPER_PTS": 2,
	"SUPER_WINDOW_SEC": 0.15,
	"MAX_GOALS": 3,
	"CHEER_EVERY_SAVES": 10,
	"CHEER_SPEED_MULT": 1.1,
	"MIX_FROM_SEC": 8.0,
	"LOB_CHANCE": 0.22,
	"ROLLER_CHANCE": 0.22,
	"FLIGHT_SEC": 0.55,
	"GAP_SEC": 0.8,
	"DIVE_HOLD_SEC": 0.45,
	"VKIND_MIN_PX": 24.0,
	"LANE_INNER_DEG": 18.0,
	"LANE_OUTER_DEG": 54.0,
	"AUTOPLAY_LEAD_SEC": 0.2,
	"AUTOPLAY_JITTER_SEC": 0.1,
	"AUTOPLAY_ERR_BASE": 0.07,
	"AUTOPLAY_ERR_RAMP": 0.48,
	"SHOOTOUT_START_SEC": 50.0,
	"SHOOTOUT_SHOTS": 5,
	"SHOOTOUT_TELEGRAPH_SEC": 0.38,
	"SHOOTOUT_FLIGHT_SEC": 0.42,
	"SHOOTOUT_GAP_SEC": 0.28,
	"SHOOTOUT_SAVE_MULT": 2,
	"ENDLESS": false,
	"ENDLESS_GOALS": 3,
	"RENDER_SCALE": 1.0,
	"HITBOX_MULT": 1.0,
	"AUTOPLAY_SKILL_MULT": 0.12,
}

## V4/G73 Zeitarena-Modi (§G5.3).
const GOALIE_DIFFICULTY := {
	"easy": {"spawnMult": 1.2, "windowMult": 1.25, "durationMult": 1.2, "botSkillMult": 0.08},
	"hard": {"spawnMult": 0.85, "windowMult": 0.8, "durationMult": 1.0, "botSkillMult": 0.2},
	"endless": {"spawnMult": 0.85, "windowMult": 0.8, "durationMult": 1.0, "botSkillMult": 0.2},
}

## V4/GAME-POLISH-4 Präsentations-Tuning (Kamera + Paraden-Juice).
const GOALIE_JUICE := {
	"CAM_Z_PORTRAIT": 10.0,
	"CAM_Z_LANDSCAPE": 7.4,
	"GOAL_HALF_W_PORTRAIT": 2.4,
	"GOAL_HALF_W_LANDSCAPE": 3.1,
	"RING_LIFE_SEC": 0.38,
	"RING_SCALE_SAVE": 3.2,
	"RING_SCALE_SUPER": 5.2,
	"GLOVE_PUNCH_SCALE": 1.5,
	"PIP_POP_SCALE": 1.7,
}


## Abgeleitetes Tune; `normal` liefert die Mittel-Tabelle bit-identisch.
static func apply_difficulty(tune := GOALIE, mode := "normal") -> Dictionary:
	if mode == "normal" or not GOALIE_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = GOALIE_DIFFICULTY[mode]
	var window_mult := float(row["windowMult"])
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["durationMult"])
	out["GAP_SEC"] = float(tune["GAP_SEC"]) * float(row["spawnMult"])
	out["TELEGRAPH_START_SEC"] = maxf(0.35, float(tune["TELEGRAPH_START_SEC"]) * window_mult)
	out["TELEGRAPH_END_SEC"] = maxf(0.35, float(tune["TELEGRAPH_END_SEC"]) * window_mult)
	out["DIVE_HOLD_SEC"] = maxf(0.35, float(tune["DIVE_HOLD_SEC"]) * window_mult)
	out["SHOOTOUT_TELEGRAPH_SEC"] = maxf(0.35, float(tune["SHOOTOUT_TELEGRAPH_SEC"]) * window_mult)
	out["ENDLESS"] = mode == "endless"
	out["AUTOPLAY_SKILL_MULT"] = float(row["botSkillMult"])
	out["MODE"] = mode
	return out


## Riesen-Gooby-Nutzlast (§C-SYS4.2): Renderskala + größere Hitbox.
static func apply_riesen_gooby(tune: Dictionary, payload := {}) -> Dictionary:
	var safe_scale := maxf(1.0, float(payload.get("scale", 1.0)))
	var safe_hitbox := maxf(1.0, float(payload.get("hitboxMult", 1.0)))
	var out := tune.duplicate()
	out["RENDER_SCALE"] = safe_scale
	out["HITBOX_MULT"] = safe_hitbox
	out["DIVE_HOLD_SEC"] = float(tune["DIVE_HOLD_SEC"]) * safe_hitbox
	return out


## Ankündigungsdauer zu einem Rundenzeitpunkt (linear 0.9 s → 0.45 s).
static func telegraph_sec_at(elapsed: float, tune := GOALIE) -> float:
	var t := clampf(elapsed / float(tune["TELEGRAPH_RAMP_SEC"]), 0.0, 1.0)
	var start := float(tune["TELEGRAPH_START_SEC"])
	return start + (float(tune["TELEGRAPH_END_SEC"]) - start) * t


## Tempofaktor nach n Jubeln (×1.10 je Jubel).
static func speed_mult_at(cheers: int, tune := GOALIE) -> float:
	return pow(float(tune["CHEER_SPEED_MULT"]), maxi(0, cheers))


## Ballflugzeit beim aktuellen Mengentempo.
static func flight_sec_at(cheers: int, tune := GOALIE) -> float:
	return float(tune["FLIGHT_SEC"]) / speed_mult_at(cheers, tune)


## Nächsten Schuss würfeln: Bahn 0–4 gleichverteilt; Heber/Roller ab Sekunde 8.
static func roll_kick(rng: Callable, elapsed: float) -> Dictionary:
	var lanes := int(GOALIE["LANES"])
	var lane := mini(lanes - 1, int(floor(float(rng.call()) * lanes)))
	if elapsed < float(GOALIE["MIX_FROM_SEC"]):
		return {"lane": lane, "kind": "straight"}
	var r := float(rng.call())
	if r < float(GOALIE["LOB_CHANCE"]):
		return {"lane": lane, "kind": "lob"}
	if r < float(GOALIE["LOB_CHANCE"]) + float(GOALIE["ROLLER_CHANCE"]):
		return {"lane": lane, "kind": "roller"}
	return {"lane": lane, "kind": "straight"}


## Wischwinkel → Bahn (0 = ganz links … 4 = ganz rechts; Tippen = Mitte).
static func lane_from_swipe(dx: float, dy: float) -> int:
	var deg := rad_to_deg(atan2(dx, maxf(1e-6, absf(dy))))
	if deg < -float(GOALIE["LANE_OUTER_DEG"]):
		return 0
	if deg < -float(GOALIE["LANE_INNER_DEG"]):
		return 1
	if deg <= float(GOALIE["LANE_INNER_DEG"]):
		return 2
	if deg <= float(GOALIE["LANE_OUTER_DEG"]):
		return 3
	return 4


## Vertikale Absicht: 'up' hält Heber, 'down' hält Roller, sonst 'mid'.
static func v_kind_from_swipe(dy: float) -> String:
	if dy <= -float(GOALIE["VKIND_MIN_PX"]):
		return "up"
	if dy >= float(GOALIE["VKIND_MIN_PX"]):
		return "down"
	return "mid"


## Hält eine Hechtparade diesen Schuss? Bahn muss passen, Heber/Roller zusätzlich
## die vertikale Absicht.
static func save_matches(kick: Dictionary, dive: Dictionary) -> bool:
	if int(kick["lane"]) != int(dive["lane"]):
		return false
	if str(kick["kind"]) == "lob":
		return str(dive["v"]) == "up"
	if str(kick["kind"]) == "roller":
		return str(dive["v"]) == "down"
	return true


## Deckt eine Parade zum Zeitpunkt diveT den bei arriveT ankommenden Ball?
static func dive_covers(dive_t: float, arrive_t: float, tune := GOALIE) -> bool:
	var lead := arrive_t - dive_t
	return lead >= 0.0 and lead <= float(tune["DIVE_HOLD_SEC"]) + 1e-9


## Superparade: die Hechte kam in den letzten 0.15 s vor der Linie.
static func is_super_save(dive_t: float, arrive_t: float, tune := GOALIE) -> bool:
	var lead := arrive_t - dive_t
	return lead >= 0.0 and lead <= float(tune["SUPER_WINDOW_SEC"]) + 1e-9


## Paradenpunkte: +4, +2 extra bei Superparade, im Elfmeterfinale verdoppelt.
static func save_points(super_save: bool, shootout := false, tune := GOALIE) -> int:
	var base := int(tune["SAVE_PTS"]) + (int(tune["SUPER_PTS"]) if super_save else 0)
	return base * (int(tune["SHOOTOUT_SAVE_MULT"]) if shootout else 1)


## Läuft gerade das Elfmeterfinale?
static func is_shootout_at(elapsed: float, tune := GOALIE) -> bool:
	if bool(tune["ENDLESS"]):
		return false
	return elapsed >= float(tune["SHOOTOUT_START_SEC"]) and elapsed <= float(tune["DURATION_SEC"])


## Nominaler Startzeitpunkt eines der fünf Finalschüsse.
static func shootout_shot_at(index: int, tune := GOALIE) -> float:
	var cycle := (
		float(tune["SHOOTOUT_TELEGRAPH_SEC"])
		+ float(tune["SHOOTOUT_FLIGHT_SEC"])
		+ float(tune["SHOOTOUT_GAP_SEC"])
	)
	return float(tune["SHOOTOUT_START_SEC"]) + maxi(0, index) * cycle


## Jubel nach n Paraden (alle 10).
static func cheers_at(saves: int) -> int:
	return int(floor(float(maxi(0, saves)) / float(GOALIE["CHEER_EVERY_SAVES"])))


## Patzerquote des Bots: Basis 7 %, steigt mit schrumpfender Ankündigung.
static func autoplay_err_at(telegraph_sec: float, tune := GOALIE, skill_mult := 1.0) -> float:
	var start := float(tune["TELEGRAPH_START_SEC"])
	var span := start - float(tune["TELEGRAPH_END_SEC"])
	var t := 1.0 if span <= 0.0 else clampf((start - telegraph_sec) / span, 0.0, 1.0)
	return (float(tune["AUTOPLAY_ERR_BASE"]) + float(tune["AUTOPLAY_ERR_RAMP"]) * t) * skill_mult


## §G5.4: Endlos endet am dritten Gegentor.
static func endless_should_end(goals: int, tune := GOALIE) -> bool:
	return bool(tune["ENDLESS"]) and goals >= int(tune["ENDLESS_GOALS"])


## Deterministische Zertifizierung des Ankündigungs-lesenden Bots.
static func simulate_autoplay(seed_value: int, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(GOALIE, mode)
	var rng := GoobyRng.new(seed_value)
	var elapsed := 0.0
	var score := 0
	var saves := 0
	var goals := 0
	var limit := 600.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	while elapsed < limit and goals < int(tune["ENDLESS_GOALS"]):
		var shootout := is_shootout_at(elapsed, tune)
		var telegraph := (
			float(tune["SHOOTOUT_TELEGRAPH_SEC"]) if shootout else telegraph_sec_at(elapsed, tune)
		)
		var flight := (
			float(tune["SHOOTOUT_FLIGHT_SEC"])
			if shootout
			else flight_sec_at(cheers_at(saves), tune)
		)
		var gap: float = tune["SHOOTOUT_GAP_SEC"] if shootout else tune["GAP_SEC"]
		elapsed += telegraph + flight + gap
		var error := autoplay_err_at(telegraph, tune, float(tune["AUTOPLAY_SKILL_MULT"]))
		if rng.next() < error:
			goals += 1
		else:
			saves += 1
			score += save_points(false, shootout, tune)
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"saves": saves,
		"goals": goals,
		"elapsed": elapsed,
	}

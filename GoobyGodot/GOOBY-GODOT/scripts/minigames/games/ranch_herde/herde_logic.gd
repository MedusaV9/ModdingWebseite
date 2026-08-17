class_name RanchHerdeLogic
extends RefCounted
## Schaf-Hüten (ranchHerde) — PURE Logik (RANCH-2). Eine Herde mit
## Schwarmverhalten (Boids: Trennung/Zusammenhalt/Ausrichtung + Flucht vor
## dem Reiter) muss durch das Tor in den Pferch getrieben werden, bevor die
## Zeit abläuft. 10 Level mit Steigerung aus data/herde_level.json
## (Content-Pack-Namespace "ranchplay"). step() ist deterministisch:
## KEIN RNG im Schritt — Wackeln kommt aus der beim Spawn gewürfelten
## Schaf-Phase + absoluter Zeit.

const LEVEL_PATH := "res://scripts/minigames/games/ranch_herde/data/herde_level.json"
const LEVEL_ANZAHL := 10

## Bindende Schwarm-/Spielzahlen (Kräfte in m/s², Tempi in m/s).
const TUNE := {
	"SCHAF_TEMPO": 3.0,
	"FLUCHT_RADIUS": 6.0,
	"FLUCHT_KRAFT": 7.0,
	"SEP_RADIUS": 1.1,
	"SEP_KRAFT": 4.5,
	"KOH_RADIUS": 5.5,
	"KOH_KRAFT": 0.7,
	"AUSR_RADIUS": 4.0,
	"AUSR_KRAFT": 0.5,
	"WAND_RAND": 1.2,
	"WAND_KRAFT": 8.0,
	"WANDER_KRAFT": 0.5,
	"DAEMPFUNG": 2.2,
	"TOR_SOG_RADIUS": 4.5,
	"TOR_SOG_KRAFT": 1.5,
	"DRUCK_ZUM_TOR": 0.45,
	"DRIN_BREMSE": 4.0,
	"REITER_TEMPO": 5.6,
	"PUNKTE_BASIS": 40,
	"PUNKTE_PRO_REST_S": 2.0,
	"PUNKTE_PRO_LEVEL": 4,
	"FIRST_CLEAR_BONUS": 25,
}

## §G5.3-Muster: easy = flinker Reiter + ruhigere Schafe, hard umgekehrt.
const DIFFICULTY := {
	"easy": {"reiter": 1.15, "wander": 0.6, "zeit": 1.25},
	"normal": {"reiter": 1.0, "wander": 1.0, "zeit": 1.0},
	"hard": {"reiter": 0.92, "wander": 1.45, "zeit": 0.85},
	"endless": {"reiter": 0.92, "wander": 1.45, "zeit": 0.85},
}


static func apply_difficulty(tune: Dictionary = TUNE, mode := "normal") -> Dictionary:
	var id := mode if DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = DIFFICULTY[id]
	var out := tune.duplicate()
	out["REITER_TEMPO"] = float(tune["REITER_TEMPO"]) * float(row["reiter"])
	out["WANDER_KRAFT"] = float(tune["WANDER_KRAFT"]) * float(row["wander"])
	out["ZEIT_MULT"] = float(row["zeit"])
	out["MODE"] = id
	return out


## Level-Zeitlimit nach Difficulty (easy bekommt mehr Luft).
static func zeitlimit(level: Dictionary, tune: Dictionary = TUNE) -> float:
	return float(level.get("zeit_s", 60.0)) * float(tune.get("ZEIT_MULT", 1.0))


## Alle Level laden (Registry-Override wie RanchWirtschaft.load_balance).
static func load_level(registry: Object = null) -> Array:
	var daten := RanchWirtschaft.read_json(LEVEL_PATH)
	var reg := registry
	if reg == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			reg = (loop as SceneTree).root.get_node_or_null("ContentRegistry")
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance("ranchplay", {})
		if overrides is Dictionary and (overrides as Dictionary).get("herde_level") is Array:
			return (overrides as Dictionary)["herde_level"]
	return daten.get("level") if daten.get("level") is Array else []


static func level_by_id(level_liste: Array, id: int) -> Dictionary:
	for level: Variant in level_liste:
		if level is Dictionary and int(level.get("id", 0)) == id:
			return level
	return {}


## Strukturelle Validierung (leer = alles gut): Pferch im Feld, Tor passt,
## Schafzahl/Zeit steigen mit dem Level.
static func validate_level(level_liste: Array) -> PackedStringArray:
	var fehler := PackedStringArray()
	if level_liste.size() != LEVEL_ANZAHL:
		fehler.append("erwartet %d Level, gefunden %d" % [LEVEL_ANZAHL, level_liste.size()])
	var schafe_vorher := 0
	for level: Variant in level_liste:
		if not (level is Dictionary):
			fehler.append("Level ist kein Objekt")
			continue
		var lv: Dictionary = level
		var id := int(lv.get("id", 0))
		var schafe := int(lv.get("schafe", 0))
		if schafe < schafe_vorher:
			fehler.append("Level %d: Schafzahl sinkt (%d < %d)" % [id, schafe, schafe_vorher])
		schafe_vorher = schafe
		var feld: Array = lv.get("feld", [])
		if feld.size() != 2:
			fehler.append("Level %d: feld braucht [halbX, halbZ]" % id)
			continue
		var pferch := pferch_rect(lv)
		if float(pferch["tor"]) < 2.0 or float(pferch["tor"]) > float(pferch["w"]):
			fehler.append("Level %d: Tor-Breite unplausibel" % id)
		if (
			absf(float(pferch["x"])) + float(pferch["w"]) * 0.5 > float(feld[0])
			or absf(float(pferch["z"])) + float(pferch["t"]) * 0.5 > float(feld[1])
		):
			fehler.append("Level %d: Pferch ragt aus dem Feld" % id)
	return fehler


## Pferch-Geometrie {x, z, w, t, tor}; das Tor sitzt mittig in der SÜD-Wand
## (zur Feldmitte hin, +z-Seite des Pferchs).
static func pferch_rect(level: Dictionary) -> Dictionary:
	var p: Dictionary = level.get("pferch") if level.get("pferch") is Dictionary else {}
	return {
		"x": float(p.get("x", 0.0)),
		"z": float(p.get("z", -7.0)),
		"w": float(p.get("w", 5.0)),
		"t": float(p.get("t", 3.5)),
		"tor": float(p.get("tor", 2.6)),
	}


## Weltposition der Tormitte (auf der Süd-Kante des Pferchs).
static func tor_pos(level: Dictionary) -> Vector2:
	var p := pferch_rect(level)
	return Vector2(float(p["x"]), float(p["z"]) + float(p["t"]) * 0.5)


static func ist_im_pferch(level: Dictionary, pos: Vector2, inset := 0.05) -> bool:
	var p := pferch_rect(level)
	return (
		absf(pos.x - float(p["x"])) <= float(p["w"]) * 0.5 - inset
		and absf(pos.y - float(p["z"])) <= float(p["t"]) * 0.5 - inset
	)


## Herde spawnen (deterministisch über GoobyRng): Süd-Hälfte des Felds.
static func spawn_schafe(level: Dictionary, rng: GoobyRng) -> Array:
	var feld: Array = level.get("feld", [12.0, 9.0])
	var out: Array = []
	for i in int(level.get("schafe", 3)):
		(
			out
			. append(
				{
					"x": (rng.next() * 2.0 - 1.0) * float(feld[0]) * 0.6,
					"z": (0.15 + rng.next() * 0.55) * float(feld[1]),
					"vx": 0.0,
					"vz": 0.0,
					"phase": rng.next() * TAU,
					"drin": false,
				}
			)
		)
	return out


## EIN Simulationsschritt der Herde. Pure: neues Array, Eingaben unberührt.
## t_abs treibt nur das deterministische Wander-Wackeln.
static func step(
	schafe: Array, reiter: Vector2, t_abs: float, dt: float, tune: Dictionary, level: Dictionary
) -> Array:
	var feld: Array = level.get("feld", [12.0, 9.0])
	var out: Array = []
	for i in schafe.size():
		var s: Dictionary = schafe[i]
		var pos := Vector2(float(s["x"]), float(s["z"]))
		var vel := Vector2(float(s["vx"]), float(s["vz"]))
		if bool(s["drin"]):
			vel = vel.move_toward(Vector2.ZERO, float(tune["DRIN_BREMSE"]) * dt)
			out.append(_bewege(s, pos, vel, dt, level, feld))
			continue
		var kraft := _boid_kraefte(schafe, i, pos, vel, tune)
		kraft += _flucht(pos, reiter, tune, tor_pos(level))
		kraft += _wand_kraft(pos, feld, tune)
		kraft += _tor_sog(pos, level, tune)
		kraft += (
			Vector2(cos(float(s["phase"]) + t_abs * 1.7), sin(float(s["phase"]) * 1.3 + t_abs))
			* float(tune["WANDER_KRAFT"])
		)
		vel += kraft * dt
		vel = vel.move_toward(Vector2.ZERO, float(tune["DAEMPFUNG"]) * dt * 0.35)
		var max_tempo := float(tune["SCHAF_TEMPO"])
		if vel.length() > max_tempo:
			vel = vel.normalized() * max_tempo
		out.append(_bewege(s, pos, vel, dt, level, feld))
	return out


## Anzahl Schafe im Pferch.
static func drin_anzahl(schafe: Array) -> int:
	var n := 0
	for s: Variant in schafe:
		if bool((s as Dictionary)["drin"]):
			n += 1
	return n


## Reiter-Schritt Richtung Ziel (geklemmt aufs Feld).
static func reiter_step(
	reiter: Vector2, ziel: Vector2, dt: float, tune: Dictionary, level: Dictionary
) -> Vector2:
	var feld: Array = level.get("feld", [12.0, 9.0])
	var neu := reiter.move_toward(ziel, float(tune["REITER_TEMPO"]) * dt)
	return Vector2(
		clampf(neu.x, -float(feld[0]), float(feld[0])),
		clampf(neu.y, -float(feld[1]), float(feld[1]))
	)


## Level-Endstand: Basis + Restzeit-Bonus + Level-Bonus (+ Erst-Abschluss).
static func level_score(
	level_id: int, rest_s: float, first_clear: bool, tune: Dictionary = TUNE
) -> int:
	var total := int(tune["PUNKTE_BASIS"])
	total += int(round(maxf(0.0, rest_s) * float(tune["PUNKTE_PRO_REST_S"])))
	total += level_id * int(tune["PUNKTE_PRO_LEVEL"])
	if first_clear:
		total += int(tune["FIRST_CLEAR_BONUS"])
	return total


## Sterne über den Restzeit-Anteil: ≥40 % = 3, ≥15 % = 2, sonst 1.
static func sterne(rest_s: float, limit_s: float) -> int:
	if limit_s <= 0.0:
		return 1
	var frac := rest_s / limit_s
	if frac >= 0.4:
		return 3
	return 2 if frac >= 0.15 else 1


## Hüte-Zielpunkt des Bots: immer HINTER dem tor-fernsten Schaf (vom Tor
## aus gesehen) — klassisches Ein-Schaf-nach-dem-anderen-Treiben; der
## Zusammenhalt der Boids zieht die Nachbarn mit. Diese Politik verklemmt
## sich nicht, wenn Nachzügler auf beiden Seiten des Pferchs stehen
## (die Herden-Mitte läge dann nutzlos IM Pferch).
static func bot_ziel(schafe: Array, level: Dictionary) -> Vector2:
	var tor := tor_pos(level)
	var ziel_schaf := tor
	var max_d := -1.0
	for s: Variant in schafe:
		if bool((s as Dictionary)["drin"]):
			continue
		var pos := Vector2(float((s as Dictionary)["x"]), float((s as Dictionary)["z"]))
		var d := pos.distance_to(tor)
		if d > max_d:
			max_d = d
			ziel_schaf = pos
	if max_d < 0.0:
		return tor
	var richtung := (ziel_schaf - tor).normalized() if ziel_schaf != tor else Vector2(0.0, 1.0)
	var ziel := ziel_schaf + richtung * 2.8
	# Steht das Zielschaf im Tor-Korridor, nie nördlich der Torlinie stehen —
	# sonst drückt der Reiter es wieder aus dem Pferch heraus. NEBEN dem
	# Pferch darf er dagegen ruhig von Norden schieben.
	var p := pferch_rect(level)
	if absf(ziel_schaf.x - float(p["x"])) < float(p["tor"]) * 0.5 + 1.0:
		ziel.y = maxf(ziel.y, float(p["z"]) + float(p["t"]) * 0.5 + 0.6)
	return ziel


## Deterministische Bot-Zertifizierung eines Levels (dt = 1/30).
## → {"geschafft", "zeit_s", "rest_s", "score", "sterne", "drin"}.
static func simulate_hueten(level: Dictionary, seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(TUNE, mode)
	var rng := GoobyRng.new(seed_value + int(level.get("id", 0)) * 211)
	var schafe := spawn_schafe(level, rng)
	var feld: Array = level.get("feld", [12.0, 9.0])
	var reiter := Vector2(0.0, float(feld[1]) * 0.9)
	var limit := zeitlimit(level, tune)
	var dt := 1.0 / 30.0
	var t := 0.0
	while t < limit:
		reiter = reiter_step(reiter, bot_ziel(schafe, level), dt, tune, level)
		schafe = step(schafe, reiter, t, dt, tune, level)
		t += dt
		if drin_anzahl(schafe) == schafe.size():
			break
	var geschafft := drin_anzahl(schafe) == schafe.size()
	var rest := maxf(0.0, limit - t)
	return {
		"seed": seed_value,
		"mode": mode,
		"geschafft": geschafft,
		"zeit_s": t,
		"rest_s": rest,
		"score": level_score(int(level.get("id", 0)), rest, false, tune) if geschafft else 0,
		"sterne": sterne(rest, limit) if geschafft else 0,
		"drin": drin_anzahl(schafe),
	}


static func _boid_kraefte(
	schafe: Array, index: int, pos: Vector2, vel: Vector2, tune: Dictionary
) -> Vector2:
	var sep := Vector2.ZERO
	var koh_summe := Vector2.ZERO
	var koh_n := 0
	var ausr_summe := Vector2.ZERO
	var ausr_n := 0
	for j in schafe.size():
		if j == index or bool((schafe[j] as Dictionary)["drin"]):
			continue
		var andere := Vector2(
			float((schafe[j] as Dictionary)["x"]), float((schafe[j] as Dictionary)["z"])
		)
		var d := pos.distance_to(andere)
		if d < 0.001:
			continue
		if d < float(tune["SEP_RADIUS"]):
			sep += (pos - andere) / d * (1.0 - d / float(tune["SEP_RADIUS"]))
		if d < float(tune["KOH_RADIUS"]):
			koh_summe += andere
			koh_n += 1
		if d < float(tune["AUSR_RADIUS"]):
			ausr_summe += Vector2(
				float((schafe[j] as Dictionary)["vx"]), float((schafe[j] as Dictionary)["vz"])
			)
			ausr_n += 1
	var kraft := sep * float(tune["SEP_KRAFT"])
	if koh_n > 0:
		kraft += (koh_summe / float(koh_n) - pos).limit_length(1.0) * float(tune["KOH_KRAFT"])
	if ausr_n > 0:
		kraft += (ausr_summe / float(ausr_n) - vel).limit_length(1.0) * float(tune["AUSR_KRAFT"])
	return kraft


## Flucht vor dem Reiter — mit Hüte-Drall: ein Anteil DRUCK_ZUM_TOR der
## Fluchtkraft zeigt Richtung Tor (die Herde ist "eingehütet" — so fühlt
## sich das Treiben für Kinder UND den Bot fair an).
static func _flucht(pos: Vector2, reiter: Vector2, tune: Dictionary, tor: Vector2) -> Vector2:
	var d := pos.distance_to(reiter)
	var radius := float(tune["FLUCHT_RADIUS"])
	if d >= radius or d < 0.001:
		return Vector2.ZERO
	var staerke := float(tune["FLUCHT_KRAFT"]) * (1.0 - d / radius)
	var weg := (pos - reiter) / d
	var zum_tor := (tor - pos).normalized() if pos.distance_to(tor) > 0.001 else Vector2.ZERO
	return weg * staerke + zum_tor * staerke * float(tune["DRUCK_ZUM_TOR"])


static func _wand_kraft(pos: Vector2, feld: Array, tune: Dictionary) -> Vector2:
	var rand := float(tune["WAND_RAND"])
	var kraft := Vector2.ZERO
	if pos.x > float(feld[0]) - rand:
		kraft.x = -(pos.x - (float(feld[0]) - rand)) / rand
	elif pos.x < -float(feld[0]) + rand:
		kraft.x = (-float(feld[0]) + rand - pos.x) / rand
	if pos.y > float(feld[1]) - rand:
		kraft.y = -(pos.y - (float(feld[1]) - rand)) / rand
	elif pos.y < -float(feld[1]) + rand:
		kraft.y = (-float(feld[1]) + rand - pos.y) / rand
	return kraft * float(tune["WAND_KRAFT"])


## Sanfter Trichter vors Tor: nahe Schafe werden zur Tormitte gezogen.
static func _tor_sog(pos: Vector2, level: Dictionary, tune: Dictionary) -> Vector2:
	var tor := tor_pos(level)
	var d := pos.distance_to(tor)
	var radius := float(tune["TOR_SOG_RADIUS"])
	if d >= radius or d < 0.001 or ist_im_pferch(level, pos, 0.0):
		return Vector2.ZERO
	return (tor - pos) / d * float(tune["TOR_SOG_KRAFT"]) * (1.0 - d / radius)


## Bewegung + Pferch-Wände, ACHSEN-GETRENNT: eine blockierte Achse stoppt
## nur sich selbst — Schafe GLEITEN an Wänden entlang statt zu kleben.
## Das Tor (Süd-Wand) lässt rein; drin-Schafe kommen nicht mehr raus.
static func _bewege(
	s: Dictionary, pos: Vector2, vel: Vector2, dt: float, level: Dictionary, feld: Array
) -> Dictionary:
	var p := pferch_rect(level)
	var drin_alt := bool(s["drin"])
	var neu := pos
	var nx := clampf(pos.x + vel.x * dt, -float(feld[0]), float(feld[0]))
	if _wand_blockiert(pos, Vector2(nx, pos.y), p, drin_alt):
		vel.x = 0.0
	else:
		neu.x = nx
	var nz := clampf(pos.y + vel.y * dt, -float(feld[1]), float(feld[1]))
	if _wand_blockiert(Vector2(neu.x, pos.y), Vector2(neu.x, nz), p, drin_alt):
		vel.y = 0.0
	else:
		neu.y = nz
	var drin := drin_alt or ist_im_pferch(level, neu)
	return {
		"x": neu.x,
		"z": neu.y,
		"vx": vel.x,
		"vz": vel.y,
		"phase": float(s["phase"]),
		"drin": drin,
	}


## True, wenn der Schritt von→nach an einer Pferch-Wand blockiert.
static func _wand_blockiert(von: Vector2, nach: Vector2, p: Dictionary, drin: bool) -> bool:
	var innen_v := _im_rect(von, p)
	var innen_n := _im_rect(nach, p)
	if innen_v == innen_n:
		return false
	if drin:
		return innen_v
	if innen_n:
		var sued_z := float(p["z"]) + float(p["t"]) * 0.5
		var im_tor := absf(nach.x - float(p["x"])) < float(p["tor"]) * 0.5 - 0.1
		return not (im_tor and von.y >= sued_z - 0.001)
	return false


static func _im_rect(pos: Vector2, p: Dictionary) -> bool:
	return (
		absf(pos.x - float(p["x"])) < float(p["w"]) * 0.5
		and absf(pos.y - float(p["z"])) < float(p["t"]) * 0.5
	)

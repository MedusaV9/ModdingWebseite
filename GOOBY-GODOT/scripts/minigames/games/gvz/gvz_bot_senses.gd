extends RefCounted
## Read-only-Weltmodell des GvZ-Bots (aus gvz_bot.gd ausgelagert — Datei-
## Limit): NUR Abfragen über den Spielzustand, keine Platzierungen und keine
## State-Mutationen. Enthält die Pessimisten-Sicht (E11-Root-Cause):
## Bedrohungen werden nie gnädiger geschätzt als auf "normal".


## Kann irgendein Schütze diesen Punkt noch treffen? (Projektile starten bei
## col*1000+600, fliegen nach rechts; Sternchen zählen ±1 Reihe.)
static func lane_can_hit(state: Dictionary, lane: int, x: int) -> bool:
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		var row: Dictionary = state["balance"]["towers"].get(str(tower["type"]), {})
		if not row.has("projectile"):
			continue
		var reach := 1 if str(row["projectile"]) == "star" else 0
		if absi(int(tower["lane"]) - lane) > reach:
			continue
		if int(tower["col"]) * GvzLogic.CELL_MM + 400 <= x:
			return true
	return false


## Ist der vorderste Boden-Zombie der Reihe ein Zerquetscher (Brocken)?
## Gegen den ist JEDE Mauer verschwendet (1-Hit-Crush).
static func front_is_crusher(state: Dictionary, lane: int) -> bool:
	var best_x := 99999
	var crusher := false
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		if bool(zombie["flying"]) or zombie["state"] == "dig":
			continue
		if int(zombie["x"]) < best_x:
			best_x = int(zombie["x"])
			crusher = bool(zombie["crusher"])
	return crusher


static func lane_has_stealable(state: Dictionary, lane: int) -> bool:
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["armor_hp"]) <= 0:
			continue
		if GvzZombies.MAGNET_STEALABLE.has(str(zombie["armor"])):
			return true
	return false


static func magnet_covers(state: Dictionary, lane: int) -> bool:
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if str(tower["type"]) == "magnet_gooby" and absi(int(tower["lane"]) - lane) <= 1:
			return true
	return false


## Dickster anrollender Boden-Zombie der Reihe (leer = keiner).
static func heaviest_zombie(state: Dictionary, lane: int) -> Dictionary:
	var best := {}
	var best_hp := 0
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		if bool(zombie["flying"]) or zombie["state"] == "dig":
			continue
		var hp := int(zombie["hp"]) + int(zombie["armor_hp"])
		if hp > best_hp:
			best_hp = hp
			best = zombie
	return best


## Anrollende Boden-HP einer Reihe (Ballons zählen nicht — Pust-Sache).
static func lane_threat_hp(state: Dictionary, lane: int) -> int:
	var total := 0
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		if bool(zombie["flying"]):
			continue
		total += pessimist_hp(state, int(zombie["hp"])) + int(zombie["armor_hp"])
	return total


## Bot-Weltmodell (E11-Root-Cause "Difficulty kippt Bot-Entscheidungen"):
## Bedrohungen werden NIE leichter eingeschätzt als auf normal. Easy-Rabatte
## werden aus der Schätzung rausgerechnet (der Bauplan bleibt identisch zu
## normal, nur die Welt ist gnädiger), Hard-Aufschläge zählen voll — das
## erzwingt monoton fallende Winrates statt Schwellen-Kippern.
static func pessimist_hp(state: Dictionary, raw: int) -> int:
	var diff: Dictionary = state["balance"]["difficulty"].get(str(state["diff"]), {})
	var pct := int(diff.get("zombie_hp_pct", 100))
	if pct >= 100:
		return raw
	return GvzLogic._idiv(raw * 100, maxi(1, pct))


## Grobe Abschuss-Kapazität der Reihe, bis der vorderste Zombie das Haus
## erreicht (Schaden/Tick der Schützen × Restlaufzeit in Ticks).
static func lane_capacity(state: Dictionary, lane: int, front_x: int) -> int:
	# E11-Root-Cause: die alte Rechnung teilte durch das GLOBALE Basistempo
	# und ignorierte speed_pct/Hard-Bonus/Regen/Rage — Sprinter & Co. wurden
	# damit doppelt so langsam geschätzt und Not-Antworten kamen zu spät.
	# Jetzt zählt das echte Maximaltempo der anrollenden Zombies der Reihe
	# (Slow-Effekte bleiben unberücksichtigt = konservative Schätzung).
	var ticks_left := GvzLogic._idiv(maxi(0, front_x), maxi(1, lane_max_speed(state, lane)))
	var dmg_per_100_ticks := 0
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) != lane:
			continue
		var row: Dictionary = state["balance"]["towers"].get(str(tower["type"]), {})
		if not row.has("projectile"):
			continue
		var interval := maxi(1, int(row.get("fire_interval_ticks", 28)))
		var dmg := int(row.get("damage", 20)) * int(row.get("volley", 1))
		dmg_per_100_ticks += GvzLogic._idiv(dmg * 100, interval)
	return GvzLogic._idiv(dmg_per_100_ticks * ticks_left, 100)


## Schnellster anrollender Zombie der Reihe in mm/Tick (Kapazitäts- und
## Schärf-Rechnungen). speed_pct trägt Difficulty-Bonus + Regen schon beim
## Spawn; Rage (Zeitungsopa) ERSETZT das Tempo wie in GvzZombies._move_mm.
## Easy-Tempo-RABATTE werden rausgerechnet (Weltmodell nie gnädiger als
## normal, siehe pessimist_hp).
static func lane_max_speed(state: Dictionary, lane: int) -> int:
	var base := int(state["balance"]["combat"].get("zombie_speed_mm_per_tick", 10))
	var diff: Dictionary = state["balance"]["difficulty"].get(str(state["diff"]), {})
	var rebate := mini(0, int(diff.get("zombie_speed_bonus_pct", 0)))
	var pct := 100
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		var z_pct := int(zombie["speed_pct"]) - rebate
		if bool(zombie["raged"]):
			var row: Dictionary = state["balance"]["zombies"].get(str(zombie["type"]), {})
			z_pct = int(row.get("rage_speed_pct", z_pct))
		pct = maxi(pct, z_pct)
	return GvzLogic._idiv(base * pct, 100)


## Grundwirtschaft VOR dem ersten Schützen: nachts mehr (kein Himmel!).
static func base_eco(state: Dictionary) -> int:
	return 4 if bool(state["mods"].get("night", false)) else 2


## Steht die Grundwirtschaft? (Level ohne Sammler-Freischaltung zählen als
## versorgt — z. B. Förderband-Hybride und die ersten Kampagnen-Level.)
static func base_eco_ready(state: Dictionary) -> bool:
	if not GvzLogic.available_towers(state).has("nutella_sammler"):
		return true
	return count_type(state, "nutella_sammler") >= base_eco(state)


## Sammler-Zielzahl nach Level (Nacht-Level leben NUR von Sammlern;
## Spät-Kampagne braucht Wiederaufbau-Reserven).
static func eco_target(state: Dictionary) -> int:
	var id := int(state["level"].get("id", 1))
	if id <= 2:
		return 2
	if id <= 4:
		return 4
	return 8 if id >= 13 else 6


static func can_buy(state: Dictionary, type: String) -> bool:
	if not GvzLogic.available_towers(state).has(type):
		return false
	if GvzLogic.cooldown_left(state, type) > 0:
		return false
	return int(state["nutella"]) >= GvzLogic.tower_cost(state, type)


static func count_type(state: Dictionary, type: String) -> int:
	var count := 0
	for key: Variant in state["towers"]:
		if str(state["towers"][key]["type"]) == type:
			count += 1
	return count


static func lane_has_type(state: Dictionary, lane: int, type: String) -> bool:
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) == lane and str(tower["type"]) == type:
			return true
	return false


static func lane_shooter_count(state: Dictionary, lane: int) -> int:
	var count := 0
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) != lane:
			continue
		var row: Dictionary = state["balance"]["towers"].get(str(tower["type"]), {})
		if row.has("projectile"):
			count += 1
	return count


static func lane_has_flying(state: Dictionary, lane: int) -> bool:
	for zombie: Dictionary in state["zombies"]:
		if not zombie["dead"] and int(zombie["lane"]) == lane and bool(zombie["flying"]):
			return true
	return false


static func armored_count(state: Dictionary) -> int:
	var count := 0
	for zombie: Dictionary in state["zombies"]:
		if not zombie["dead"] and int(zombie["armor_hp"]) > 0:
			count += 1
	return count


static func nearest_zombie_x(state: Dictionary, lane: int) -> int:
	var best := 99999
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		if zombie["state"] == "dig":
			continue
		best = mini(best, int(zombie["x"]))
	return best


static func lane_has_armor(state: Dictionary, lane: int, armor: String) -> bool:
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane:
			continue
		if str(zombie["armor"]) == armor and int(zombie["armor_hp"]) > 0:
			return true
	return false

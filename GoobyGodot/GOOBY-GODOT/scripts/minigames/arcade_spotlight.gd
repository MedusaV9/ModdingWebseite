class_name ArcadeSpotlight
extends RefCounted
## Arcade-Spotlight „Spiel des Tages“ (W19) — pure, headless testbare Logik.
## Zeit kommt IMMER injiziert als "YYYY-MM-DD" (Clock.local_day() der
## GameState-Uhr) — keine OS-Uhr/randomize() in dieser Datei (AGENTS.md).
##
## AUSWAHL-REGEL (deterministisch, geräteübergreifend identisch):
## - Pool = alle Spiele, die der Spieler öffnen kann (Registry-Einträge ohne
##   „Bald!“-Flag `coming_soon`), alphabetisch nach id sortiert. Der
##   Endlos-LOCK (§G5.5) sperrt nur den Endlos-MODUS, nie die Kachel —
##   deshalb gehört jedes spielbare Spiel in den Pool.
## - Ketten-Rotation ab ANKER_TAG: der Start-Index kommt aus dem Tages-Seed
##   des Ankertags (YYYYMMDD als Zahl), danach springt JEDER Kalendertag um
##   1..n-1 Positionen weiter (Sprungweite ebenfalls aus dem YYYYMMDD-Seed
##   des jeweiligen Tages). Ein Sprung ist nie 0 → dasselbe Spiel steht NIE
##   an zwei aufeinanderfolgenden Tagen im Spotlight (bei n >= 2 und
##   stabilem Pool; wächst der Pool, rechnet die Kette mit dem neuen Pool).
##
## BONUS: Wer das Spotlight-Spiel an seinem Tag spielt, bekommt
## +BONUS_PROZENT % auf die tatsächlich gezahlte Runden-Auszahlung — genau
## EINMAL pro Lokaltag, im Save verankert unter minigames.spotlightBonusDay
## (additiver v5-Key, merge_defaults lässt ihn überleben — Muster
## minigames.dayCoinsDay). Gebucht wird der Bonus ausschließlich im EINEN
## Award-Pfad (minigame_award.gd → Economy.award, Reason "spotlight").

## Ankertag der Rotations-Kette — liegt VOR jedem realen Spieltag.
const ANKER_TAG := "2024-01-01"
## Ehrlicher Tagesbonus: +50 % auf die reguläre Auszahlung.
const BONUS_PROZENT := 50
## Additiver Marker-Key im minigames-Slice („heute schon eingelöst“).
const MARKER_KEY := "spotlightBonusDay"


## Pool der Spotlight-Kandidaten: ids aller öffenbaren Spiele, sortiert
## (stabile Reihenfolge = deterministische Auswahl auf allen Geräten).
static func pool_ids(games: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for game in games:
		if bool(game.get("coming_soon", false)):
			continue
		var id := str(game.get("id", ""))
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	ids.sort()
	return ids


## DAS Spotlight des Kalendertags `day` ("YYYY-MM-DD", injizierte Uhr!).
## "" bei leerem Pool oder kaputtem Datum. Regel: siehe Datei-Kopf.
static func spotlight_id(games: Array[Dictionary], day: String) -> String:
	var pool := pool_ids(games)
	var n := pool.size()
	var ziel := _tag_nummer(day)
	if n == 0 or ziel < 0:
		return ""
	if n == 1:
		return pool[0]
	var anker := _tag_nummer(ANKER_TAG)
	if ziel <= anker:
		# Vor dem Anker (sollte real nie vorkommen): direkter Seed-Griff.
		return pool[_mix(_tages_seed(ziel)) % n]
	var idx := _mix(_tages_seed(anker)) % n
	for k in range(anker + 1, ziel + 1):
		idx = (idx + 1 + _mix(_tages_seed(k)) % (n - 1)) % n
	return pool[idx]


## Ist `game_id` das Spiel des Tages `day`? Ohne `games`-Injektion (Tests)
## zählt die echte Registry.
static func ist_spotlight(game_id: String, day: String, games: Array[Dictionary] = []) -> bool:
	if game_id.is_empty():
		return false
	var kandidaten := games if not games.is_empty() else MinigameRegistry.all_games()
	return spotlight_id(kandidaten, day) == game_id


## Steht der Tagesbonus an `day` noch aus? (Marker-Lesung, wirft nie.)
static func bonus_verfuegbar(state: Dictionary, day: String) -> bool:
	var mg: Variant = state.get("minigames")
	if not (mg is Dictionary):
		return true
	return str((mg as Dictionary).get(MARKER_KEY, "")) != day


## Genau-einmal-pro-Tag-Anspruch prüfen UND verankern (mutiert `state` in
## place — innerhalb von GameState.update aufrufen, wie der Award-Pfad).
## Liefert die Bonus-Münzen (+BONUS_PROZENT % auf `basis_coins`); 0 = kein
## Anspruch. basis_coins <= 0 (z. B. Tages-Cap erreicht) verbraucht den
## Anspruch NICHT — der Bonus bleibt ehrlich.
static func beanspruche_bonus(
	state: Dictionary, game_id: String, basis_coins: int, day: String, games: Array[Dictionary] = []
) -> int:
	if basis_coins <= 0:
		return 0
	if not bonus_verfuegbar(state, day):
		return 0
	if not ist_spotlight(game_id, day, games):
		return 0
	if not (state.get("minigames") is Dictionary):
		return 0
	var mg: Dictionary = state["minigames"]
	mg[MARKER_KEY] = day
	return int(round(float(basis_coins) * float(BONUS_PROZENT) / 100.0))


## "YYYY-MM-DD" → fortlaufende Tag-Nummer (Unix-Tage; Mittags-Trick wie
## DailyBonus.prev_day gegen DST-Kanten). -1 bei kaputtem Input.
static func _tag_nummer(day: String) -> int:
	var parts := day.split("-")
	if parts.size() != 3 or not parts[2].is_valid_int():
		return -1
	var unix := (
		Time
		. get_unix_time_from_datetime_dict(
			{
				"year": int(parts[0]),
				"month": int(parts[1]),
				"day": int(parts[2]),
				"hour": 12,
				"minute": 0,
				"second": 0,
			}
		)
	)
	return int(floor(unix / 86400.0))


## Tages-Seed der Tag-Nummer: das Kalenderdatum als Zahl YYYYMMDD.
static func _tages_seed(tag_nummer: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(tag_nummer * 86400 + 43200)
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


## Deterministischer Integer-Avalanche (splitmix-Variante, 32-bit-maskiert,
## Ergebnis >= 0) — bewusst selbst implementiert statt hash():
## plattform-/versionsstabil und im Datei-Kopf dokumentierbar.
static func _mix(seed: int) -> int:
	var z := (seed + 0x9E3779B9) & 0xFFFFFFFF
	z = ((z ^ (z >> 16)) * 0x21F0AAAD) & 0xFFFFFFFF
	z = ((z ^ (z >> 15)) * 0x735A2D97) & 0xFFFFFFFF
	return (z ^ (z >> 15)) & 0x7FFFFFFF

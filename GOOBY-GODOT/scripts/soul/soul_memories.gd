class_name SoulMemories
extends RefCounted
## Persönliche Erinnerungen (FB-6/SEELE) — Gooby erwähnt NUR Dinge, die
## WIRKLICH passiert sind. Jeder Kandidat wird aus echten Save-Daten gebaut
## (Rekorde, Urlaube, Zähler, Streaks); ohne Daten gibt es KEINE Erinnerung.
## PURE Statics: State + Zeit werden hereingereicht, Auswahl über roll (0..1).

const MEMORY_COOLDOWN_MS := 3 * 86_400_000

## Schwellen, ab denen ein Zähler eine Erinnerung wert ist.
const MIN_TICKLES := 20
const MIN_HARVESTS := 10
const MIN_STREAK := 3
const MIN_PLAYTIME_MIN := 600
## Vorlieben (SEELE-2): erst ab echter Datenlage — 2 gespielte Spiele bzw.
## 3 Fütterungen desselben Essens.
const MIN_VORLIEBE_SPIELE := 2
const MIN_VORLIEBE_ESSEN := 3
## W20/HORIZONT: Schwellen der neuen Erlebnis-Quellen (W18/W19-Brocken).
## Umsatz-Bilanz erst ab richtiger Kassenlage (und >= 2 Markttagen, damit
## der Text grammatisch stimmt); Bestwert-Schwelle = 2-Sterne-Rang-Zeile
## des McGooby-Katalogs (McGoobyKatalog.RANG-Stufe „bestwert: 80“).
const MIN_GOOBYE_UMSATZ := 100
const MIN_SCHICHTEN := 3
const MIN_BESTWERT := 80
const MIN_FUNDE := 3
const MIN_GEISTER := 2
const MIN_MITBRINGSEL := 2

## Goobys kleine eigene Ziele (SEELE-2): „Ich wollte schon immer mal…“ —
## jede Bedingung prüft ECHTE Save-Daten; erfüllt sich das Ziel, bezieht
## sich Gooby beiläufig darauf zurück. Reihenfolge = stabile Auswahlbasis.
const WUNSCH_IDS: Array[String] = ["funkelpark", "urlaub", "streak7", "kissenturm"]


## Alle aktuell möglichen Erinnerungen: Array aus
## {id, text_key, args: Dictionary}. Reihenfolge stabil (deterministisch).
static func candidates(state: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_add_best_minigame(out, state)
	_add_vacation(out, state)
	_add_counters(out, state)
	_add_streak(out, state)
	_add_park(out, state)
	_add_playtime(out, state)
	_add_vorlieben(out, state)
	# W20/HORIZONT: die W18/W19-Brocken — additiv NACH den Bestands-Quellen,
	# damit deren stabile Reihenfolge (Determinismus-Vertrag) unberührt bleibt.
	_add_goobye(out, state)
	_add_mcgooby(out, state)
	_add_ranch_welt(out, state)
	_add_geist(out, state)
	_add_heimkehr(out, state)
	_add_spotlight(out, state)
	return out


## Kandidat wählen, der laut memoryShownAt lange nicht dran war. roll (0..1)
## wählt deterministisch unter den erlaubten; {} wenn keiner erlaubt ist.
static func pick(
	memory_candidates: Array[Dictionary], shown_at: Dictionary, now_ms: int, roll: float
) -> Dictionary:
	var allowed: Array[Dictionary] = []
	for candidate in memory_candidates:
		var last := int(shown_at.get(str(candidate["id"]), 0))
		if last <= 0 or now_ms - last >= MEMORY_COOLDOWN_MS:
			allowed.append(candidate)
	if allowed.is_empty():
		return {}
	var index := int(clampf(roll, 0.0, 0.999999) * allowed.size())
	return allowed[index]


## Bester Minigame-Rekord (minigames.legacy.best: {gameId: score}).
static func _add_best_minigame(out: Array[Dictionary], state: Dictionary) -> void:
	var best: Variant = _dig(state, ["minigames", "legacy", "best"])
	if not (best is Dictionary) or (best as Dictionary).is_empty():
		return
	var top_id := ""
	var top_score := 0
	var ids: Array = (best as Dictionary).keys()
	ids.sort()
	for game_id: Variant in ids:
		var score := int(_num(best[game_id]))
		if score > top_score:
			top_score = score
			top_id = str(game_id)
	if top_id.is_empty() or top_score <= 0:
		return
	(
		out
		. append(
			{
				"id": "rekord_" + top_id,
				"text_key": "soul.erinnerung.rekord",
				"args": {"spiel": _game_title(top_id), "punkte": top_score},
			}
		)
	)


## Urlaubs-Erinnerung nur bei ECHT besuchten Zielen (vacation.visited).
static func _add_vacation(out: Array[Dictionary], state: Dictionary) -> void:
	var visited: Variant = _dig(state, ["vacation", "visited"])
	if not (visited is Dictionary) or (visited as Dictionary).is_empty():
		return
	var dests: Array = (visited as Dictionary).keys()
	dests.sort()
	var dest := str(dests[0])
	(
		out
		. append(
			{
				"id": "urlaub_" + dest,
				"text_key": "soul.erinnerung.urlaub",
				"args": {"ziel": _dest_title(dest)},
			}
		)
	)


## Zähler-Erinnerungen (achievements.counters) — nur ab Schwelle.
static func _add_counters(out: Array[Dictionary], state: Dictionary) -> void:
	var counters: Variant = _dig(state, ["achievements", "counters"])
	if not (counters is Dictionary):
		return
	var tickles := int(_num((counters as Dictionary).get("tickles")))
	if tickles >= MIN_TICKLES:
		(
			out
			. append(
				{
					"id": "kitzeln",
					"text_key": "soul.erinnerung.kitzeln",
					"args": {"anzahl": tickles},
				}
			)
		)
	var harvests := int(_num((counters as Dictionary).get("harvests")))
	if harvests >= MIN_HARVESTS:
		(
			out
			. append(
				{
					"id": "garten",
					"text_key": "soul.erinnerung.garten",
					"args": {"anzahl": harvests},
				}
			)
		)


static func _add_streak(out: Array[Dictionary], state: Dictionary) -> void:
	var streak := int(_num(_dig(state, ["daily", "streak"])))
	if streak >= MIN_STREAK:
		(
			out
			. append(
				{
					"id": "streak",
					"text_key": "soul.erinnerung.streak",
					"args": {"tage": streak},
				}
			)
		)


static func _add_park(out: Array[Dictionary], state: Dictionary) -> void:
	var visits := int(_num(_dig(state, ["park", "visits"])))
	if visits > 0:
		(
			out
			. append(
				{
					"id": "funkelpark",
					"text_key": "soul.erinnerung.funkelpark",
					"args": {"anzahl": visits},
				}
			)
		)


static func _add_playtime(out: Array[Dictionary], state: Dictionary) -> void:
	var minutes := int(_num(_dig(state, ["profile", "playtimeMin"])))
	if minutes >= MIN_PLAYTIME_MIN:
		(
			out
			. append(
				{
					"id": "spielzeit",
					"text_key": "soul.erinnerung.spielzeit",
					"args": {"stunden": int(minutes / 60.0)},
				}
			)
		)


# ── Vorlieben & kleine Wünsche (SEELE-2) ─────────────────────────────────────


## Vorlieben aus dem echten Verhalten: Lieblingsspiel (bestes von ≥2
## gespielten) und Lieblingsessen (meistgefüttert, ≥3×). Beiläufig als
## Erinnerung erwähnt — nie als Liste.
static func _add_vorlieben(out: Array[Dictionary], state: Dictionary) -> void:
	var best: Variant = _dig(state, ["minigames", "legacy", "best"])
	if best is Dictionary and (best as Dictionary).size() >= MIN_VORLIEBE_SPIELE:
		var top_id := ""
		var top_score := 0
		var ids: Array = (best as Dictionary).keys()
		ids.sort()
		for game_id: Variant in ids:
			var score := int(_num(best[game_id]))
			if score > top_score:
				top_score = score
				top_id = str(game_id)
		if not top_id.is_empty():
			(
				out
				. append(
					{
						"id": "vorliebe_spiel",
						"text_key": "soul.erinnerung.vorliebe_spiel",
						"args": {"spiel": _game_title(top_id)},
					}
				)
			)
	var food: Variant = _dig(state, ["soul", "foodGiven"])
	if food is Dictionary:
		var top_food := ""
		var top_count := 0
		var food_ids: Array = (food as Dictionary).keys()
		food_ids.sort()
		for food_id: Variant in food_ids:
			var count := int(_num(food[food_id]))
			if count > top_count:
				top_count = count
				top_food = str(food_id)
		if top_count >= MIN_VORLIEBE_ESSEN:
			(
				out
				. append(
					{
						"id": "vorliebe_essen",
						"text_key": "soul.erinnerung.vorliebe_essen",
						"args": {"essen": _food_title(top_food)},
					}
				)
			)


# ── Erinnerungs-Horizont 2.0 (W20) — Digger der W18/W19-Quellen ─────────────
# Alle PURE + defensiv (Muster _add_counters): nur echte Save-Daten, ohne
# Daten KEINE Erinnerung, kein RNG/keine Uhr — Auswahl macht weiter pick().


## Goo-und-Bye-Lädchen (dlc.goobye.*): erster Markttag (umsatz.tage),
## Kassen-Bilanz (umsatz.gesamt) und der Lieferwagen-Kauf
## (transport.lieferwagen) — alles echte Kassensturz-/Transport-Daten.
static func _add_goobye(out: Array[Dictionary], state: Dictionary) -> void:
	var goobye: Variant = _dig(state, ["dlc", "goobye"])
	if not (goobye is Dictionary):
		return
	var umsatz: Variant = (goobye as Dictionary).get("umsatz")
	var tage := 0
	var gesamt := 0
	if umsatz is Dictionary:
		tage = int(_num((umsatz as Dictionary).get("tage")))
		gesamt = int(_num((umsatz as Dictionary).get("gesamt")))
	if tage >= 1:
		(
			out
			. append(
				{
					"id": "goobye_markttag",
					"text_key": "soul.erinnerung.goobye_markttag",
					"args": {},
				}
			)
		)
	if tage >= 2 and gesamt >= MIN_GOOBYE_UMSATZ:
		(
			out
			. append(
				{
					"id": "goobye_umsatz",
					"text_key": "soul.erinnerung.goobye_umsatz",
					"args": {"tage": tage, "muenzen": gesamt},
				}
			)
		)
	var transport: Variant = (goobye as Dictionary).get("transport")
	var lieferwagen: Variant = (
		(transport as Dictionary).get("lieferwagen") if transport is Dictionary else false
	)
	if lieferwagen is bool and lieferwagen:
		(
			out
			. append(
				{
					"id": "goobye_lieferwagen",
					"text_key": "soul.erinnerung.goobye_lieferwagen",
					"args": {},
				}
			)
		)


## McGooby-Laden (mcgooby.schichten.*): gespielte Schichten, Punkte-Bestwert
## (Rang-Futter, s. MIN_BESTWERT) und fehlerfreie Schichten (perfekt).
static func _add_mcgooby(out: Array[Dictionary], state: Dictionary) -> void:
	var schichten: Variant = _dig(state, ["mcgooby", "schichten"])
	if not (schichten is Dictionary):
		return
	var gespielt := int(_num((schichten as Dictionary).get("gespielt")))
	if gespielt >= MIN_SCHICHTEN:
		(
			out
			. append(
				{
					"id": "mcgooby_schichten",
					"text_key": "soul.erinnerung.mcgooby_schichten",
					"args": {"anzahl": gespielt},
				}
			)
		)
	var bestwert := int(_num((schichten as Dictionary).get("bestwert")))
	if bestwert >= MIN_BESTWERT:
		(
			out
			. append(
				{
					"id": "mcgooby_bestwert",
					"text_key": "soul.erinnerung.mcgooby_bestwert",
					"args": {"punkte": bestwert},
				}
			)
		)
	if int(_num((schichten as Dictionary).get("perfekt"))) >= 1:
		(
			out
			. append(
				{
					"id": "mcgooby_perfekt",
					"text_key": "soul.erinnerung.mcgooby_perfekt",
					"args": {},
				}
			)
		)


## Ranch-Region (ranch.welt.*): entdeckte Fundorte (funde) und die
## Entdecker-Karte (karteGesehen) — beides additive RanchWeltState-Keys.
static func _add_ranch_welt(out: Array[Dictionary], state: Dictionary) -> void:
	var welt: Variant = _dig(state, ["ranch", "welt"])
	if not (welt is Dictionary):
		return
	var funde := _string_liste((welt as Dictionary).get("funde"))
	if not funde.is_empty():
		funde.sort()
		(
			out
			. append(
				{
					"id": "ranch_fund_" + funde[0],
					"text_key": "soul.erinnerung.ranch_fund",
					"args": {"ort": _fund_title(funde[0])},
				}
			)
		)
	if funde.size() >= MIN_FUNDE:
		(
			out
			. append(
				{
					"id": "ranch_funde",
					"text_key": "soul.erinnerung.ranch_funde",
					"args": {"anzahl": funde.size()},
				}
			)
		)
	if not _string_liste((welt as Dictionary).get("karteGesehen")).is_empty():
		(
			out
			. append(
				{
					"id": "ranch_karte",
					"text_key": "soul.erinnerung.ranch_karte",
					"args": {},
				}
			)
		)


## Geister-Bestläufe (minigames.geist.<gameId>): bester gespeicherter
## Rekord-Geist + Größe der Geister-Sammlung (nur Läufe mit Score > 0).
static func _add_geist(out: Array[Dictionary], state: Dictionary) -> void:
	var geist: Variant = _dig(state, ["minigames", "geist"])
	if not (geist is Dictionary):
		return
	var top_id := ""
	var top_score := 0
	var anzahl := 0
	var ids: Array = (geist as Dictionary).keys()
	ids.sort()
	for game_id: Variant in ids:
		var rekord: Variant = geist[game_id]
		if not (rekord is Dictionary):
			continue
		var score := int(_num((rekord as Dictionary).get("score")))
		if score <= 0:
			continue
		anzahl += 1
		if score > top_score:
			top_score = score
			top_id = str(game_id)
	if top_id.is_empty():
		return
	(
		out
		. append(
			{
				"id": "geist_" + top_id,
				"text_key": "soul.erinnerung.geist_rekord",
				"args": {"spiel": _game_title(top_id), "punkte": top_score},
			}
		)
	)
	if anzahl >= MIN_GEISTER:
		(
			out
			. append(
				{
					"id": "geist_sammlung",
					"text_key": "soul.erinnerung.geist_sammlung",
					"args": {"anzahl": anzahl},
				}
			)
		)


## Urlaubs-Heimkehr (vacation.heimkehr*-Latches) + Mitbringsel-Sammlung
## (inventory.items, Ids mitbringsel_<ziel>_<typ> — HeimkehrLogik-Pipeline).
static func _add_heimkehr(out: Array[Dictionary], state: Dictionary) -> void:
	var vacation: Variant = state.get("vacation")
	if vacation is Dictionary:
		var ziel_roh: Variant = (vacation as Dictionary).get("heimkehrZiel")
		var ziel: String = ziel_roh if ziel_roh is String else ""
		var gefeiert: Variant = (vacation as Dictionary).get("heimkehrGefeiert")
		if gefeiert is bool and gefeiert and not ziel.is_empty():
			(
				out
				. append(
					{
						"id": "heimkehr_" + ziel,
						"text_key": "soul.erinnerung.heimkehr",
						"args": {"ziel": _dest_title(ziel)},
					}
				)
			)
	var items: Variant = _dig(state, ["inventory", "items"])
	if not (items is Dictionary):
		return
	var anzahl := 0
	for item_id: Variant in items as Dictionary:
		if str(item_id).begins_with("mitbringsel_") and int(_num(items[item_id])) > 0:
			anzahl += 1
	if anzahl >= MIN_MITBRINGSEL:
		(
			out
			. append(
				{
					"id": "mitbringsel",
					"text_key": "soul.erinnerung.mitbringsel",
					"args": {"anzahl": anzahl},
				}
			)
		)


## Arcade-Spotlight (minigames.spotlightBonusDay): der Tagesbonus wurde
## wirklich eingelöst. Textvariante deterministisch aus dem Save-Datum
## selbst (Kalendertag der Einlösung) — kein RNG, keine Uhr.
static func _add_spotlight(out: Array[Dictionary], state: Dictionary) -> void:
	var tag_roh: Variant = _dig(state, ["minigames", "spotlightBonusDay"])
	if not (tag_roh is String) or (tag_roh as String).is_empty():
		return
	var teile := (tag_roh as String).split("-")
	var variante := "a"
	if teile.size() == 3 and teile[2].is_valid_int() and int(teile[2]) % 2 == 1:
		variante = "b"
	(
		out
		. append(
			{
				"id": "spotlight",
				"text_key": "soul.erinnerung.spotlight_" + variante,
				"args": {},
			}
		)
	)


## Ist dieser Wunsch aktuell noch OFFEN (Bedingung aus echten Daten)?
static func wunsch_offen(state: Dictionary, wunsch_id: String) -> bool:
	match wunsch_id:
		"funkelpark":
			return int(_num(_dig(state, ["park", "visits"]))) <= 0
		"urlaub":
			var visited: Variant = _dig(state, ["vacation", "visited"])
			return not (visited is Dictionary) or (visited as Dictionary).is_empty()
		"streak7":
			return int(_num(_dig(state, ["daily", "streak"]))) < 7
		"kissenturm":
			var seen: Variant = _dig(state, ["soul", "surpriseAt"])
			return not (seen is Dictionary) or not (seen as Dictionary).has("sup_turm")
	return false


static func wunsch_erfuellt(state: Dictionary, wunsch_id: String) -> bool:
	return WUNSCH_IDS.has(wunsch_id) and not wunsch_offen(state, wunsch_id)


## Alle Wünsche, die Gooby JETZT fassen könnte: offen und noch nie erfüllt
## gefeiert (wunschErfuellt-Map). Stabile Reihenfolge.
static func offene_wuensche(state: Dictionary, slice: Dictionary) -> Array[String]:
	var gefeiert: Dictionary = slice.get("wunschErfuellt", {})
	var out: Array[String] = []
	for wunsch_id in WUNSCH_IDS:
		if wunsch_offen(state, wunsch_id) and not gefeiert.has(wunsch_id):
			out.append(wunsch_id)
	return out


## Spieltitel über den I18n-Katalog der Minigames ("mg.<id>.title"),
## Fallback: die rohe Id (nie crashen, nie leere Erinnerung).
static func _game_title(game_id: String) -> String:
	var key := "mg.%s.title" % game_id
	if I18nService.has_key(key):
		return I18nService.t(key)
	return game_id


static func _dest_title(dest_id: String) -> String:
	var key := "travel.ziel.%s" % dest_id
	if I18nService.has_key(key):
		return I18nService.t(key)
	return dest_id


## Fundort-Name über die Ranch-Welt-Strings ("rwelt.fund.<id>"),
## Fallback: rohe Id (Muster _dest_title — nie crashen, nie leer).
static func _fund_title(fund_id: String) -> String:
	var key := "rwelt.fund.%s" % fund_id
	if I18nService.has_key(key):
		return I18nService.t(key)
	return fund_id


static func _food_title(food_id: String) -> String:
	var key := "soul.essen.%s" % food_id
	if I18nService.has_key(key):
		return I18nService.t(key)
	return FoodCatalog.display_name(food_id)


static func _dig(state: Dictionary, path: Array) -> Variant:
	var node: Variant = state
	for part: Variant in path:
		if node is Dictionary and (node as Dictionary).has(part):
			node = node[part]
		else:
			return null
	return node


static func _num(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0


## Defensive Liste: eindeutige, nicht-leere Strings aus einem Array —
## alles andere (Müll-Typen, Duplikate) fällt still raus.
static func _string_liste(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (raw is Array):
		return out
	for eintrag: Variant in raw as Array:
		if not (eintrag is String):
			continue
		var id := str(eintrag)
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out

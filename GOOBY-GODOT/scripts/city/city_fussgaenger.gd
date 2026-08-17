class_name CityFussgaenger
extends RefCounted
## Fußgänger-Goobys der Stadt (Doc E §1.4 „Leben auf der Straße") — PURE:
## hier entstehen nur die ROUTEN und die Position darauf, die Meshes hängt
## CityScene ein. Jede Route ist ein Bürgersteig-Stück zwischen zwei
## benachbarten Straßen-Tiles, seitlich versetzt, und wird im Ping-Pong
## abgelaufen — NEU (FIX-5 „Leben"): an den Wendepunkten legen die Goobys
## eine Schaufenster-Pause ein (stehen, schauen zur Ladenzeile, manche
## winken), Routen vor Orts-Fassaden werden bevorzugt, und die Menge hängt
## an der Tageszeit (nachts sind nur Nachtschwärmer unterwegs).

## Seitlicher Versatz von der Fahrbahnmitte (m) — Tile ist 20 m breit, die
## Kenney-Straßenplatte ~12 m, also liegt 7,5 m sauber auf dem Gehweg.
const GEHWEG_M := 7.5
## Gehtempo-Fenster (m/s) — Gooby schlendert.
const TEMPO_MIN := 0.9
const TEMPO_MAX := 1.6
## Mehr als das kostet auf dem Handy mehr, als die Stadt dadurch gewinnt.
const MAX_GOOBYS := 14
## Schaufenster-Pause an den Wendepunkten (s).
const PAUSE_MIN_S := 2.5
const PAUSE_MAX_S := 7.0
## Anteil der Pausierer, die dabei winken.
const WINKER_ANTEIL := 0.4
## Tageszeit-Menge (CityScene fragt `anzahl(stunde)`).
const TAG_ANZAHL := 11
const NACHT_ANZAHL := 4
## Fell-Töne der Passanten (AC-Palette, bewusst nicht Spieler-Gooby-weiß).
const FELLE: Array[String] = ["#F2C14E", "#8FD06C", "#CFE9F5", "#FF7BA9", "#59C9B9", "#FFD166"]


## Wie viele Goobys schlendern zur Stunde? — W18/J4: folgt der
## CityRhythmus-Dichtekurve (morgens ruhig, mittags voll, nachts leer).
static func anzahl(stunde: float) -> int:
	return CityRhythmus.fussgaenger_anzahl(stunde)


## `anzahl` Routen aus der Karte würfeln (deterministisch über `seed`).
## Rückgabe je Eintrag: {von, nach, laenge, tempo, phase, tint, pause_s,
## winkt, blick} — Routen an Orts-Fassaden (Schaufenster) zuerst.
static func routen(karte: CityMap, anzahl_wunsch: int, seed_wert: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if karte == null or not karte.ist_geladen():
		return out
	var kandidaten := _kandidaten(karte)
	if kandidaten.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	# Deterministische Reihenfolge: strassen_tiles() kommt aus einem Dictionary
	# und ist damit NICHT sortiert — ohne das hier würfelt jeder Start anders.
	kandidaten.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["schaufenster"] != b["schaufenster"]:
				return bool(a["schaufenster"])
			return str(a["key"]) < str(b["key"])
	)
	var schaufenster_anzahl := 0
	for kandidat in kandidaten:
		if kandidat["schaufenster"]:
			schaufenster_anzahl += 1
	for i in mini(maxi(0, anzahl_wunsch), MAX_GOOBYS):
		# Erst die Schaufenster-Strecken besetzen (Läden wirken besucht),
		# dann den Rest der Stadt.
		var wahl: Dictionary
		if i < schaufenster_anzahl:
			wahl = kandidaten[i]
		else:
			wahl = kandidaten[rng.randi_range(0, kandidaten.size() - 1)]
		var seite := 1.0 if rng.randf() < 0.5 else -1.0
		var quer: Vector3 = wahl["quer"]
		var von: Vector3 = wahl["von"] + quer * GEHWEG_M * seite
		var nach: Vector3 = wahl["nach"] + quer * GEHWEG_M * seite
		var blick := quer * seite
		(
			out
			. append(
				{
					"von": von,
					"nach": nach,
					"laenge": von.distance_to(nach),
					"tempo": rng.randf_range(TEMPO_MIN, TEMPO_MAX),
					"phase": rng.randf(),
					"tint": Color(FELLE[rng.randi_range(0, FELLE.size() - 1)]),
					"pause_s": rng.randf_range(PAUSE_MIN_S, PAUSE_MAX_S),
					"winkt": rng.randf() < WINKER_ANTEIL,
					"blick": atan2(blick.x, blick.z),
				}
			)
		)
	return out


## Position + Blickrichtung auf einer Route zum Fortschritt `t` (beliebig
## groß, wird ge-ping-pongt: 0→1 hin, 1→2 zurück).
static func punkt(route: Dictionary, t: float) -> Dictionary:
	var von: Vector3 = route.get("von", Vector3.ZERO)
	var nach: Vector3 = route.get("nach", Vector3.ZERO)
	var zyklus := fposmod(t, 2.0)
	var hin := zyklus < 1.0
	var f := zyklus if hin else 2.0 - zyklus
	var pos := von.lerp(nach, f)
	var richtung := (nach - von) if hin else (von - nach)
	if richtung.length_squared() < 0.000001:
		richtung = Vector3.FORWARD
	return {"pos": pos, "heading": atan2(richtung.x, richtung.z)}


## Fortschritt nach `sekunden` (Startphase eingerechnet) — eine Runde hin
## und zurück ist t = 2.
static func fortschritt(route: Dictionary, sekunden: float) -> float:
	var laenge := maxf(0.001, float(route.get("laenge", 1.0)))
	var tempo := float(route.get("tempo", TEMPO_MIN))
	return float(route.get("phase", 0.0)) * 2.0 + sekunden * tempo / laenge


## Kompletter Zustand eines Spaziergängers nach `sekunden` — wie `punkt`,
## aber MIT Schaufenster-Pausen an beiden Wendepunkten: gehen → stehen
## (Blick zur Ladenzeile, optional winken) → zurück → stehen → …
## Rückgabe: {pos, heading, steht, winkt}.
static func zustand(route: Dictionary, sekunden: float) -> Dictionary:
	var laenge := maxf(0.001, float(route.get("laenge", 1.0)))
	var tempo := maxf(0.001, float(route.get("tempo", TEMPO_MIN)))
	var pause := maxf(0.0, float(route.get("pause_s", 0.0)))
	var gehzeit := laenge / tempo
	var zyklus_s := 2.0 * (gehzeit + pause)
	var t := fposmod(sekunden + float(route.get("phase", 0.0)) * zyklus_s, zyklus_s)
	var winkt := bool(route.get("winkt", false))
	var blick := float(route.get("blick", 0.0))
	if t < gehzeit:
		var bei := punkt(route, t / gehzeit)
		return {"pos": bei["pos"], "heading": bei["heading"], "steht": false, "winkt": false}
	if t < gehzeit + pause:
		var ende := punkt(route, 1.0)
		return {"pos": ende["pos"], "heading": blick, "steht": true, "winkt": winkt}
	if t < 2.0 * gehzeit + pause:
		var bei := punkt(route, 1.0 + (t - gehzeit - pause) / gehzeit)
		return {"pos": bei["pos"], "heading": bei["heading"], "steht": false, "winkt": false}
	var start := punkt(route, 0.0)
	return {"pos": start["pos"], "heading": blick, "steht": true, "winkt": winkt}


## Alle Straßen-Paare (Tile + rechter/unterer Nachbar) als Gehweg-Segmente;
## Segmente an einer Orts-Zufahrt gelten als Schaufenster-Strecken.
static func _kandidaten(karte: CityMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var laden_strassen := {}
	for eintrag: Dictionary in karte.orte():
		laden_strassen[CityMap._tile_von(eintrag.get("strasse", [0, 0]))] = true
	for tile in karte.strassen_tiles():
		if karte.ist_kreisel(tile):
			continue
		for schritt: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nachbar := tile + schritt
			if not karte.ist_strasse(nachbar) or karte.ist_kreisel(nachbar):
				continue
			var von := karte.tile_zu_welt(tile)
			var nach := karte.tile_zu_welt(nachbar)
			var laengs := (nach - von).normalized()
			(
				out
				. append(
					{
						"key": "%d_%d_%d_%d" % [tile.x, tile.y, nachbar.x, nachbar.y],
						"von": von,
						"nach": nach,
						"quer": Vector3(laengs.z, 0.0, -laengs.x),
						"schaufenster": laden_strassen.has(tile) or laden_strassen.has(nachbar),
					}
				)
			)
	return out

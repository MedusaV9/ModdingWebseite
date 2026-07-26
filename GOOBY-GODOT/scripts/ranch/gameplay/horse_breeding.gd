class_name RanchHorseBreeding
extends RefCounted
## Zucht & Fohlen (RW-2, IDEAS-3 Kap. 4) — PURE. Vererbung nach dem
## 4-Gen-Orte-Modell (RanchRassen), Stat-Wuerfel, Traechtigkeit als
## 48-h-Wartequest mit Fuersorge-Checkpoints und Fohlen-Aufzucht in 4
## sichtbaren Phasen. Anti-Excel: max 2 Traechtigkeiten, Stuten-Ruhezeit
## 5 Tage, Fohlenverkauf nur zum Festpreis — Gene erscheinen NIRGENDS
## als Buchstaben in der UI (Stammbaum zeigt Portraets).
##
## Zustand lebt im Save-Unterschluessel `ranch.zucht`
## (RanchPlaySlices.default_zucht): traechtigkeiten je Stuten-Id +
## ruhezeitBis. Zeit kommt IMMER als now_ms-Parameter (Test-Muster).

## Voraussetzungen (Kap. 4.1).
const MIN_LEVEL := 8
const MIN_BINDUNG := 45.0
const MIN_LAUNE := 60.0
const MAX_TRAECHTIGKEITEN := 2
const RUHEZEIT_MS := 5 * 86_400_000

## Traechtigkeit (Kap. 4.3): 48 h Grunddauer, 5 Checkpoints alle 9,6 h,
## jeder erledigte verkuerzt um 2 h → minimal 38 h. Verpasste schaden NIE.
const GRUND_DAUER_MS := 48 * 3_600_000
const CHECKPOINTS := 5
const CHECKPOINT_INTERVALL_MS := int(GRUND_DAUER_MS / 5.0)
const CHECKPOINT_BONUS_MS := 2 * 3_600_000
## Sichtbar: runder Bauch (+12 % Rumpf-Skalierung).
const BAUCH_SKALA := 1.12

## Stat-Wuerfel (Kap. 4.2): Erwartungswert +0,27 je Generation.
const WUERFEL: Array = [[-1, 0.15], [0, 0.55], [1, 0.20], [2, 0.08], [3, 0.02]]
## Abzeichen: P = 0,05 + 0,35 · (Eltern mit Merkmal) → 5/40/75 %.
const ABZEICHEN_BASIS := 0.05
const ABZEICHEN_JE_ELTER := 0.35
## Maehnenform: 40 % Mutter, 40 % Vater, 20 % Ueberraschung.
const MAEHNE_ELTER_CHANCE := 0.4
## Charakter je Zug: 45 % Mutter, 45 % Vater, 10 % zufaellig neu.
const CHARAKTER_ELTER_CHANCE := 0.45
## Rassensprung bei Mischlingen: 10 % schlagen ganz nach einem Elternteil.
const RASSENSPRUNG_CHANCE := 0.10
const MISCHLING_RASSE := "puschelmix"
## Groesse: Mittel der Eltern ± 5 %.
const GROESSE_VARIANZ := 0.05

## Fohlen-Phasen (Kap. 4.4): [Alter-Id, Dauer in Tagen, Skala].
const PHASEN: Array = [
	["fohlen", 3, 0.55], ["jaehrling", 4, 0.75], ["jungpferd", 3, 0.90], ["ausgewachsen", 0, 1.0]
]
## Beine in fruehen Phasen ueberproportional lang (+15 %).
const FOHLEN_BEIN_BONUS := 0.15
## Fohlenverkauf nur an den NPC-Ponyhof (Festpreis; rassen.json).
const FOHLEN_VERKAUF_FALLBACK := 150


## Duerfen Stute + Hengst jetzt zuechten? Pure — {"ok", "fehler": String}.
## fehler-Ids: level|bindung|laune|ruhezeit|voll|traechtig.
static func zucht_erlaubt(
	stute_id: String,
	stute: Dictionary,
	hengst: Dictionary,
	laune: float,
	zucht: Dictionary,
	now_ms: int
) -> Dictionary:
	var t: Dictionary = _dict(zucht, "traechtigkeiten")
	if t.has(stute_id):
		return {"ok": false, "fehler": "traechtig"}
	if t.size() >= MAX_TRAECHTIGKEITEN:
		return {"ok": false, "fehler": "voll"}
	var ruhe: Dictionary = _dict(zucht, "ruhezeitBis")
	if int(_num(ruhe.get(stute_id), 0.0)) > now_ms:
		return {"ok": false, "fehler": "ruhezeit"}
	for pferd: Dictionary in [stute, hengst]:
		if int(_num(pferd.get("level"), 1.0)) < MIN_LEVEL:
			return {"ok": false, "fehler": "level"}
		if _num(pferd.get("bindung"), 0.0) < MIN_BINDUNG:
			return {"ok": false, "fehler": "bindung"}
	if laune < MIN_LAUNE:
		return {"ok": false, "fehler": "laune"}
	return {"ok": true, "fehler": ""}


## Traechtigkeit starten: Vater-SNAPSHOT wird eingefroren (auch NPC-/
## Freundes-Deckhengste funktionieren so). Pure — neuer zucht-Slice.
static func traechtigkeit_starten(
	zucht: Dictionary, stute_id: String, vater: Dictionary, now_ms: int, seed_wert: int
) -> Dictionary:
	var z := zucht.duplicate(true)
	var t: Dictionary = _dict(z, "traechtigkeiten")
	t[stute_id] = {
		"startAt": now_ms,
		"checkpoints": 0,
		"letzterCheckpoint": -1,
		"seed": seed_wert,
		"vater": eltern_snapshot(vater),
	}
	z["traechtigkeiten"] = t
	return z


## Dauer der Traechtigkeit nach n erledigten Checkpoints (48 h − 2 h·n).
static func dauer_ms(checkpoints_erledigt: int) -> int:
	return GRUND_DAUER_MS - clampi(checkpoints_erledigt, 0, CHECKPOINTS) * CHECKPOINT_BONUS_MS


## Faelliger Fuersorge-Checkpoint (0..4) oder −1 (keiner offen).
static func checkpoint_faellig(traechtigkeit: Dictionary, now_ms: int) -> int:
	var start := int(_num(traechtigkeit.get("startAt"), 0.0))
	var idx := mini(CHECKPOINTS - 1, int(floor(float(now_ms - start) / CHECKPOINT_INTERVALL_MS)))
	if idx < 0 or idx <= int(_num(traechtigkeit.get("letzterCheckpoint"), -1.0)):
		return -1
	return idx


## Fuersorge-Checkpoint erledigen (Mash + Bauch striegeln): verkuerzt um
## 2 h. Pure — {"ok", "zucht"}. Verpasste Checkpoints schaden nie.
static func checkpoint_pflegen(zucht: Dictionary, stute_id: String, now_ms: int) -> Dictionary:
	var z := zucht.duplicate(true)
	var t: Dictionary = _dict(z, "traechtigkeiten")
	if not (t.get(stute_id) is Dictionary):
		return {"ok": false, "zucht": z}
	var eintrag: Dictionary = t[stute_id]
	var idx := checkpoint_faellig(eintrag, now_ms)
	if idx < 0:
		return {"ok": false, "zucht": z}
	eintrag["letzterCheckpoint"] = idx
	eintrag["checkpoints"] = int(_num(eintrag.get("checkpoints"), 0.0)) + 1
	t[stute_id] = eintrag
	z["traechtigkeiten"] = t
	return {"ok": true, "zucht": z}


## Ist die Geburt faellig?
static func geburt_bereit(zucht: Dictionary, stute_id: String, now_ms: int) -> bool:
	var t: Dictionary = _dict(zucht, "traechtigkeiten")
	if not (t.get(stute_id) is Dictionary):
		return false
	var eintrag: Dictionary = t[stute_id]
	var start := int(_num(eintrag.get("startAt"), 0.0))
	return now_ms >= start + dauer_ms(int(_num(eintrag.get("checkpoints"), 0.0)))


## Geburt: Fohlen wuerfeln, Traechtigkeit beenden, Ruhezeit 5 Tage.
## Pure — {"ok", "fohlen": Dictionary, "zucht": Dictionary}.
static func gebaeren(
	zucht: Dictionary, stute_id: String, mutter: Dictionary, now_ms: int
) -> Dictionary:
	if not geburt_bereit(zucht, stute_id, now_ms):
		return {"ok": false, "fohlen": {}, "zucht": zucht.duplicate(true)}
	var z := zucht.duplicate(true)
	var t: Dictionary = _dict(z, "traechtigkeiten")
	var eintrag: Dictionary = t[stute_id]
	var vater: Dictionary = eintrag.get("vater") if eintrag.get("vater") is Dictionary else {}
	var fohlen := wuerfle_fohlen(mutter, vater, int(_num(eintrag.get("seed"), 0.0)))
	fohlen["geborenAm"] = now_ms
	fohlen["eltern"] = [stute_id, str(vater.get("ref", "npc"))]
	fohlen["ahnen"] = {"mutter": eltern_snapshot(mutter), "vater": vater}
	t.erase(stute_id)
	z["traechtigkeiten"] = t
	var ruhe: Dictionary = z.get("ruhezeitBis") if z.get("ruhezeitBis") is Dictionary else {}
	ruhe[stute_id] = now_ms + RUHEZEIT_MS
	z["ruhezeitBis"] = ruhe
	return {"ok": true, "fohlen": fohlen, "zucht": z}


## Das Vererbungsmodell (Kap. 4.2), DETERMINISTISCH aus dem Seed:
## je Gen-Ort 1 zufaelliges Allel pro Elternteil, Stats = Mittel +
## Wuerfel, Rasse rein/gemischt/Rassensprung, Charakter 45/45/10.
static func wuerfle_fohlen(mutter: Dictionary, vater: Dictionary, seed_wert: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("fohlen|%d" % seed_wert)
	var gene := {}
	for ort in ["g", "h", "s", "glitzer"]:
		gene[ort] = [_erbe_allel(rng, mutter, ort), _erbe_allel(rng, vater, ort)]
	var stats := {}
	for k in RanchRassen.STAT_KEYS:
		var mitte := roundf((_stat_basis(mutter, k) + _stat_basis(vater, k)) / 2.0)
		stats[k] = clampi(int(mitte) + _wuerfel(rng), 1, 20)
	var fohlen := {
		"rasse": MISCHLING_RASSE,
		"gene": gene,
		"farbe": RanchRassen.fellfarbe_aus_genen(gene),
		"abzeichen": _erbe_abzeichen(rng, mutter, vater),
		"charakter": _erbe_charakter(rng, mutter, vater),
		"stats": stats,
		"groesse": snappedf(_erbe_groesse(rng, mutter, vater), 0.001),
		"stimmPitch": snappedf(rng.randf_range(0.85, 1.15), 0.001),
		"phasenOffset": snappedf(rng.randf(), 0.001),
		"alter": "fohlen",
		"eltern": [],
		"geborenAm": 0,
	}
	var rasse_m := str(mutter.get("rasse", "puschelhufer"))
	var rasse_v := str(vater.get("rasse", "puschelhufer"))
	if rasse_m == rasse_v:
		fohlen["rasse"] = rasse_m
	elif rng.randf() < RASSENSPRUNG_CHANCE:
		fohlen["rasse"] = rasse_m if rng.randf() < 0.5 else rasse_v
	else:
		fohlen["mixEigenheiten"] = _mix_eigenheiten(mutter, vater)
	return fohlen


## Eltern-Snapshot fuer Traechtigkeit + Stammbaum-Portraets: alles, was
## Vererbung + Portraet brauchen — OHNE tiefe Ahnen-Rekursion (max 1
## Ebene → 3 Generationen im Baum).
static func eltern_snapshot(pferd: Dictionary) -> Dictionary:
	var out := {
		"ref": str(pferd.get("ref", pferd.get("packId", "eigen"))),
		"name": str(pferd.get("name", "")),
		"rasse": str(pferd.get("rasse", "puschelhufer")),
		"farbe": str(pferd.get("farbe", "braun")),
		"gene": _tiefe_kopie(pferd.get("gene")),
		"stats": _tiefe_kopie(pferd.get("stats")),
		"abzeichen": _tiefe_kopie(pferd.get("abzeichen")),
		"charakter": _tiefe_kopie(pferd.get("charakter")),
		"groesse": _num(pferd.get("groesse"), 1.0),
	}
	var ahnen: Variant = pferd.get("ahnen")
	if ahnen is Dictionary:
		var flach := {}
		for rolle: Variant in ahnen.keys():
			if ahnen[rolle] is Dictionary:
				var kurz: Dictionary = (ahnen[rolle] as Dictionary).duplicate(true)
				kurz.erase("ahnen")
				flach[rolle] = kurz
		out["ahnen"] = flach
	return out


## Alters-Phase aus dem Geburtsstempel: fohlen (3 Tage) → jaehrling (4)
## → jungpferd (3) → ausgewachsen (fuer immer; kein Altern, kein Tod).
static func alter_fuer(geboren_am_ms: int, now_ms: int) -> String:
	if geboren_am_ms <= 0:
		return "ausgewachsen"
	var tage := float(now_ms - geboren_am_ms) / 86_400_000.0
	var grenze := 0.0
	for phase: Array in PHASEN:
		if int(phase[1]) <= 0:
			return str(phase[0])
		grenze += float(phase[1])
		if tage < grenze:
			return str(phase[0])
	return "ausgewachsen"


## Sichtbare Groessen-Skala einer Phase (0,55 / 0,75 / 0,90 / 1,00).
static func phasen_skala(alter: String) -> float:
	for phase: Array in PHASEN:
		if str(phase[0]) == alter:
			return float(phase[2])
	return 1.0


## Reitbar erst ab Jungpferd (Werte-Deckel 15 regelt horse_levels).
static func reitbar(alter: String) -> bool:
	return alter == "jungpferd" or alter == "ausgewachsen"


## Fohlen/Jaehrlinge haben ueberproportional lange Beine (+15 %).
static func bein_bonus(alter: String) -> float:
	return FOHLEN_BEIN_BONUS if (alter == "fohlen" or alter == "jaehrling") else 0.0


## "Erbe"-Badges fuer den Stammbaum (statt Zahlen): Wuerfel-Glueck je
## Stat + das Glitzer-Geheimnis. Ids, Texte kommen aus rpferd.erbe.*.
static func erbe_badges(fohlen: Dictionary) -> Array:
	var out: Array = []
	var ahnen: Dictionary = fohlen.get("ahnen") if fohlen.get("ahnen") is Dictionary else {}
	var mutter: Dictionary = ahnen.get("mutter") if ahnen.get("mutter") is Dictionary else {}
	var vater: Dictionary = ahnen.get("vater") if ahnen.get("vater") is Dictionary else {}
	for k in RanchRassen.STAT_KEYS:
		var mitte := roundf((_stat_basis(mutter, k) + _stat_basis(vater, k)) / 2.0)
		if _stat_basis(fohlen, k) > mitte:
			out.append(k)
	var glitzer: Array = RanchRassen.allele(
		fohlen.get("gene") if fohlen.get("gene") is Dictionary else {}, "glitzer", "g0"
	)
	if glitzer.has("gx"):
		out.append("glitzer")
	return out


## --------------------------------------------------------------- intern


static func _erbe_allel(rng: RandomNumberGenerator, elter: Dictionary, ort: String) -> String:
	var gene: Dictionary = elter.get("gene") if elter.get("gene") is Dictionary else {}
	var allele := RanchRassen.allele(gene, ort, _fallback_allel(ort))
	return str(allele[rng.randi_range(0, 1)])


static func _fallback_allel(ort: String) -> String:
	match ort:
		"g":
			return "B"
		"h":
			return "h0"
		"s":
			return "s0"
		_:
			return "g0"


static func _wuerfel(rng: RandomNumberGenerator) -> int:
	var wurf := rng.randf()
	var summe := 0.0
	for eintrag: Array in WUERFEL:
		summe += float(eintrag[1])
		if wurf < summe:
			return int(eintrag[0])
	return int(WUERFEL[-1][0])


static func _erbe_abzeichen(
	rng: RandomNumberGenerator, mutter: Dictionary, vater: Dictionary
) -> Dictionary:
	var abz_m: Dictionary = _dict(mutter, "abzeichen")
	var abz_v: Dictionary = _dict(vater, "abzeichen")
	var out := {}
	for merkmal in RanchRassen.ABZEICHEN_MERKMALE:
		var n := 1 if bool(abz_m.get(merkmal, false)) else 0
		n += 1 if bool(abz_v.get(merkmal, false)) else 0
		out[merkmal] = rng.randf() < ABZEICHEN_BASIS + ABZEICHEN_JE_ELTER * n
	var socken: Array = []
	var socken_m: Array = abz_m.get("socken") if abz_m.get("socken") is Array else []
	var socken_v: Array = abz_v.get("socken") if abz_v.get("socken") is Array else []
	for i in 4:
		var n := 1 if i < socken_m.size() and int(_num(socken_m[i], 0.0)) == 1 else 0
		n += 1 if i < socken_v.size() and int(_num(socken_v[i], 0.0)) == 1 else 0
		socken.append(1 if rng.randf() < ABZEICHEN_BASIS + ABZEICHEN_JE_ELTER * n else 0)
	out["socken"] = socken
	var wurf := rng.randf()
	if wurf < MAEHNE_ELTER_CHANCE:
		out["maehnenform"] = str(abz_m.get("maehnenform", "glatt"))
	elif wurf < MAEHNE_ELTER_CHANCE * 2.0:
		out["maehnenform"] = str(abz_v.get("maehnenform", "glatt"))
	else:
		var formen := RanchRassen.MAEHNENFORMEN
		out["maehnenform"] = formen[rng.randi_range(0, formen.size() - 1)]
	return out


static func _erbe_charakter(
	rng: RandomNumberGenerator, mutter: Dictionary, vater: Dictionary
) -> Array:
	var out: Array = []
	for slot in 2:
		var zug := ""
		var guard := 0
		while (zug == "" or out.has(zug)) and guard < 32:
			guard += 1
			var wurf := rng.randf()
			if wurf < CHARAKTER_ELTER_CHANCE:
				zug = _zufalls_zug(rng, mutter)
			elif wurf < CHARAKTER_ELTER_CHANCE * 2.0:
				zug = _zufalls_zug(rng, vater)
			else:
				var alle := RanchRassen.CHARAKTERZUEGE
				zug = alle[rng.randi_range(0, alle.size() - 1)]
		out.append(zug)
	return out


static func _zufalls_zug(rng: RandomNumberGenerator, elter: Dictionary) -> String:
	var charakter: Variant = elter.get("charakter")
	if charakter is Array and (charakter as Array).size() > 0:
		var liste: Array = charakter
		return str(liste[rng.randi_range(0, liste.size() - 1)])
	var alle := RanchRassen.CHARAKTERZUEGE
	return alle[rng.randi_range(0, alle.size() - 1)]


static func _erbe_groesse(
	rng: RandomNumberGenerator, mutter: Dictionary, vater: Dictionary
) -> float:
	var mitte := (_num(mutter.get("groesse"), 1.0) + _num(vater.get("groesse"), 1.0)) / 2.0
	return mitte * (1.0 + rng.randf_range(-GROESSE_VARIANZ, GROESSE_VARIANZ))


## Beide Rassen-Eigenheiten in halber Staerke (Kap. 4.2 "Puschelmix").
static func _mix_eigenheiten(mutter: Dictionary, vater: Dictionary) -> Array:
	var out: Array = []
	for elter: Dictionary in [mutter, vater]:
		var eigen := _eigenheit_id(elter)
		if eigen != "" and not out.has(eigen):
			out.append(eigen)
	return out


static func _eigenheit_id(pferd: Dictionary) -> String:
	var mix: Variant = pferd.get("mixEigenheiten")
	if mix is Array and (mix as Array).size() > 0:
		return str((mix as Array)[0])
	var balance := RanchRassen.load_balance()
	return str(
		RanchRassen.rasse(balance, str(pferd.get("rasse", "puschelhufer"))).get("eigenheit", "")
	)


static func _stat_basis(pferd: Dictionary, key: String) -> float:
	return clampf(_num(_dict(pferd, "stats").get(key), 10.0), 1.0, 20.0)


static func _tiefe_kopie(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


static func _dict(d: Dictionary, key: String) -> Dictionary:
	var raw: Variant = d.get(key)
	return raw if raw is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback

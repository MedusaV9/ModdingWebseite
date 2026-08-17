extends RefCounted
## Spline-Werkzeug des Spielzeug-Rennens — der geometrische Teil des
## zahlengleichen Ports von GOOBY/src/minigames/games/toyRacer.logic.js
## (emitPiece / buildTrack / pointAt / Zonenabfragen). Liegt in einer eigenen
## Datei, weil die Rennlogik sonst über die 1000-Zeilen-Grenze läuft; die
## Zahlen sind unverändert. `toy_racer_logic.gd` reicht die öffentliche API
## durch, die Ansicht nutzt point_at() direkt.

## Streckenteile: Geometrie-Semantik je Typ (`model` = das Web-GLB, hier nur
## als Herkunftsnachweis — die 2D-Ansicht zeichnet aus den Stützstellen).
const PIECE_LIB := {
	"straight": {"kind": "straight", "len": 4.0, "dy": 0.0, "model": "track-narrow-straight"},
	"bumpUp": {"kind": "straight", "len": 4.0, "dy": 0.5, "model": "track-narrow-straight-bump-up"},
	"bumpDown":
	{"kind": "straight", "len": 4.0, "dy": -0.5, "model": "track-narrow-straight-bump-down"},
	"cornerS": {"kind": "corner", "r": 2.0, "model": "track-narrow-corner-small"},
	"cornerL": {"kind": "corner", "r": 4.0, "model": "track-narrow-corner-large"},
	"curve": {"kind": "shift", "len": 4.0, "shift": 2.0, "model": "track-narrow-curve"},
	"loop":
	{
		"kind": "loop",
		"len": 4.0,
		"shift": 1.0,
		"r": 1.7,
		"entry": 2.0,
		"model": "track-narrow-looping",
		"originOffset": 2.0,
	},
}

## Genau 2 Layout-Vorlagen; der Seed wählt eine + variiert das Buckelpaar.
const TEMPLATES := [
	{
		"id": "rugRing",
		"pieces":
		[
			"straight",
			"straight",
			"cornerL",
			"cornerL",
			"straight",
			"straight",
			"cornerL",
			"cornerL",
		],
		"bumpPair": [4, 5],
	},
	{
		"id": "loopBoulevard",
		"pieces": ["loop", "loop", "cornerS", "cornerL", "straight", "curve", "cornerS", "cornerL"],
		"bumpPair": [],
	},
]

## Gitterrichtungen (x, z): 0=+z · 1=−x · 2=−z · 3=+x.
const DIRS := [[0.0, 1.0], [-1.0, 0.0], [0.0, -1.0], [1.0, 0.0]]

## Feiner Parameterschritt beim Emittieren eines Streckenteils.
const FINE := 0.06


static func left_of(d: int) -> int:
	return (d + 1) % 4


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _vlen(v: Array) -> float:
	return sqrt(float(v[0]) * float(v[0]) + float(v[1]) * float(v[1]) + float(v[2]) * float(v[2]))


static func _norm(v: Array) -> Array:
	var n := _vlen(v)
	if n == 0.0:
		n = 1.0
	return [float(v[0]) / n, float(v[1]) / n, float(v[2]) / n]


## Feine Stützpunkte für EIN Streckenteil (Web `emitPiece`).
static func emit_piece(def: Dictionary, cur: Dictionary) -> Dictionary:
	var h: Array = DIRS[int(cur["dir"])]
	var l: Array = DIRS[left_of(int(cur["dir"]))]
	var points: Array[Dictionary] = []
	var cx := float(cur["x"])
	var cy := float(cur["y"])
	var cz := float(cur["z"])
	var kind := str(def["kind"])
	if kind == "straight":
		var length := float(def["len"])
		var dy := float(def["dy"])
		var n := int(ceil(length / FINE))
		for i in n:
			var u := (float(i) / n) * length
			var t := u / length
			(
				points
				. append(
					{
						"p": [cx + float(h[0]) * u, cy + dy * _smooth(t), cz + float(h[1]) * u],
						"up": [0.0, 1.0, 0.0],
					}
				)
			)
		return {
			"points": points,
			"next":
			{
				"x": cx + float(h[0]) * length,
				"y": cy + dy,
				"z": cz + float(h[1]) * length,
				"dir": int(cur["dir"]),
			},
		}
	if kind == "corner":
		var r := float(def["r"])
		var ccx := cx + float(l[0]) * r
		var ccz := cz + float(l[1]) * r
		var arc := (PI / 2.0) * r
		var n := int(ceil(arc / FINE))
		for i in n:
			var phi := (float(i) / n) * (PI / 2.0)
			(
				points
				. append(
					{
						"p":
						[
							ccx - float(l[0]) * r * cos(phi) + float(h[0]) * r * sin(phi),
							cy,
							ccz - float(l[1]) * r * cos(phi) + float(h[1]) * r * sin(phi),
						],
						"up": [0.0, 1.0, 0.0],
					}
				)
			)
		return {
			"points": points,
			"next":
			{
				"x": cx + float(h[0]) * r + float(l[0]) * r,
				"y": cy,
				"z": cz + float(h[1]) * r + float(l[1]) * r,
				"dir": left_of(int(cur["dir"])),
			},
		}
	if kind == "shift":
		var length := float(def["len"])
		var shift := float(def["shift"])
		var n := int(ceil(length / FINE))
		for i in n:
			var u := (float(i) / n) * length
			var t := u / length
			(
				points
				. append(
					{
						"p":
						[
							cx + float(h[0]) * u + float(l[0]) * shift * _smooth(t),
							cy,
							cz + float(h[1]) * u + float(l[1]) * shift * _smooth(t),
						],
						"up": [0.0, 1.0, 0.0],
					}
				)
			)
		return {
			"points": points,
			"next":
			{
				"x": cx + float(h[0]) * length + float(l[0]) * shift,
				"y": cy,
				"z": cz + float(h[1]) * length + float(l[1]) * shift,
				"dir": int(cur["dir"]),
			},
		}
	# Senkrechter Looping: Einfahrt → 2π-Kreis in der (Fahrt, y)-Ebene mit
	# 1 Einheit Korkenzieher-Drift nach links → Ausfahrt.
	var radius := float(def["r"])
	var total_len := float(def["len"])
	var loop_shift := float(def["shift"])
	var entry := float(def.get("entry", total_len / 2.0))
	var exit_len := total_len - entry
	var n_e := int(ceil(entry / FINE))
	for i in n_e:
		var u := (float(i) / n_e) * entry
		points.append(
			{"p": [cx + float(h[0]) * u, cy, cz + float(h[1]) * u], "up": [0.0, 1.0, 0.0]}
		)
	var c0x := cx + float(h[0]) * entry
	var c0z := cz + float(h[1]) * entry
	var n_c := int(ceil((2.0 * PI * radius) / FINE))
	for i in n_c:
		var th := (float(i) / n_c) * PI * 2.0
		var drift := (th / (PI * 2.0)) * loop_shift
		(
			points
			. append(
				{
					"p":
					[
						c0x + float(h[0]) * radius * sin(th) + float(l[0]) * drift,
						cy + radius * (1.0 - cos(th)),
						c0z + float(h[1]) * radius * sin(th) + float(l[1]) * drift,
					],
					"up": [-float(h[0]) * sin(th), cos(th), -float(h[1]) * sin(th)],
				}
			)
		)
	var ex_x := c0x + float(l[0]) * loop_shift
	var ex_z := c0z + float(l[1]) * loop_shift
	var n_x := int(ceil(exit_len / FINE))
	for i in n_x:
		var u := (float(i) / n_x) * exit_len
		points.append(
			{"p": [ex_x + float(h[0]) * u, cy, ex_z + float(h[1]) * u], "up": [0.0, 1.0, 0.0]}
		)
	return {
		"points": points,
		"next":
		{
			"x": cx + float(h[0]) * total_len + float(l[0]) * loop_shift,
			"y": cy,
			"z": cz + float(h[1]) * total_len + float(l[1]) * loop_shift,
			"dir": int(cur["dir"]),
		},
	}


## Gesäter Kurs (2 Vorlagen × Seeds) inkl. Bogenlängen-Tabelle.
static func build_track(seed_value: int, tune: Dictionary) -> Dictionary:
	var rng := GoobyRng.new((seed_value ^ 0x51AB7E0D) & 0xFFFFFFFF)
	var tpl_idx := 0 if rng.next() < 0.5 else 1
	var tpl: Dictionary = TEMPLATES[tpl_idx]
	var bump_pair: Array = tpl["bumpPair"]
	var use_bumps := not bump_pair.is_empty() and rng.next() < 0.6
	var types: Array[String] = []
	var tpl_pieces: Array = tpl["pieces"]
	for i in tpl_pieces.size():
		if use_bumps and i == int(bump_pair[0]):
			types.append("bumpUp")
		elif use_bumps and i == int(bump_pair[1]):
			types.append("bumpDown")
		else:
			types.append(str(tpl_pieces[i]))

	var cur := {"x": 0.0, "y": 0.0, "z": 0.0, "dir": 0}
	var pieces: Array[Dictionary] = []
	var fine: Array[Dictionary] = []
	var piece_ranges: Array[Dictionary] = []
	for type_name in types:
		var def: Dictionary = PIECE_LIB[type_name]
		(
			pieces
			. append(
				{
					"type": type_name,
					"model": str(def["model"]),
					"x": float(cur["x"]),
					"y": float(cur["y"]),
					"z": float(cur["z"]),
					"dir": int(cur["dir"]),
					"originOffset": float(def.get("originOffset", 0.0)),
				}
			)
		)
		var from := fine.size()
		var out := emit_piece(def, cur)
		for pt: Dictionary in out["points"]:
			fine.append(pt)
		(
			piece_ranges
			. append(
				{
					"type": type_name,
					"from": from,
					"to": fine.size(),
					"turnDeg": 90.0 if str(def["kind"]) == "corner" else 0.0,
				}
			)
		)
		cur = out["next"]

	# Gleichmäßige Bogenlängen-Abtastung
	var step := float(tune["SAMPLE_STEP"])
	var samples: Array[Dictionary] = []
	var acc := 0.0
	var prev: Dictionary = fine[0]
	samples.append({"p": (prev["p"] as Array).duplicate(), "up": (prev["up"] as Array).duplicate()})
	var fine_s: Array[float] = [0.0]
	for i in range(1, fine.size() + 1):
		var pt: Dictionary = fine[i % fine.size()]
		var pp: Array = prev["p"]
		var np: Array = pt["p"]
		var d := sqrt(
			(
				(float(np[0]) - float(pp[0])) * (float(np[0]) - float(pp[0]))
				+ (float(np[1]) - float(pp[1])) * (float(np[1]) - float(pp[1]))
				+ (float(np[2]) - float(pp[2])) * (float(np[2]) - float(pp[2]))
			)
		)
		var seg_start := acc
		acc += d
		fine_s.append(acc)
		while samples.size() * step <= acc and d > 0.0:
			var target := samples.size() * step
			var f := (target - seg_start) / d
			var pu: Array = prev["up"]
			var nu: Array = pt["up"]
			(
				samples
				. append(
					{
						"p":
						[
							float(pp[0]) + (float(np[0]) - float(pp[0])) * f,
							float(pp[1]) + (float(np[1]) - float(pp[1])) * f,
							float(pp[2]) + (float(np[2]) - float(pp[2])) * f,
						],
						"up":
						_norm(
							[
								float(pu[0]) + (float(nu[0]) - float(pu[0])) * f,
								float(pu[1]) + (float(nu[1]) - float(pu[1])) * f,
								float(pu[2]) + (float(nu[2]) - float(pu[2])) * f,
							]
						),
					}
				)
			)
		prev = pt
	var lap_len := acc

	# Tangenten (zentrale Differenz auf dem geschlossenen Ring) + Gierkrümmung
	var n := samples.size()
	for i in n:
		var a: Array = samples[(i - 1 + n) % n]["p"]
		var b: Array = samples[(i + 1) % n]["p"]
		samples[i]["t"] = _norm(
			[
				float(b[0]) - float(a[0]),
				float(b[1]) - float(a[1]),
				float(b[2]) - float(a[2]),
			]
		)
	for i in n:
		var t0: Array = samples[i]["t"]
		var t1: Array = samples[(i + 1) % n]["t"]
		var h0 := sqrt(float(t0[0]) * float(t0[0]) + float(t0[2]) * float(t0[2]))
		var h1 := sqrt(float(t1[0]) * float(t1[0]) + float(t1[2]) * float(t1[2]))
		if h0 < 0.5 or h1 < 0.5:
			samples[i]["kappa"] = 0.0
			continue
		var cross := float(t0[2]) * float(t1[0]) - float(t0[0]) * float(t1[2])
		var dot := (float(t0[0]) * float(t1[0]) + float(t0[2]) * float(t1[2])) / (h0 * h1)
		samples[i]["kappa"] = atan2(cross, maxf(-1.0, minf(1.0, dot))) / step

	var corner_zones: Array[Dictionary] = []
	var loop_zones: Array[Dictionary] = []
	for r: Dictionary in piece_ranges:
		var s0 := fine_s[int(r["from"])]
		var s1 := fine_s[mini(int(r["to"]), fine_s.size() - 1)]
		if float(r["turnDeg"]) > 0.0:
			corner_zones.append({"s0": s0, "s1": s1, "turnDeg": float(r["turnDeg"])})
		if str(r["type"]) == "loop":
			loop_zones.append({"s0": s0, "s1": s1})

	var item_rows: Array[Dictionary] = []
	for f: float in tune["ITEM_ROW_FRACTIONS"]:
		var s := f * lap_len
		for z: Dictionary in loop_zones:
			if s > float(z["s0"]) - 1.0 and s < float(z["s1"]) + 0.5:
				s = fmod(float(z["s1"]) + 0.8, lap_len)
		var boxes: Array[Dictionary] = []
		for lat: float in tune["ITEM_BOX_LATS"]:
			boxes.append({"lat": lat, "respawnT": 0.0})
		item_rows.append({"s": s, "boxes": boxes})

	return {
		"templateId": str(tpl["id"]),
		"hasBumps": use_bumps,
		"pieces": pieces,
		"samples": samples,
		"step": step,
		"lapLen": lap_len,
		"cornerZones": corner_zones,
		"loopZones": loop_zones,
		"itemRows": item_rows,
	}


## Mittelspline bei Bogenlänge s (läuft rundenweise um).
static func point_at(track: Dictionary, s: float) -> Dictionary:
	var samples: Array = track["samples"]
	var n := samples.size()
	var u := fmod(s, float(track["lapLen"])) / float(track["step"])
	if u < 0.0:
		u += n
	var i0 := int(floorf(u)) % n
	var i1 := (i0 + 1) % n
	var f := u - floorf(u)
	var a: Dictionary = samples[i0]
	var b: Dictionary = samples[i1]
	var p := _lerp3(a["p"], b["p"], f)
	var t := _norm(_lerp3(a["t"], b["t"], f))
	var up := _norm(_lerp3(a["up"], b["up"], f))
	var right := _norm(
		[
			float(t[1]) * float(up[2]) - float(t[2]) * float(up[1]),
			float(t[2]) * float(up[0]) - float(t[0]) * float(up[2]),
			float(t[0]) * float(up[1]) - float(t[1]) * float(up[0]),
		]
	)
	return {"p": p, "t": t, "up": up, "right": right, "kappa": float(a["kappa"])}


static func _lerp3(x: Array, y: Array, f: float) -> Array:
	return [
		float(x[0]) + (float(y[0]) - float(x[0])) * f,
		float(x[1]) + (float(y[1]) - float(x[1])) * f,
		float(x[2]) + (float(y[2]) - float(x[2])) * f,
	]


static func in_loop_zone(track: Dictionary, s: float) -> bool:
	var lap_len := float(track["lapLen"])
	var sm := fmod(fmod(s, lap_len) + lap_len, lap_len)
	for z: Dictionary in track["loopZones"]:
		if sm >= float(z["s0"]) and sm <= float(z["s1"]):
			return true
	return false


## Kurvenzone (mit Vorausschau) über minDeg, sonst {}.
static func corner_zone_at(
	track: Dictionary, s: float, lookahead := 0.0, min_deg := 0.0
) -> Dictionary:
	var lap_len := float(track["lapLen"])
	var sm := fmod(fmod(s + lookahead, lap_len) + lap_len, lap_len)
	for z: Dictionary in track["cornerZones"]:
		if float(z["turnDeg"]) >= min_deg and sm >= float(z["s0"]) and sm <= float(z["s1"]):
			return z
	return {}

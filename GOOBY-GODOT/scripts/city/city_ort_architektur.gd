class_name CityOrtArchitektur
extends RefCounted
## Orts-Architektur-Planer (GOOBY-WELT/STADT, EVAL-2026-08 B §2: „Stadtorte
## werden durch übergroße Labels statt Architektur erklärt") — PURE und
## headless-testbar: pro Ort-Id entsteht hier der PLAN der unterscheidbaren
## Fassaden-Elemente in LOKALEN Koordinaten (+Z zeigt zur Straße, +X quer,
## Y hoch, Maße in Metern; Fassaden-Front der 10er-Gebäude liegt bei z≈5).
## Gebaut wird der Plan von CityOrtBau als echte Nodes.
##
## Jeder Laden bekommt: ein TÜRPORTAL in Signaturfarbe, ein 3D-LOGO über
## dem Eingang (Karotte, grünes Kreuz, Pille, Knochen, Stern-Burst, Blitz,
## Brief, Hammer …), SCHAUFENSTER mit Waren und passende VORPLATZ-Requisiten
## (Einkaufswagen, Paket-Stapel, Reifenstapel, Farbeimer …). Schilder werden
## dadurch klein/diegetisch (CityBau hängt sie niedriger und gedeckelt).

## Element-Rollen für Tests/Übersicht: jedes Laden-Portal braucht mindestens
## ein "logo" und ein "schaufenster"-Element (Architektur statt Text).
const ROLLEN: Array[String] = ["portal", "logo", "schaufenster", "deko", "neon"]

## Signatur-Neonfarben je Ort (nachts leuchtende Akzentleiste am Portal).
const NEON_FARBEN := {
	"rehwei": "#FF6F61",
	"goobytheke": "#4FBF8B",
	"gouhbus": "#8FD0E8",
	"tierarzt": "#8ED0A0",
	"flughafen": "#9BD7E8",
	"baumarkt": "#F2A03D",
	"post": "#FFD166",
	"pow": "#F2C14E",
	"autohaus": "#8FD0E8",
	"goobyman": "#D94F8C",
	"funkelpark": "#F781B0",
}

## Fassaden-Front (z) der 10er-Orte-Gebäude — Panels kleben knapp davor.
const FRONT_Z := 5.05


## Alle Ort-Ids mit eigenem Architektur-Plan (für Tests).
static func orte_mit_plan() -> Array[String]:
	var ids: Array[String] = []
	for id: String in NEON_FARBEN:
		ids.append(id)
	ids.append("wochenmarkt")
	return ids


## Signatur-Neonfarbe eines Orts ("" = keine Neonleiste).
static func neon_farbe(ort_id: String) -> String:
	return str(NEON_FARBEN.get(ort_id, ""))


## Architektur-Plan eines Orts (deterministisch, lokale Koordinaten).
static func plan(ort_id: String) -> Array[Dictionary]:
	match ort_id:
		"rehwei":
			return _rehwei()
		"goobytheke":
			return _goobytheke()
		"gouhbus":
			return _gouhbus()
		"tierarzt":
			return _tierarzt()
		"flughafen":
			return _flughafen()
		"baumarkt":
			return _baumarkt()
		"post":
			return _post()
		"pow":
			return _pow()
		"autohaus":
			return _autohaus()
		"wochenmarkt":
			return _wochenmarkt()
		"goobyman":
			return _goobyman()
		"funkelpark":
			return _funkelpark_tor()
		_:
			return []


## ------------------------------------------------------------ Bausteine


static func _el(
	form: String, off: Vector3, size: Vector3, farbe: String, extra: Dictionary = {}
) -> Dictionary:
	var out := {"form": form, "off": off, "size": size, "farbe": farbe}
	out.merge(extra)
	return out


static func _box(off: Vector3, size: Vector3, farbe: String, extra: Dictionary = {}) -> Dictionary:
	return _el("box", off, size, farbe, extra)


## Zylinder: size = (radius_oben, hoehe, radius_unten).
static func _zyl(off: Vector3, size: Vector3, farbe: String, extra: Dictionary = {}) -> Dictionary:
	return _el("zyl", off, size, farbe, extra)


static func _kugel(off: Vector3, radius: float, farbe: String, extra := {}) -> Dictionary:
	return _el("kugel", off, Vector3(radius, radius, radius), farbe, extra)


static func _glb(pfad: String, off: Vector3, groesse: float, extra: Dictionary = {}) -> Dictionary:
	var out := {"form": "glb", "glb": pfad, "off": off, "scale": groesse}
	out.merge(extra)
	return out


## Türportal in Signaturfarbe: zwei Pfosten + Sturz — DAS Wiedererkennungs-
## Element jeder Ladenfront (ersetzt „alle Türen sehen gleich aus").
static func _portal(farbe: String, breite := 2.6, hoehe := 2.9) -> Array[Dictionary]:
	var halb := breite * 0.5
	return [
		_box(Vector3(-halb, hoehe * 0.5, FRONT_Z), Vector3(0.3, hoehe, 0.34), farbe, _rp("portal")),
		_box(Vector3(halb, hoehe * 0.5, FRONT_Z), Vector3(0.3, hoehe, 0.34), farbe, _rp("portal")),
		_box(
			Vector3(0.0, hoehe + 0.18, FRONT_Z),
			Vector3(breite + 0.7, 0.4, 0.4),
			farbe,
			_rp("portal")
		),
	]


## Schaufenster: helle Scheibe + Sims + Waren-Brett davor (Waren = GLBs).
static func _schaufenster(
	x: float, farbe: String, waren: Array[String], waren_scale := 2.2
) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		_box(
			Vector3(x, 1.75, FRONT_Z),
			Vector3(3.0, 1.9, 0.14),
			"#EAF4F8",
			{"rolle": "schaufenster", "glow": 0.28}
		),
		_box(Vector3(x, 0.72, FRONT_Z + 0.12), Vector3(3.2, 0.24, 0.5), farbe, _rp("schaufenster")),
	]
	for i in waren.size():
		var wx := x + (float(i) - float(waren.size() - 1) * 0.5) * 0.9
		out.append(
			_glb(
				"essen/%s.glb" % waren[i],
				Vector3(wx, 0.86, FRONT_Z + 0.16),
				waren_scale,
				{"rot": float(i * 40 - 30), "rolle": "schaufenster"}
			)
		)
	return out


## Markisen-Band über der Front (gestreift über 3 Segmente).
static func _markisen_band(farbe_a: String, farbe_b: String, y := 3.3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 5:
		var x := (float(i) - 2.0) * 1.7
		var farbe := farbe_a if i % 2 == 0 else farbe_b
		out.append(
			_box(
				Vector3(x, y, FRONT_Z + 0.45),
				Vector3(1.7, 0.16, 1.1),
				farbe,
				{"rot_x": -16.0, "rolle": "deko"}
			)
		)
	return out


## Einkaufswagen (Korb + Bügel + 4 Mini-Rollen) — REHWEI-Vorplatz.
static func _einkaufswagen(off: Vector3, rot: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		_box(off + Vector3(0, 0.62, 0), Vector3(0.72, 0.5, 1.0), "#C8D4DC", _rd(rot)),
		_box(off + Vector3(0, 1.02, -0.62), Vector3(0.7, 0.08, 0.3), "#E8524A", _rd(rot)),
	]
	for ecke: Vector2 in [Vector2(-0.3, -0.4), Vector2(0.3, -0.4), Vector2(-0.3, 0.4)]:
		out.append(_kugel(off + Vector3(ecke.x, 0.14, ecke.y), 0.11, "#5B4636", _rd(rot)))
	out.append(_kugel(off + Vector3(0.3, 0.14, 0.4), 0.11, "#5B4636", _rd(rot)))
	return out


static func _rp(rolle: String) -> Dictionary:
	return {"rolle": rolle}


static func _rd(rot: float) -> Dictionary:
	return {"rot": rot}


## ------------------------------------------------------------- Die Orte


## REHWEI (Supermarkt, rot): Karotten-Logo, Obst-Schaufenster, Markisen-
## Band rot/weiß, Einkaufswagen + Kisten vor der Tür.
static func _rehwei() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#E8524A"))
	out.append_array(_markisen_band("#E8524A", "#FFF4E8"))
	out.append_array(_schaufenster(-3.2, "#E8524A", ["apple", "banana", "tomato"] as Array[String]))
	out.append_array(_schaufenster(3.2, "#E8524A", ["salad", "grapes", "carrot"] as Array[String]))
	# Karotten-Logo überm Portal: oranger Kegel + grüner Schopf.
	out.append(
		_zyl(
			Vector3(0.0, 4.35, FRONT_Z + 0.3),
			Vector3(0.06, 1.15, 0.34),
			"#F2A03D",
			{"rot_x": 180.0, "rolle": "logo"}
		)
	)
	out.append(_kugel(Vector3(0.0, 5.05, FRONT_Z + 0.3), 0.26, "#4FBF8B", _rp("logo")))
	out.append_array(_einkaufswagen(Vector3(-4.6, 0.0, 7.2), 24.0))
	out.append_array(_einkaufswagen(Vector3(-5.3, 0.0, 6.4), 12.0))
	out.append(_glb("innen/crate_carrots.gltf", Vector3(4.6, 0.0, 6.6), 3.6, _rd(-15.0)))
	out.append(_glb("vorstadt/planter.glb", Vector3(6.2, 0.0, 6.2), 4.0))
	return out


## GOOBYTHEKE (Apotheke, grün): grünes Kreuz-Logo, Fläschchen-Schaufenster,
## weiße Front-Paneele, Wartebänkchen.
static func _goobytheke() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#4FBF8B"))
	# Grünes Apotheken-Kreuz (2 Balken) auf weißer Tafel.
	out.append(_box(Vector3(0.0, 4.6, FRONT_Z + 0.2), Vector3(1.7, 1.7, 0.14), "#FFFFFF"))
	out.append(
		_box(Vector3(0.0, 4.6, FRONT_Z + 0.32), Vector3(1.3, 0.44, 0.1), "#2FA36B", _rp("logo"))
	)
	out.append(
		_box(Vector3(0.0, 4.6, FRONT_Z + 0.32), Vector3(0.44, 1.3, 0.1), "#2FA36B", _rp("logo"))
	)
	# Fläschchen-Schaufenster: bunte Mini-Flaschen (Zylinder + Kugelkorken).
	out.append(
		_box(
			Vector3(-3.0, 1.75, FRONT_Z),
			Vector3(2.8, 1.9, 0.14),
			"#EAF4F8",
			{"rolle": "schaufenster", "glow": 0.28}
		)
	)
	out.append(
		_box(Vector3(-3.0, 0.72, FRONT_Z + 0.12), Vector3(3.0, 0.24, 0.5), "#4FBF8B", _rp("deko"))
	)
	var flaschen_farben: Array[String] = ["#B58CE4", "#8FD0E8", "#F2C14E", "#4FBF8B"]
	for i in 4:
		var x := -4.1 + float(i) * 0.75
		out.append(
			_zyl(
				Vector3(x, 1.06, FRONT_Z + 0.16),
				Vector3(0.13, 0.44, 0.13),
				flaschen_farben[i],
				_rp("schaufenster")
			)
		)
		out.append(_kugel(Vector3(x, 1.36, FRONT_Z + 0.16), 0.09, "#F0EFE9", _rp("schaufenster")))
	out.append_array(_schaufenster(3.0, "#4FBF8B", ["chocolate", "candy-bar"] as Array[String]))
	out.append(_glb("deko/bench.gltf", Vector3(5.4, 0.0, 6.4), 4.5, _rd(180.0)))
	out.append(_glb("vorstadt/planter.glb", Vector3(-5.6, 0.0, 6.2), 4.0))
	return out


## Dr. GOOUHBUS (Arztpraxis, hellblau): Pillen-Logo als 3D-Kapsel, Praxis-
## Tafel, Wartebank + Sanitäts-Koffer.
static func _gouhbus() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#8FD0E8"))
	# Pillen-Logo: liegende Kapsel, zweifarbig (2 überlappende Kapseln).
	out.append(
		_el(
			"kapsel",
			Vector3(-0.29, 4.55, FRONT_Z + 0.3),
			Vector3(0.34, 1.05, 0.34),
			"#4E79D6",
			{"rot_z": 90.0, "rolle": "logo"}
		)
	)
	out.append(
		_el(
			"kapsel",
			Vector3(0.29, 4.55, FRONT_Z + 0.3),
			Vector3(0.34, 1.05, 0.34),
			"#F0EFE9",
			{"rot_z": 90.0, "rolle": "logo"}
		)
	)
	# Praxis-Tafel neben der Tür (weiß mit blauem Rand).
	out.append(_box(Vector3(-2.6, 1.7, FRONT_Z), Vector3(1.2, 1.5, 0.12), "#FFFFFF"))
	out.append(
		_box(
			Vector3(-2.6, 1.7, FRONT_Z + 0.07),
			Vector3(1.0, 1.3, 0.1),
			"#8FD0E8",
			_rp("schaufenster")
		)
	)
	# Rotes Kreuz auf dem Sanitäts-Koffer vor der Tür.
	out.append(_box(Vector3(3.4, 0.36, 6.6), Vector3(0.9, 0.62, 0.5), "#F0EFE9", _rd(18.0)))
	out.append(_box(Vector3(3.4, 0.66, 6.62), Vector3(0.4, 0.12, 0.34), "#E8524A", _rd(18.0)))
	out.append(_box(Vector3(3.4, 0.66, 6.62), Vector3(0.12, 0.4, 0.34), "#E8524A", _rd(18.0)))
	out.append(_glb("deko/bench.gltf", Vector3(-4.8, 0.0, 6.6), 4.5, _rd(180.0)))
	out.append(_glb("natur/plant_bushLarge.glb", Vector3(5.6, 0.0, 6.0), 4.5))
	return out


## Tierarztpraxis Dr. Dr. Möhrchen (mint): Knochen-Logo, Pfoten-Tafel,
## Napf + Wartebank mit Grün.
static func _tierarzt() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#8ED0A0"))
	# Knochen-Logo: Querbalken + 4 Kugelenden.
	out.append(
		_box(Vector3(0.0, 4.5, FRONT_Z + 0.28), Vector3(1.3, 0.3, 0.3), "#FFF9F0", _rp("logo"))
	)
	for ecke: Vector2 in [
		Vector2(-0.65, 0.17), Vector2(0.65, 0.17), Vector2(-0.65, -0.17), Vector2(0.65, -0.17)
	]:
		out.append(
			_kugel(Vector3(ecke.x, 4.5 + ecke.y, FRONT_Z + 0.28), 0.21, "#FFF9F0", _rp("logo"))
		)
	# Pfoten-Tafel: mint Tafel + 4 Zehen-Kugeln + Ballen.
	out.append(
		_box(Vector3(2.8, 1.8, FRONT_Z), Vector3(1.3, 1.3, 0.12), "#FFFFFF", _rp("schaufenster"))
	)
	out.append(_kugel(Vector3(2.8, 1.62, FRONT_Z + 0.1), 0.24, "#8ED0A0", _rp("schaufenster")))
	for i in 4:
		var x := 2.44 + float(i) * 0.24
		var y := 2.06 + (0.12 if i == 1 or i == 2 else 0.0)
		out.append(_kugel(Vector3(x, y, FRONT_Z + 0.1), 0.11, "#8ED0A0", _rp("schaufenster")))
	# Futternapf vor der Tür (roter Ring + Füllung).
	out.append(_zyl(Vector3(-3.4, 0.12, 6.8), Vector3(0.4, 0.22, 0.44), "#E8524A"))
	out.append(_zyl(Vector3(-3.4, 0.24, 6.8), Vector3(0.3, 0.06, 0.3), "#B98A62"))
	out.append(_glb("deko/bench.gltf", Vector3(4.6, 0.0, 6.4), 4.5, _rd(180.0)))
	out.append(_glb("natur/flower_purpleA.glb", Vector3(-5.2, 0.0, 6.2), 2.6))
	return out


## Flughafen (weiß/hellblau): Tower mit Radar, Windsack, Abflugtafel.
static func _flughafen() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#9BD7E8", 3.4, 3.2))
	# Mini-Tower neben dem Eingang: Schaft + Kanzel + Radarbalken.
	out.append(_zyl(Vector3(6.4, 2.6, 5.2), Vector3(0.5, 5.2, 0.62), "#F0EFE9", _rp("logo")))
	out.append(_zyl(Vector3(6.4, 5.5, 5.2), Vector3(1.1, 0.9, 0.9), "#9BD7E8", _rp("logo")))
	out.append(_box(Vector3(6.4, 6.2, 5.2), Vector3(1.5, 0.1, 0.22), "#5B4636", _rp("logo")))
	# Windsack: Mast + orange/weiße Ringe.
	out.append(_zyl(Vector3(-6.2, 1.7, 6.0), Vector3(0.07, 3.4, 0.07), "#C8D4DC"))
	out.append(_zyl(Vector3(-5.7, 3.3, 6.0), Vector3(0.16, 0.5, 0.22), "#F2A03D", {"rot_z": -70.0}))
	out.append(
		_zyl(Vector3(-5.25, 3.42, 6.0), Vector3(0.1, 0.4, 0.15), "#FFF4E8", {"rot_z": -70.0})
	)
	# Abflugtafel überm Portal (dunkel mit „Zeilen").
	out.append(
		_box(
			Vector3(0.0, 4.6, FRONT_Z + 0.16),
			Vector3(3.4, 1.1, 0.14),
			"#2E3440",
			_rp("schaufenster")
		)
	)
	for i in 3:
		out.append(
			_box(
				Vector3(-0.5, 4.9 - float(i) * 0.3, FRONT_Z + 0.26),
				Vector3(1.9, 0.1, 0.04),
				"#F2C14E",
				{"glow": 0.5, "rolle": "schaufenster"}
			)
		)
	return out


## Baumarkt Bodo Balken (orange): Hammer-Logo, Bretterstapel, Farbeimer,
## Leiter an der Wand.
static func _baumarkt() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#F2A03D", 3.2, 3.1))
	# Hammer-Logo: Stiel (Zylinder) + Kopf (Box).
	out.append(
		_zyl(
			Vector3(0.0, 4.35, FRONT_Z + 0.3),
			Vector3(0.09, 1.2, 0.09),
			"#B98A62",
			{"rot_z": 34.0, "rolle": "logo"}
		)
	)
	out.append(
		_box(
			Vector3(-0.34, 4.86, FRONT_Z + 0.3),
			Vector3(0.94, 0.42, 0.42),
			"#5B6470",
			{"rot": 0.0, "rot_z": 34.0, "rolle": "logo"}
		)
	)
	# Bretterstapel: 3 Lagen Holz quer vor der Front.
	for i in 3:
		out.append(
			_box(
				Vector3(-4.6, 0.16 + float(i) * 0.24, 6.6),
				Vector3(0.9 - float(i) * 0.12, 0.2, 3.0),
				"#C89A6A",
				_rd(8.0 + float(i) * 7.0)
			)
		)
	# Farbeimer-Reihe (bunt) am Schaufenster-Sims.
	out.append(
		_box(
			Vector3(3.2, 0.72, FRONT_Z + 0.12),
			Vector3(3.0, 0.24, 0.5),
			"#F2A03D",
			_rp("schaufenster")
		)
	)
	var eimer: Array[String] = ["#E8524A", "#4E79D6", "#8FD06C", "#F2C14E"]
	for i in eimer.size():
		out.append(
			_zyl(
				Vector3(2.2 + float(i) * 0.7, 1.02, FRONT_Z + 0.16),
				Vector3(0.2, 0.36, 0.17),
				eimer[i],
				_rp("schaufenster")
			)
		)
	# Leiter an der Fassade: 2 Holme + 4 Sprossen.
	for seite: float in [-0.4, 0.4]:
		out.append(_box(Vector3(-2.8 + seite, 1.5, FRONT_Z), Vector3(0.09, 3.0, 0.09), "#B98A62"))
	for i in 4:
		out.append(
			_box(Vector3(-2.8, 0.6 + float(i) * 0.7, FRONT_Z), Vector3(0.8, 0.08, 0.08), "#B98A62")
		)
	return out


## Post (gelb): Brief-Logo (Umschlag), Briefkasten, Paket-Stapel,
## Lieferwagen am Bordstein.
static func _post() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#FFD166"))
	# Brief-Logo: weißer Umschlag + gelbe Klappen-Linien.
	out.append(
		_box(Vector3(0.0, 4.55, FRONT_Z + 0.24), Vector3(1.6, 1.0, 0.12), "#FFFFFF", _rp("logo"))
	)
	out.append(
		_box(
			Vector3(-0.4, 4.72, FRONT_Z + 0.32),
			Vector3(0.95, 0.1, 0.06),
			"#FFD166",
			{"rot": 0.0, "rot_z": -24.0, "rolle": "logo"}
		)
	)
	out.append(
		_box(
			Vector3(0.4, 4.72, FRONT_Z + 0.32),
			Vector3(0.95, 0.1, 0.06),
			"#FFD166",
			{"rot": 0.0, "rot_z": 24.0, "rolle": "logo"}
		)
	)
	# Briefkasten: gelber Kasten auf Fuß mit Schlitz.
	out.append(_zyl(Vector3(-3.6, 0.5, 6.8), Vector3(0.09, 1.0, 0.09), "#5B6470"))
	out.append(_box(Vector3(-3.6, 1.24, 6.8), Vector3(0.74, 0.6, 0.5), "#FFD166", _rd(12.0)))
	out.append(_box(Vector3(-3.6, 1.4, 7.06), Vector3(0.4, 0.05, 0.06), "#5B4636", _rd(12.0)))
	# Paket-Stapel: 3 Kartons in Brauntönen.
	out.append(_box(Vector3(3.7, 0.35, 6.5), Vector3(1.1, 0.7, 0.9), "#C89A6A", _rd(-10.0)))
	out.append(_box(Vector3(3.5, 0.95, 6.6), Vector3(0.8, 0.5, 0.7), "#B98A62", _rd(14.0)))
	out.append(_box(Vector3(4.3, 0.3, 7.3), Vector3(0.6, 0.6, 0.6), "#D9B98C", _rd(28.0)))
	# Schaufenster mit Paket-Regal.
	out.append_array(_schaufenster(-3.2, "#FFD166", [] as Array[String]))
	out.append(
		_box(
			Vector3(-3.6, 1.1, FRONT_Z + 0.16),
			Vector3(0.6, 0.5, 0.4),
			"#C89A6A",
			_rp("schaufenster")
		)
	)
	out.append(
		_box(
			Vector3(-2.8, 1.0, FRONT_Z + 0.16),
			Vector3(0.5, 0.4, 0.4),
			"#D9B98C",
			_rp("schaufenster")
		)
	)
	out.append(
		_glb("autos/delivery.glb", Vector3(6.4, 0.35, 7.6), 1.8, {"rot": 80.0, "tint": "#FFD166"})
	)
	return out


## POW! (Comicladen, gelb): Stern-Burst-Logo, Comic-Schaufenster mit
## Sprechblasen-Tafeln, bunte Kisten.
static func _pow() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#F2C14E"))
	# Stern-Burst: 6 gedrehte Strahlen-Boxen + Kern-Kugel.
	for i in 6:
		out.append(
			_box(
				Vector3(0.0, 4.6, FRONT_Z + 0.26),
				Vector3(1.9, 0.28, 0.12),
				"#E8524A" if i % 2 == 0 else "#F2C14E",
				{"rot_z": float(i) * 30.0, "rolle": "logo"}
			)
		)
	out.append(_kugel(Vector3(0.0, 4.6, FRONT_Z + 0.36), 0.34, "#FFF4E8", _rp("logo")))
	# Comic-Schaufenster: Tafeln wie Comic-Panels.
	out.append(
		_box(
			Vector3(-3.0, 1.75, FRONT_Z),
			Vector3(2.8, 1.9, 0.14),
			"#EAF4F8",
			{"rolle": "schaufenster", "glow": 0.28}
		)
	)
	var panel_farben: Array[String] = ["#F781B0", "#4E79D6", "#8FD06C"]
	for i in 3:
		out.append(
			_box(
				Vector3(-3.75 + float(i) * 0.78, 1.75, FRONT_Z + 0.1),
				Vector3(0.62, 1.3, 0.06),
				panel_farben[i],
				_rp("schaufenster")
			)
		)
	out.append(
		_glb("innen/crate.gltf", Vector3(3.8, 0.0, 6.6), 4.2, {"rot": 20.0, "tint": "#F781B0"})
	)
	out.append(_glb("deko/bench.gltf", Vector3(-4.8, 0.0, 6.4), 4.5, _rd(180.0)))
	out.append(_glb("natur/flower_yellowA.glb", Vector3(5.4, 0.0, 6.2), 2.6))
	return out


## Autohaus Blechbert (hellblau): Wimpel-Masten, Reifenstapel, Schauwagen
## auf Podest (Wagen kommen weiter aus CityBau-Props? Nein: hier komplett).
static func _autohaus() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#8FD0E8", 3.4, 3.1))
	# Schlüssel-Logo: Ring + Bart.
	out.append(
		_el(
			"torus",
			Vector3(-0.4, 4.6, FRONT_Z + 0.26),
			Vector3(0.34, 0.12, 0.34),
			"#F2C14E",
			_rp("logo")
		)
	)
	out.append(
		_box(Vector3(0.35, 4.6, FRONT_Z + 0.26), Vector3(0.9, 0.14, 0.12), "#F2C14E", _rp("logo"))
	)
	out.append(
		_box(Vector3(0.62, 4.42, FRONT_Z + 0.26), Vector3(0.12, 0.24, 0.12), "#F2C14E", _rp("logo"))
	)
	# Schauwagen auf flachem Podest + zweiter am Vorplatz.
	out.append(
		_zyl(Vector3(-3.6, 0.12, 7.0), Vector3(2.2, 0.24, 2.3), "#EAF4F8", _rp("schaufenster"))
	)
	out.append(
		_glb(
			"autos/race.glb", Vector3(-3.6, 0.28, 7.0), 1.8, {"rot": -35.0, "rolle": "schaufenster"}
		)
	)
	out.append(_glb("autos/sedan-sports.glb", Vector3(3.6, 0.05, 7.0), 1.8, {"rot": 35.0}))
	# Reifenstapel: 3 Tori übereinander.
	for i in 3:
		out.append(
			_el(
				"torus",
				Vector3(5.8, 0.22 + float(i) * 0.34, 5.8),
				Vector3(0.42, 0.17, 0.42),
				"#2E3440",
				{}
			)
		)
	# Wimpel-Masten mit Fähnchen (statisch, bunt).
	for i in 3:
		var x := -6.2 + float(i) * 1.4
		out.append(_zyl(Vector3(x, 1.6, 8.6), Vector3(0.05, 3.2, 0.05), "#F0EFE9"))
		out.append(
			_box(
				Vector3(x + 0.34, 3.0, 8.6),
				Vector3(0.6, 0.34, 0.04),
				["#E8524A", "#F2C14E", "#4E79D6"][i],
				_rp("deko")
			)
		)
	return out


## Wochenmarkt: Stände + Waren (aus dem alten CityBau-Prop-Set übernommen,
## plus Gemüse-Deko auf den Tischen).
static func _wochenmarkt() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		_glb("natur/pot_large.glb", Vector3(5.0, 0.0, 5.0), 3.5),
		_glb("innen/crate_carrots.gltf", Vector3(-6.4, 0.0, 1.2), 3.4, _rd(35.0)),
		_glb("innen/crate_cheese.gltf", Vector3(7.4, 0.0, -15.0), 3.4, _rd(205.0)),
	]
	for stand: Vector3 in [
		Vector3(-5.0, 0.0, 4.0),
		Vector3(6.0, 0.0, 4.0),
		Vector3(-5.0, 0.0, -18.0),
		Vector3(6.0, 0.0, -18.0),
	]:
		out.append(_glb("innen/table_round_A.gltf", stand, 0.9))
	# Waren auf den Tischen: Kürbis, Brot, Käse, Wassermelone.
	out.append(_glb("essen/pumpkin.glb", Vector3(-5.0, 1.0, 4.0), 2.6))
	out.append(_glb("essen/bread.glb", Vector3(6.0, 1.0, 4.0), 2.6, _rd(40.0)))
	out.append(_glb("essen/cheese.glb", Vector3(-5.0, 1.0, -18.0), 2.6, _rd(80.0)))
	out.append(_glb("essen/watermelon.glb", Vector3(6.0, 1.0, -18.0), 2.6, _rd(120.0)))
	for seite: float in [-1.0, 1.0]:
		out.append(_glb("deko/bench.gltf", Vector3(1.6 * seite, 0.0, -7.0), 5.0, _rd(90.0 * seite)))
		out.append(_glb("vorstadt/planter.glb", Vector3(4.2 * seite, 0.0, 8.6), 4.0))
	return out


## GOOBYMAN (Heldenladen, pink): Blitz-Logo, Cape-Banner, Masken-Fenster.
static func _goobyman() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#D94F8C"))
	# Blitz-Logo: 2 versetzte Parallelogramm-Boxen.
	out.append(
		_box(
			Vector3(-0.14, 4.75, FRONT_Z + 0.26),
			Vector3(0.4, 0.85, 0.12),
			"#F2C14E",
			{"rot_z": 20.0, "rolle": "logo"}
		)
	)
	out.append(
		_box(
			Vector3(0.14, 4.15, FRONT_Z + 0.26),
			Vector3(0.4, 0.85, 0.12),
			"#F2C14E",
			{"rot_z": 20.0, "rolle": "logo"}
		)
	)
	# Cape-Banner links/rechts der Tür.
	for seite: float in [-1.0, 1.0]:
		out.append(
			_box(
				Vector3(2.2 * seite, 2.4, FRONT_Z),
				Vector3(0.7, 2.4, 0.08),
				"#D94F8C" if seite < 0.0 else "#4E79D6",
				_rp("deko")
			)
		)
	out.append_array(_schaufenster(-3.4, "#D94F8C", ["lollypop", "candy-bar"] as Array[String]))
	out.append(
		_glb("innen/crate.gltf", Vector3(4.2, 0.0, 6.4), 4.0, {"rot": -18.0, "tint": "#4E79D6"})
	)
	return out


## Funkelpark-Stadtfassade (pink): Mini-Riesenrad-Logo + Wimpel + Ballons.
static func _funkelpark_tor() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_portal("#F781B0", 3.4, 3.2))
	# Mini-Riesenrad-Logo: Torus + 4 Speichen + Gondel-Punkte.
	out.append(
		_el(
			"torus",
			Vector3(0.0, 4.7, FRONT_Z + 0.26),
			Vector3(0.62, 0.09, 0.62),
			"#F2C14E",
			_rp("logo")
		)
	)
	for i in 2:
		out.append(
			_box(
				Vector3(0.0, 4.7, FRONT_Z + 0.26),
				Vector3(1.16, 0.08, 0.08),
				"#F0EFE9",
				{"rot_z": float(i) * 90.0, "rolle": "logo"}
			)
		)
	var gondel_farben: Array[String] = ["#F781B0", "#9BD7E8", "#8FD06C", "#B58CE4"]
	for i in 4:
		var w := float(i) * TAU / 4.0
		out.append(
			_kugel(
				Vector3(cos(w) * 0.62, 4.7 + sin(w) * 0.62, FRONT_Z + 0.3),
				0.12,
				gondel_farben[i],
				_rp("logo")
			)
		)
	# Ballon-Bündel am Portal.
	for i in 3:
		var farbe: String = gondel_farben[i]
		out.append(
			_zyl(Vector3(4.0, 1.1 + float(i) * 0.1, 6.4), Vector3(0.015, 2.2, 0.015), "#C8D4DC")
		)
		out.append(
			_kugel(
				Vector3(3.7 + float(i) * 0.3, 2.5 + float(i) * 0.25, 6.4), 0.3, farbe, _rp("deko")
			)
		)
	out.append_array(_schaufenster(-3.2, "#F781B0", ["ice-cream", "cupcake-pink"] as Array[String]))
	return out

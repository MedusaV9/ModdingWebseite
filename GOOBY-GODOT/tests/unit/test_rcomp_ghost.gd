extends TestCase
## RW-5 — Geisterlauf-Format (Kap. 5.3, IDEAS-4-MP-Standard): 10-Hz-Recorder,
## Binärformat v1 (8 B/Sample = 80 B/s, unter dem Doc-Budget ~130 B/s),
## verlustarme Runde Encode→Decode und die Wiedergabe-Interpolation.

const Ghost := preload("res://scripts/ranch/comp/ghost/comp_ghost.gd")


## Synthetischer 30-s-Lauf: Kreisbahn mit Galopp + zwei Sprüngen.
func _beispiel_recorder() -> Dictionary:
	var rec := Ghost.neuer_recorder("tonnen", Vector3(12.0, 0.0, -5.0))
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < 30.0:
		t += dt
		var winkel := t * 0.4
		var pos := Vector3(12.0 + cos(winkel) * 9.0, 0.0, -5.0 + sin(winkel) * 9.0)
		var springt := t > 4.0 and t < 4.6
		if springt:
			pos.y = 0.8
		var gangart := "galopp" if t > 2.0 else "trab"
		Ghost.tick(rec, dt, pos, winkel + PI * 0.5, gangart, springt)
	return rec


func test_recorder_rastert_auf_10_hz() -> void:
	var rec := _beispiel_recorder()
	var samples: Array = rec["samples"]
	assert_true(absf(samples.size() - 300.0) <= 1.0, "30 s × 10 Hz ≈ 300 Samples")
	assert_almost(Ghost.dauer_s(rec), 30.0, 0.2)


func test_encode_bleibt_unter_dem_byte_budget() -> void:
	var rec := _beispiel_recorder()
	var bytes := Ghost.encode(rec)
	var samples: Array = rec["samples"]
	assert_eq(bytes.size(), Ghost.HEADER_BYTES + samples.size() * Ghost.SAMPLE_BYTES)
	var bytes_pro_s := float(bytes.size()) / Ghost.dauer_s(rec)
	assert_true(bytes_pro_s <= 130.0, "Doc-Budget ~130 B/s (ist: %.1f)" % bytes_pro_s)
	assert_eq(Ghost.BYTES_PRO_S, 80, "10 Hz × 8 B")


func test_roundtrip_verlustarm() -> void:
	var rec := _beispiel_recorder()
	var geist := Ghost.decode(Ghost.encode(rec))
	assert_true(bool(geist["ok"]))
	assert_eq(str(geist["disziplin"]), "tonnen")
	assert_eq(int(geist["hz"]), Ghost.HZ)
	var samples: Array = geist["samples"]
	# Referenz nachrechnen: Position exakt wie beim Aufzeichnen abtasten.
	for idx: int in [0, 60, 150, 299]:
		if idx >= samples.size():
			continue
		var t := float(idx + 1) / Ghost.HZ
		var winkel := 0.0
		# Der Recorder sampelt beim Überschreiten des Rasters — die Referenz-
		# position stammt vom Frame, in dem das Sample fiel (±1 Frame).
		winkel = t * 0.4
		var soll := Vector2(12.0 + cos(winkel) * 9.0, -5.0 + sin(winkel) * 9.0)
		var ist: Vector2 = (samples[idx] as Dictionary)["pos"]
		assert_true(
			ist.distance_to(soll) < 0.08,
			"Sample %d: Positionsverlust klein (%.3f m)" % [idx, ist.distance_to(soll)]
		)
	# Quantisierung: Heading ≤ 1/256 Umdrehung, Höhe ≤ 1 cm.
	var s60: Dictionary = samples[60]
	assert_true(bool(samples[42].get("springt", false)), "Sprung-Flag überlebt (t≈4,3 s)")
	assert_eq(str(s60["gangart"]), "galopp", "Gangart überlebt")


func test_b64_und_kaputte_daten() -> void:
	var rec := _beispiel_recorder()
	var b64 := Ghost.to_b64(rec)
	assert_true(b64.length() > 0)
	var geist := Ghost.from_b64(b64)
	assert_true(bool(geist["ok"]))
	assert_eq((geist["samples"] as Array).size(), (rec["samples"] as Array).size())
	assert_false(bool(Ghost.from_b64("")["ok"]))
	assert_false(bool(Ghost.decode(PackedByteArray([1, 2, 3]))["ok"]))
	var falsch_magic := Ghost.encode(rec)
	falsch_magic[0] = 0xFF
	assert_false(bool(Ghost.decode(falsch_magic)["ok"]))
	var zu_kurz := Ghost.encode(rec).slice(0, 40)
	assert_false(bool(Ghost.decode(zu_kurz)["ok"]), "abgeschnittene Samples = kaputt")


func test_zustand_bei_interpoliert() -> void:
	var rec := Ghost.neuer_recorder("zeit", Vector3.ZERO)
	# Zwei Samples von Hand: (0,0) → (1 m, 0) in einem 10-Hz-Schritt.
	Ghost.tick(rec, 0.1, Vector3(0.0, 0.0, 0.0), 0.0, "trab", false)
	Ghost.tick(rec, 0.1, Vector3(1.0, 0.0, 0.0), 0.0, "trab", false)
	var geist := Ghost.decode(Ghost.encode(rec))
	var mitte: Dictionary = Ghost.zustand_bei(geist, 0.05)
	assert_almost((mitte["pos"] as Vector3).x, 0.5, 0.01, "linear zwischen den Samples")
	var ende: Dictionary = Ghost.zustand_bei(geist, 99.0)
	assert_almost((ende["pos"] as Vector3).x, 1.0, 0.01, "hinter dem Ende bleibt er stehen")
	var leer: Dictionary = Ghost.zustand_bei({"samples": []}, 1.0)
	assert_eq(str(leer["gangart"]), "stand", "leerer Geist steht")


func test_heading_wickelt_ueber_null() -> void:
	var rec := Ghost.neuer_recorder("zeit", Vector3.ZERO)
	Ghost.tick(rec, 0.1, Vector3.ZERO, TAU - 0.1, "schritt", false)
	Ghost.tick(rec, 0.1, Vector3.ZERO, 0.1, "schritt", false)
	var geist := Ghost.decode(Ghost.encode(rec))
	var mitte: Dictionary = Ghost.zustand_bei(geist, 0.05)
	var heading := fposmod(float(mitte["heading"]), TAU)
	assert_true(
		heading < 0.15 or heading > TAU - 0.15,
		"Interpolation nimmt den kurzen Weg über 0 (ist: %.3f)" % heading
	)

class_name RanchCompGhost
extends RefCounted
## Geisterlauf-Format (RW-5, IDEAS-3 Kap. 5.3 + IDEAS-4: asynchroner
## Geisterlauf ist der MP-Standard) — PURE Encoder/Decoder/Interpolation.
## Aufzeichnung mit 10 Hz, 8 Bytes je Sample = 80 B/s (Doc-Budget ~130 B/s;
## ein 3-min-Lauf ≈ 14,4 KB roh / ≈ 19 KB als Base64 im Save — Doc ≈ 24 KB).
## Binärformat v1 (little-endian, Details: handoffs/RW5-ghost-format.md):
##   Header 16 B: magic "G5" (0x47 0x35), u8 version, u8 hz, u8 disziplin,
##     u8 flags, f32 origin_x, f32 origin_z, u16 count
##   Sample 8 B: i16 dx_mm, i16 dz_mm (Delta zur VORIGEN quantisierten
##     Position; Sample 0 relativ zum Origin), u8 heading (0..255 = 0..2π),
##     u8 gangart|Bit3 springt, u8 y_cm (Sprunghöhe), u8 reserve
## Der Recorder akkumuliert QUANTISIERTE Positionen — kein Drift.

const VERSION := 1
const HZ := 10
const MAGIC_A := 0x47
const MAGIC_B := 0x35
const HEADER_BYTES := 16
const SAMPLE_BYTES := 8
const BYTES_PRO_S := HZ * SAMPLE_BYTES
## Disziplin-Ids im Header (Index; "zeit" = Arcade-Zeitrennen).
const DISZIPLIN_IDS: Array[String] = [
	"springen", "dressur", "gelaende", "rennen", "trail", "schau", "tonnen", "zeit"
]
const GANGARTEN: Array[String] = ["stand", "schritt", "trab", "toelt", "galopp"]
const SPRUNG_BIT := 8
const MAX_SAMPLES := 65535


## Neuer Recorder-Zustand; origin = Startpunkt des Laufs (Weltkoordinaten).
static func neuer_recorder(disziplin: String, origin: Vector3) -> Dictionary:
	return {
		"disziplin": disziplin,
		"origin": Vector2(origin.x, origin.z),
		"akku_s": 0.0,
		"letzte_mm": Vector2i.ZERO,
		"samples": [],
	}


## Einen Frame einspeisen; sampelt selbstständig im 10-Hz-Raster.
static func tick(
	rec: Dictionary, dt: float, pos: Vector3, heading: float, gangart: String, springt := false
) -> void:
	rec["akku_s"] = _num(rec.get("akku_s"), 0.0) + maxf(0.0, dt)
	var schritt := 1.0 / HZ
	while _num(rec.get("akku_s"), 0.0) >= schritt:
		rec["akku_s"] = _num(rec.get("akku_s"), 0.0) - schritt
		_sample(rec, pos, heading, gangart, springt)


## Aufgezeichnete Dauer in Sekunden.
static func dauer_s(rec: Dictionary) -> float:
	return float((rec.get("samples", []) as Array).size()) / HZ


## Recorder → Binärformat v1.
static func encode(rec: Dictionary) -> PackedByteArray:
	var samples: Array = rec.get("samples", [])
	var anzahl := mini(samples.size(), MAX_SAMPLES)
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_u8(MAGIC_A)
	buf.put_u8(MAGIC_B)
	buf.put_u8(VERSION)
	buf.put_u8(HZ)
	buf.put_u8(maxi(0, DISZIPLIN_IDS.find(str(rec.get("disziplin", "")))))
	buf.put_u8(0)
	var origin: Vector2 = rec.get("origin", Vector2.ZERO)
	buf.put_float(origin.x)
	buf.put_float(origin.y)
	buf.put_u16(anzahl)
	for i in anzahl:
		var s: Dictionary = samples[i]
		buf.put_16(int(s["dx_mm"]))
		buf.put_16(int(s["dz_mm"]))
		buf.put_u8(int(s["heading8"]))
		buf.put_u8(int(s["gang_flags"]))
		buf.put_u8(int(s["y_cm"]))
		buf.put_u8(0)
	return buf.data_array


static func to_b64(rec: Dictionary) -> String:
	return Marshalls.raw_to_base64(encode(rec))


## Binärformat v1 → Geist {ok, disziplin, hz, dauer_s, samples: [{pos:
## Vector2, y, heading, gangart, springt}]}. Kaputte Daten → {"ok": false}.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_BYTES:
		return {"ok": false}
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = bytes
	if buf.get_u8() != MAGIC_A or buf.get_u8() != MAGIC_B or buf.get_u8() != VERSION:
		return {"ok": false}
	var hz := maxi(1, buf.get_u8())
	var disziplin_id := buf.get_u8()
	buf.get_u8()
	var origin := Vector2(buf.get_float(), buf.get_float())
	var anzahl := buf.get_u16()
	if bytes.size() < HEADER_BYTES + anzahl * SAMPLE_BYTES:
		return {"ok": false}
	var samples: Array = []
	var pos_mm := Vector2i.ZERO
	for _i in anzahl:
		pos_mm += Vector2i(buf.get_16(), buf.get_16())
		var heading8 := buf.get_u8()
		var gang_flags := buf.get_u8()
		var y_cm := buf.get_u8()
		buf.get_u8()
		(
			samples
			. append(
				{
					"pos": origin + Vector2(pos_mm.x / 1000.0, pos_mm.y / 1000.0),
					"y": y_cm / 100.0,
					"heading": float(heading8) / 256.0 * TAU,
					"gangart": GANGARTEN[mini(gang_flags & 7, GANGARTEN.size() - 1)],
					"springt": (gang_flags & SPRUNG_BIT) != 0,
				}
			)
		)
	var disziplin := "zeit"
	if disziplin_id >= 0 and disziplin_id < DISZIPLIN_IDS.size():
		disziplin = DISZIPLIN_IDS[disziplin_id]
	return {
		"ok": true,
		"disziplin": disziplin,
		"hz": hz,
		"dauer_s": float(samples.size()) / hz,
		"samples": samples,
	}


static func from_b64(b64: String) -> Dictionary:
	if b64.is_empty():
		return {"ok": false}
	return decode(Marshalls.base64_to_raw(b64))


## Interpolierte Wiedergabe: Zustand des Geists zur Zeit t (linear
## zwischen den Samples, Heading über den kurzen Weg gewickelt).
static func zustand_bei(geist: Dictionary, t: float) -> Dictionary:
	var samples: Array = geist.get("samples", [])
	if samples.is_empty():
		return {"pos": Vector3.ZERO, "heading": 0.0, "gangart": "stand", "springt": false}
	var hz := maxi(1, int(_num(geist.get("hz"), HZ)))
	var f := clampf(t, 0.0, float(samples.size() - 1) / hz) * hz
	var i := mini(int(f), samples.size() - 1)
	var j := mini(i + 1, samples.size() - 1)
	var frac := f - i
	var a: Dictionary = samples[i]
	var b: Dictionary = samples[j]
	var pos_a: Vector2 = a["pos"]
	var pos_b: Vector2 = b["pos"]
	var pos := pos_a.lerp(pos_b, frac)
	var y := lerpf(_num(a.get("y"), 0.0), _num(b.get("y"), 0.0), frac)
	var ha := _num(a.get("heading"), 0.0)
	var hb := _num(b.get("heading"), 0.0)
	var diff := fposmod(hb - ha + PI, TAU) - PI
	return {
		"pos": Vector3(pos.x, y, pos.y),
		"heading": ha + diff * frac,
		"gangart": str(a.get("gangart", "stand")),
		"springt": bool(a.get("springt", false)),
	}


## ---------------------------------------------------------------- intern


static func _sample(
	rec: Dictionary, pos: Vector3, heading: float, gangart: String, springt: bool
) -> void:
	var samples: Array = rec.get("samples", [])
	if samples.size() >= MAX_SAMPLES:
		return
	var origin: Vector2 = rec.get("origin", Vector2.ZERO)
	var ziel_mm := Vector2i(
		int(round((pos.x - origin.x) * 1000.0)), int(round((pos.z - origin.y) * 1000.0))
	)
	var letzte: Vector2i = rec.get("letzte_mm", Vector2i.ZERO)
	var delta := ziel_mm - letzte
	delta.x = clampi(delta.x, -32767, 32767)
	delta.y = clampi(delta.y, -32767, 32767)
	rec["letzte_mm"] = letzte + delta
	var gang := maxi(0, GANGARTEN.find(gangart))
	(
		samples
		. append(
			{
				"dx_mm": delta.x,
				"dz_mm": delta.y,
				"heading8": int(round(fposmod(heading, TAU) / TAU * 256.0)) & 255,
				"gang_flags": gang | (SPRUNG_BIT if springt else 0),
				"y_cm": clampi(int(round(maxf(0.0, pos.y) * 100.0)), 0, 255),
			}
		)
	)
	rec["samples"] = samples


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback

extends RefCounted
## Binaer-Plist-Parser (bplist00) in reinem GDScript (FIX-6; Doc H §5.3).
##
## WARUM: Die Alt-App (Capacitor, Bundle-Id com.permissionmaxed.gooby)
## spiegelt jeden Spielstand nach @capacitor/preferences == NSUserDefaults —
## physisch `Library/Preferences/com.permissionmaxed.gooby.plist` im eigenen
## App-Container. iOS schreibt NSUserDefaults als BINAER-Plist (bplist00).
## Dieser Parser liest genau dieses Format OHNE natives Plugin — Godot kann
## die Datei im eigenen Sandbox-Container per FileAccess lesen.
##
## Unterstuetzt die fuer NSUserDefaults relevanten Objekt-Typen:
## null/bool, int (1/2/4/8/16 Byte BE), real (f32/f64), date, data,
## ASCII-String, UTF-16BE-String, UID, Array, Set, Dict. Zyklen in den
## Objekt-Referenzen werden erkannt (kein Endlos-Rekurs bei kaputten Dateien).
##
## API: parse(bytes) / parse_file(path) → {"ok", "value", "error"}.

const HEADER := "bplist00"
const TRAILER_SIZE := 32
## Sekunden zwischen Unix-Epoche und Apple-Epoche (2001-01-01T00:00:00Z).
const APPLE_EPOCH_OFFSET := 978307200.0
## Harte Rekursionsbremse (NSUserDefaults-Plists sind flach).
const MAX_DEPTH := 64

var _bytes: PackedByteArray = PackedByteArray()
var _offsets: PackedInt64Array = PackedInt64Array()
var _ref_size := 0
var _error := ""


## Datei einlesen und parsen. {"ok": bool, "value": Variant, "error": String}.
static func parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "value": null, "error": "file not found: %s" % path}
	return parse(FileAccess.get_file_as_bytes(path))


## bplist00-Bytes parsen. {"ok": bool, "value": Variant, "error": String}.
static func parse(bytes: PackedByteArray) -> Dictionary:
	var parser := new()
	return parser._parse(bytes)


func _parse(bytes: PackedByteArray) -> Dictionary:
	_bytes = bytes
	_error = ""
	var header_ok := (
		bytes.size() >= HEADER.length() + TRAILER_SIZE + 1
		and bytes.slice(0, HEADER.length()).get_string_from_ascii() == HEADER
	)
	if not header_ok:
		return _fail("not a bplist00 (%d bytes)" % bytes.size())
	var top := _load_offset_table()
	var value: Variant = null
	if _error.is_empty():
		value = _decode(top, 0)
	if not _error.is_empty():
		return {"ok": false, "value": null, "error": _error}
	return {"ok": true, "value": value, "error": ""}


## Trailer pruefen + Offset-Tabelle laden; liefert den Top-Objekt-Index
## (Fehler laufen ueber _set_error/_error).
func _load_offset_table() -> int:
	var t := _bytes.size() - TRAILER_SIZE
	var offset_int_size := int(_bytes[t + 6])
	_ref_size = int(_bytes[t + 7])
	var num_objects := _read_be_uint(t + 8, 8)
	var top_object := _read_be_uint(t + 16, 8)
	var table_offset := _read_be_uint(t + 24, 8)
	if offset_int_size < 1 or offset_int_size > 8 or _ref_size < 1 or _ref_size > 8:
		_set_error("absurd trailer int sizes")
	elif num_objects <= 0 or num_objects > 4_000_000:
		_set_error("absurd object count %d" % num_objects)
	elif table_offset < 0 or table_offset + num_objects * offset_int_size > t:
		_set_error("offset table out of range")
	elif top_object < 0 or top_object >= num_objects:
		_set_error("top object out of range")
	if not _error.is_empty():
		return 0
	_offsets.resize(num_objects)
	for i in num_objects:
		_offsets[i] = _read_be_uint(table_offset + i * offset_int_size, offset_int_size)
	return int(top_object)


# ── Objekt-Dekodierung ────────────────────────────────────────────────────────


func _decode(index: int, depth: int) -> Variant:
	if depth > MAX_DEPTH or index < 0 or index >= _offsets.size():
		return _set_error("bad object ref %d (depth %d)" % [index, depth])
	var off := int(_offsets[index])
	if off < 0 or off >= _bytes.size():
		return _set_error("object offset %d out of range" % off)
	var marker := int(_bytes[off])
	var value: Variant = null
	match marker >> 4:
		0x0:
			value = _decode_singleton(marker)
		0x1:
			value = _read_be_int(off + 1, 1 << (marker & 0xF))
		0x2:
			value = _decode_real(off, marker & 0xF)
		0x3:
			# Datum: f64 Sekunden seit Apple-Epoche → Unix-ms (int).
			value = int((_decode_real(off, 3) + APPLE_EPOCH_OFFSET) * 1000.0)
		0x8:
			value = _read_be_int(off + 1, (marker & 0xF) + 1)
		_:
			value = _decode_sized(marker >> 4, off, marker & 0xF, depth)
	return value


func _decode_singleton(marker: int) -> Variant:
	match marker:
		0x08:
			return false
		0x09:
			return true
	return null


func _decode_real(off: int, info: int) -> float:
	var count := 1 << info
	if off + 1 + count > _bytes.size():
		_set_error("real out of range")
		return 0.0
	var slice := _bytes.slice(off + 1, off + 1 + count)
	slice.reverse()  # BE → LE
	if count == 4:
		return slice.decode_float(0)
	if count == 8:
		return slice.decode_double(0)
	_set_error("unsupported real width %d" % count)
	return 0.0


## Typen mit Laengen-Nibble (0xF → Laenge folgt als Int-Objekt).
func _decode_sized(kind: int, off: int, info: int, depth: int) -> Variant:
	var head := _sized_head(off, info)
	var count := int(head["count"])
	var data := int(head["data"])
	if count < 0 or data < 0:
		return _set_error("bad length header at %d" % off)
	var value: Variant = null
	match kind:
		0x4:
			value = _slice_checked(data, count)
		0x5:
			var ascii: Variant = _slice_checked(data, count)
			if ascii != null:
				value = (ascii as PackedByteArray).get_string_from_ascii()
		0x6:
			value = _decode_utf16(data, count)
		0xA, 0xC:
			value = _decode_array(data, count, depth)
		0xD:
			value = _decode_dict(data, count, depth)
		_:
			value = _set_error("unsupported marker 0x%X at %d" % [kind, off])
	return value


func _sized_head(off: int, info: int) -> Dictionary:
	if info != 0xF:
		return {"count": info, "data": off + 1}
	if off + 1 >= _bytes.size():
		return {"count": -1, "data": -1}
	var int_marker := int(_bytes[off + 1])
	if int_marker >> 4 != 0x1:
		return {"count": -1, "data": -1}
	var nbytes := 1 << (int_marker & 0xF)
	var count := _read_be_uint(off + 2, nbytes)
	return {"count": count, "data": off + 2 + nbytes}


func _decode_utf16(data: int, count: int) -> Variant:
	var raw: Variant = _slice_checked(data, count * 2)
	if raw == null:
		return null
	# bplist speichert UTF-16 BIG-endian; get_string_from_utf16 will LE →
	# Byte-Paare drehen.
	var bytes := raw as PackedByteArray
	for i in count:
		var hi := bytes[i * 2]
		bytes[i * 2] = bytes[i * 2 + 1]
		bytes[i * 2 + 1] = hi
	return bytes.get_string_from_utf16()


func _decode_array(data: int, count: int, depth: int) -> Variant:
	if data + count * _ref_size > _bytes.size():
		return _set_error("array refs out of range")
	var out: Array = []
	for i in count:
		out.append(_decode(_read_be_uint(data + i * _ref_size, _ref_size), depth + 1))
		if not _error.is_empty():
			return null
	return out


func _decode_dict(data: int, count: int, depth: int) -> Variant:
	if data + count * 2 * _ref_size > _bytes.size():
		return _set_error("dict refs out of range")
	var out := {}
	for i in count:
		var key: Variant = _decode(_read_be_uint(data + i * _ref_size, _ref_size), depth + 1)
		var value: Variant = _decode(
			_read_be_uint(data + (count + i) * _ref_size, _ref_size), depth + 1
		)
		if not _error.is_empty():
			return null
		out[key if key is String else str(key)] = value
	return out


# ── Byte-Helfer ───────────────────────────────────────────────────────────────


func _slice_checked(from: int, count: int) -> Variant:
	if from < 0 or count < 0 or from + count > _bytes.size():
		return _set_error("data out of range (%d+%d)" % [from, count])
	return _bytes.slice(from, from + count)


## Vorzeichenlose Big-Endian-Zahl (Offsets/Refs/Laengen).
func _read_be_uint(from: int, count: int) -> int:
	if from < 0 or from + count > _bytes.size():
		_set_error("uint out of range (%d+%d)" % [from, count])
		return -1
	var value := 0
	for i in count:
		value = (value << 8) | int(_bytes[from + i])
	return value


## Int-OBJEKTE: 1/2/4 Byte sind laut Format vorzeichenlos, 8/16 Byte
## vorzeichenbehaftet (16 Byte: nur die unteren 8 tragen NSUserDefaults-Werte).
func _read_be_int(from: int, count: int) -> int:
	if count == 16:
		return _read_be_int(from + 8, 8)
	var value := _read_be_uint(from, count)
	if count == 8:
		return value  # 64-Bit-Shift laeuft in Godot natuerlich ins Vorzeichen.
	return value


func _set_error(message: String) -> Variant:
	if _error.is_empty():
		_error = message
	return null


func _fail(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}

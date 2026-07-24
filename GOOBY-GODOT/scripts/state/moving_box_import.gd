extends RefCounted
## "Umzugskoffer"-Import/Export (W1d/STATE; Doc H §5.3 Fallback-Weg).
##
## Akzeptiert ZWEI Formate (import_text):
## 1. Roher JSON-String der Alt-App: Einstellungen → 5x aufs Sprachsegment
##    "Auto" tippen (Dev-Freischaltung) → Entwickler-Panel → "Save
##    exportieren" kopiert den KOMPLETTEN v4-Save-JSON in die Zwischenablage
##    (web devPanel.js — verifiziert: raw JSON, KEIN base64). Jede Version
##    v0–v4 laeuft durch die volle Migrationskette (migration_v4.gd).
## 2. Kompaktformat `GOOBY5.<base64url(gzip(json))>.<crc32hex>` fuer
##    Godot↔Godot-Transfers (Geraetewechsel): export_code() erzeugt es aus
##    einem v5-State, import_text() validiert CRC32 (ueber die gzip-Bytes)
##    und Format strikt. v5-Payloads laufen durch SaveSchema.normalize.
##
## Der UI-Screen dazu ist W1c/W2 — dieses Modul liefert nur die reine API
## (String rein, {ok, state, error, report} raus) + Tests.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const MigrationV4 := preload("res://scripts/state/migration_v4.gd")

const CODE_PREFIX := "GOOBY5"
## Safety cap for decompression (a save is a few 100 KB at most).
const MAX_DECOMPRESSED_BYTES := 16 * 1024 * 1024

static var _crc_table: PackedInt64Array = PackedInt64Array()


## Import from pasted text (raw JSON or GOOBY5 code).
## Returns {"ok": bool, "state": Dictionary, "error": String, "report": Dictionary}.
static func import_text(text: String, now_ms: int) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return _err("empty input")
	var json_text := trimmed
	if trimmed.begins_with(CODE_PREFIX + "."):
		var decoded := decode_code(trimmed)
		if not decoded["ok"]:
			return _err(decoded["error"])
		json_text = decoded["json"]
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return _err("invalid JSON: %s" % json.get_error_message())
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return _err("save is not an object")
	var v: Variant = parsed.get("v")
	var v_num := typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
	if v_num and int(v) == SaveSchema.SCHEMA_VERSION:
		var normalized := SaveSchema.normalize(parsed, now_ms)
		if not normalized["ok"]:
			return _err(normalized["error"])
		var s: Dictionary = normalized["state"]
		return {
			"ok": true,
			"state": s,
			"error": "",
			"report":
			{
				"importedFrom": "godot-v5",
				"level": s["progression"]["level"],
				"coins": s["economy"]["coins"],
				"stickers": s["stickers"]["unlocked"].size(),
				"outfits": s["cosmetics"]["outfits"]["owned"].size(),
			},
		}
	if v_num and int(v) > SaveSchema.SCHEMA_VERSION:
		return _err("forward version %d — bitte App updaten" % int(v))
	return MigrationV4.migrate_any(parsed, now_ms)


## Export a v5 state as `GOOBY5.<base64url(gzip(json))>.<crc32hex>`.
static func export_code(state: Dictionary) -> String:
	var bytes := JSON.stringify(state).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return "%s.%s.%08x" % [CODE_PREFIX, _base64url_encode(bytes), crc32(bytes)]


## Strict GOOBY5-code decode. Returns {"ok", "json": String, "error"}.
static func decode_code(code: String) -> Dictionary:
	var parts := code.strip_edges().split(".")
	if parts.size() != 3 or parts[0] != CODE_PREFIX:
		return {"ok": false, "json": "", "error": "malformed GOOBY5 code"}
	var bytes := _base64url_decode(parts[1])
	if bytes.is_empty():
		return {"ok": false, "json": "", "error": "invalid base64url payload"}
	var want := parts[2].strip_edges().to_lower()
	var got := "%08x" % crc32(bytes)
	if got != want:
		return {"ok": false, "json": "", "error": "CRC mismatch (%s != %s)" % [got, want]}
	var raw := bytes.decompress_dynamic(MAX_DECOMPRESSED_BYTES, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {"ok": false, "json": "", "error": "gzip payload did not decompress"}
	return {"ok": true, "json": raw.get_string_from_utf8(), "error": ""}


static func _base64url_encode(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


static func _base64url_decode(text: String) -> PackedByteArray:
	var b64 := text.replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	return Marshalls.base64_to_raw(b64)


## CRC-32 (IEEE 802.3, wie zlib.crc32) — lazily built lookup table.
static func crc32(bytes: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for _bit in 8:
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) != 0 else (c >> 1)
			_crc_table[i] = c
	var crc := 0xFFFFFFFF
	for b in bytes:
		crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


static func _err(message: String) -> Dictionary:
	return {"ok": false, "state": {}, "error": message, "report": {}}

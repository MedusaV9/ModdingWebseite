extends RefCounted
## Pinnable game clock — port of GOOBY/src/core/clock.js (§E4).
##
## now_ms() is the ONLY allowed time source for all W1d state/logic code.
## Tests pin the clock (pin/advance) for fully deterministic runs; production
## code leaves it unpinned and gets the system clock.
##
## local_day() mirrors the web's localDay(): a YYYY-MM-DD string in LOCAL
## time. The UTC offset is taken from the OS by default and can be overridden
## (tests pin offset 0 so the golden values generated with TZ=UTC match).

var _pinned := false
var _pinned_ms := 0
var _offset_minutes := 0
var _offset_overridden := false


## Current game time in epoch milliseconds.
func now_ms() -> int:
	if _pinned:
		return _pinned_ms
	return int(Time.get_unix_time_from_system() * 1000.0)


## Pin the clock to a fixed epoch-ms value (tests / dev harness).
func pin(ms: int) -> void:
	_pinned = true
	_pinned_ms = ms


## Advance a pinned clock by `ms` (no-op when unpinned).
func advance(ms: int) -> void:
	if _pinned:
		_pinned_ms += ms


## Return to the system clock.
func unpin() -> void:
	_pinned = false


## Override the UTC offset in minutes used by local_day() (tests use 0).
func set_utc_offset_minutes(minutes: int) -> void:
	_offset_minutes = minutes
	_offset_overridden = true


## Local calendar day string (YYYY-MM-DD) for "per local day" rules
## (daily x2, streaks). Mirrors web localDay(ms).
func local_day(ms := -1) -> String:
	var at := ms if ms >= 0 else now_ms()
	var offset := _offset_minutes
	if not _offset_overridden:
		offset = int(Time.get_time_zone_from_system().get("bias", 0))
	var local_secs := int(floor(at / 1000.0)) + offset * 60
	var d := Time.get_datetime_dict_from_unix_time(local_secs)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

class_name DeviceProfile
extends RefCounted
## RW-7 (Doc §4.2) — Geräteerkennung für das Auto-Qualitätsprofil.
##
## Pure statische Klassifikation: `classify(facts)` bekommt messbare Fakten
## (Speicher, Bildschirm, Bildwiederholrate, Renderer-Name) und liefert die
## Geräteklasse "niedrig" | "mittel" | "hoch" plus 120-Hz-Fähigkeit. KEINE
## Modellnamen-Hardcodes (Doc: „Auto darf nicht nur Modellnamen hardcoden“) —
## die Laufzeitmessung/Notbremse übernimmt danach `PerfGovernor`.
##
## `snapshot()` sammelt die Fakten headless-sicher vom laufenden System.

## Ab dieser physischen RAM-Größe gilt ein Gerät als „hoch“ (etwa iPhone 12+
## Klasse); darunter „mittel“, unter MEMORY_MITTEL_MB „niedrig“.
const MEMORY_HOCH_MB := 5500.0
const MEMORY_MITTEL_MB := 3500.0
## Ab dieser gemessenen Bildwiederholrate gilt das Display als ProMotion.
const REFRESH_PROMOTION_HZ := 100.0
## Sehr kleine Auflösungen (kurze Kante) deuten auf alte Geräte.
const SCREEN_NIEDRIG_PX := 750.0


## Fakten vom laufenden System (headless liefert neutrale Werte).
static func snapshot() -> Dictionary:
	var memory_mb := 0.0
	var mem_info := OS.get_memory_info()
	if mem_info.has("physical"):
		memory_mb = float(mem_info["physical"]) / 1048576.0
	var screen := Vector2.ZERO
	var refresh := -1.0
	if DisplayServer.get_name() != "headless":
		screen = Vector2(DisplayServer.screen_get_size())
		refresh = DisplayServer.screen_get_refresh_rate()
	return {
		"memory_mb": memory_mb,
		"screen_px": screen,
		"refresh_hz": refresh,
		"adapter": RenderingServer.get_video_adapter_name(),
		"os_name": OS.get_name(),
	}


## Fakten → {"klasse": "niedrig"|"mittel"|"hoch", "supports_120": bool,
## "fps": 30|60|120}. Unbekannte/leere Fakten → konservativ „mittel“ (Doc:
## „konservativ Mittel/60 starten“, echte Messung korrigiert später).
static func classify(facts: Dictionary) -> Dictionary:
	var memory_mb := float(facts.get("memory_mb", 0.0))
	var refresh := float(facts.get("refresh_hz", -1.0))
	var screen: Vector2 = facts.get("screen_px", Vector2.ZERO)
	var supports_120 := refresh >= REFRESH_PROMOTION_HZ
	var klasse := "mittel"
	if memory_mb <= 0.0:
		klasse = "mittel"
	elif memory_mb >= MEMORY_HOCH_MB:
		klasse = "hoch"
	elif memory_mb >= MEMORY_MITTEL_MB:
		klasse = "mittel"
	else:
		klasse = "niedrig"
	var short_edge := minf(screen.x, screen.y)
	if short_edge > 0.0 and short_edge < SCREEN_NIEDRIG_PX and klasse != "niedrig":
		klasse = "niedrig" if klasse == "mittel" else "mittel"
	var fps := 30
	match klasse:
		"hoch":
			fps = 120 if supports_120 else 60
		"mittel":
			fps = 60
		_:
			fps = 30
	return {"klasse": klasse, "supports_120": supports_120, "fps": fps}

class_name RmpInterp
extends RefCounted
## Interpolations-Puffer für Peer-Posen (RW-6, RANCH-DLC-IDEAS-4 §2.1):
## Posen kommen mit 10 Hz vom Relay, gerendert wird VERZOEGERT_MS in der
## Vergangenheit — dazwischen wird linear interpoliert, Heading über den
## kurzen Weg. PURE (kein Node): ein Dictionary-Zustand, deterministisch
## testbar. Bei Puffer-Leerlauf (Lag-Spike) hält der Peer die letzte Pose.

const VERZOEGERT_MS := 150
const PUFFER_MAX := 24
## Nach so langer Funkstille gilt der Peer als eingefroren (HUD zeigt "…").
const STALE_MS := 1200


static func neu() -> Dictionary:
	return {"samples": [], "letzte_at": -1}


## Pose einspeisen. `at_ms` = lokale Empfangszeit (Ticks); alte/duplizierte
## Sequenzen filtert schon der Service über poseSeq.
static func push(zustand: Dictionary, at_ms: int, pos: Vector3, yaw: float, gait: int) -> void:
	var samples: Array = zustand.get("samples", [])
	samples.append({"at": at_ms, "pos": pos, "yaw": yaw, "gait": gait})
	while samples.size() > PUFFER_MAX:
		samples.pop_front()
	zustand["samples"] = samples
	zustand["letzte_at"] = at_ms


## Interpolierte Pose zur Renderzeit `now_ms` (schaut VERZOEGERT_MS zurück).
## {} = noch keine Daten.
static func sample_at(zustand: Dictionary, now_ms: int) -> Dictionary:
	var samples: Array = zustand.get("samples", [])
	if samples.is_empty():
		return {}
	var ziel := now_ms - VERZOEGERT_MS
	var erste: Dictionary = samples[0]
	if ziel <= int(erste["at"]) or samples.size() == 1:
		var pose_erste := _pose(erste)
		# Auch mit nur EINEM Sample gilt: lange Funkstille = eingefroren.
		pose_erste["stale"] = now_ms - int(samples.back()["at"]) > STALE_MS
		return pose_erste
	for i in range(samples.size() - 1):
		var a: Dictionary = samples[i]
		var b: Dictionary = samples[i + 1]
		if ziel >= int(a["at"]) and ziel <= int(b["at"]):
			var spanne := float(int(b["at"]) - int(a["at"]))
			var frac := 0.0 if spanne <= 0.0 else float(ziel - int(a["at"])) / spanne
			var yaw_a := float(a["yaw"])
			var diff := fposmod(float(b["yaw"]) - yaw_a + PI, TAU) - PI
			return {
				"pos": (a["pos"] as Vector3).lerp(b["pos"], frac),
				"yaw": yaw_a + diff * frac,
				"gait": int(b["gait"]),
				"stale": false,
			}
	# Ziel liegt hinter dem jüngsten Sample (Lag-Spike): letzte Pose halten.
	var letzte: Dictionary = samples.back()
	var pose := _pose(letzte)
	pose["stale"] = now_ms - int(letzte["at"]) > STALE_MS
	return pose


## Alles verwerfen (Rejoin/Teleport: kein Gleiten quer über die Karte).
static func reset(zustand: Dictionary) -> void:
	zustand["samples"] = []
	zustand["letzte_at"] = -1


static func _pose(sample: Dictionary) -> Dictionary:
	return {
		"pos": sample["pos"],
		"yaw": float(sample["yaw"]),
		"gait": int(sample["gait"]),
		"stale": false,
	}

extends SceneTree
## RW-1-Probe (KEIN Test): baut die Region-Szene headless auf, tickt ein
## paar Frames und meldet Knoten-/Tier-Zahlen + Wetter-Zustand.


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	await process_frame
	var szene: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	var region: Node3D = szene.instantiate()
	region.stunde_override = 14.0
	var t0 := Time.get_ticks_msec()
	root.add_child(region)
	print("aufbau_ms=", Time.get_ticks_msec() - t0)
	for _i in 30:
		await process_frame
	print("kinder=", region.get_child_count())
	print("wetter=", region.wetter.zustand)
	print("tiere=", region.wildtiere.tiere.size())
	print("reiter=", region.reiter.position)
	print("zone=", RanchKarte.zone_bei(region.reiter.position))
	region.queue_free()
	await process_frame
	quit(0)

class_name NetTestRig
extends RefCounted
## Gemeinsames Test-Rig der test_net_*-Suiten: ein NetClient mit FakeWsLink-
## Factory (jeder connect_now() erzeugt einen neuen Fake in `links`), Temp-
## Identität unter user:// und go_online() für den kompletten HELLO/WELCOME-
## Handshake mit fingiertem Server. Services (Presence/Friends/Analytics)
## verdrahten die Tests selbst (build_services=false — kein Default-Outbox-IO).

var client: NetClient
var links: Array[FakeWsLink] = []
var identity_path := ""


static func boot(tree: SceneTree) -> NetTestRig:
	var rig := NetTestRig.new()
	rig.identity_path = ("user://test_netid_%d_%d.json" % [Time.get_ticks_usec(), randi() % 100000])
	var net := NetClient.new()
	net.auto_connect = false
	net.build_services = false
	net.identity_path = rig.identity_path
	net.config_override = {"host": "fake.test", "port": 1, "tls": false}
	net.link_factory = func() -> FakeWsLink:
		var link := FakeWsLink.new()
		rig.links.append(link)
		return link
	tree.root.add_child(net)
	rig.client = net
	return rig


## Der aktuell aktive Fake-Link (der jüngste aus der Factory).
func link() -> FakeWsLink:
	return links.back() if not links.is_empty() else null


## Kompletter Handshake: connect → open → HELLO abwarten → WELCOME einspielen.
func go_online(tree: SceneTree, friend_code := "GOOBY-TEST") -> void:
	client.connect_now()
	link().open()
	for _i in 3:
		await tree.process_frame
	link().respond_to(
		"HELLO", "WELCOME", {"friendCode": friend_code, "heartbeatSec": 20, "serverTime": 0}
	)
	for _i in 3:
		await tree.process_frame


func shutdown(tree: SceneTree) -> void:
	client.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(identity_path))

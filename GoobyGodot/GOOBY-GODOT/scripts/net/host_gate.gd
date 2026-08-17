class_name NetHostGate
extends RefCounted
## ws://-Heimnetz-Gate (Doc C §7 / P3 AP-12) — PURE Host-Klassifikation.
## Unverschlüsseltes ws:// ist nur zu privaten/lokalen Zielen erlaubt:
## localhost, 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
## `*.local` (mDNS) sowie IPv6-loopback (::1), ULA (fc00::/7) und
## link-local (fe80::/10). Zusätzlich gelten die RFC-6761-reservierten
## Namensräume `*.test`/`*.invalid`/`*.localhost` als lokal — sie sind im
## öffentlichen DNS nie auflösbar (und tragen die FakeWsLink-Testsuiten).
## Alles andere braucht wss:// (TLS). Keine Seiteneffekte, kein Netz-IO.

## Lokale Namens-Suffixe (mDNS + RFC-6761-reservierte TLDs).
const LOCAL_NAME_SUFFIXES: Array[String] = [".local", ".localhost", ".test", ".invalid"]


## true == privates/lokales Ziel (Heimnetz) — ws:// ohne TLS ist ok.
## Nimmt rohe Host-Angaben inkl. Randfällen: „host:port“, „[::1]:port“,
## Zone-Index („fe80::1%eth0“), Groß-/Kleinschreibung, Leerraum.
static func is_private_host(raw_host: String) -> bool:
	var host := strip_port(raw_host).to_lower()
	if host.is_empty():
		return false
	if host.contains(":"):
		return _is_private_ipv6(host)
	if host == "localhost":
		return true
	for suffix in LOCAL_NAME_SUFFIXES:
		if host.ends_with(suffix):
			return true
	if _is_ipv4(host):
		return _is_private_ipv4(host)
	return false


## Host-Teil aus einer rohen Angabe lösen: trimmt Leerraum, packt
## „[IPv6]“ aus und schneidet einen „:port“-Anhang ab (nur wenn er nicht
## Teil einer klammerlosen IPv6-Adresse ist — die hat ≥2 Doppelpunkte).
static func strip_port(raw_host: String) -> String:
	var host := raw_host.strip_edges()
	if host.begins_with("["):
		var close := host.find("]")
		return host.substr(1, close - 1) if close > 0 else ""
	if host.count(":") == 1:
		var port := host.get_slice(":", 1)
		if port.is_valid_int():
			return host.get_slice(":", 0)
	return host


static func _is_ipv4(host: String) -> bool:
	var parts := host.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if part.is_empty() or not part.is_valid_int():
			return false
		if int(part) < 0 or int(part) > 255:
			return false
		# Führende Nullen/Plus wären keine kanonische Dotted-Quad-Schreibweise.
		if str(int(part)) != part:
			return false
	return true


static func _is_private_ipv4(host: String) -> bool:
	var octets := host.split(".")
	var first := int(octets[0])
	var second := int(octets[1])
	if first == 127 or first == 10:
		return true
	if first == 192 and second == 168:
		return true
	return first == 172 and second >= 16 and second <= 31


static func _is_private_ipv6(host: String) -> bool:
	# Zone-Index (fe80::1%eth0) für die Klassifikation abschneiden.
	var addr := host.get_slice("%", 0)
	if not addr.is_valid_ip_address():
		return false
	if addr == "::1" or addr == "0:0:0:0:0:0:0:1":
		return true
	if addr.begins_with("fc") or addr.begins_with("fd"):
		return true  # ULA fc00::/7
	# Link-local fe80::/10 (erste Gruppe fe80–febf).
	return (
		addr.begins_with("fe8")
		or addr.begins_with("fe9")
		or addr.begins_with("fea")
		or addr.begins_with("feb")
	)

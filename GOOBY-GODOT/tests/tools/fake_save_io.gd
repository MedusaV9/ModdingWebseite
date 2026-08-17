extends "res://scripts/state/save_manager.gd".SaveIo
## Fault-Injection-Fassade für die save_manager-Tests (EVAL-2026-08/C
## Befund 14): simuliert volle Platte, Permission-Fehler, Rename-Failure
## und den Prozess-Crash zwischen Rotationsschritten DETERMINISTISCH auf
## Dateisystem-Ebene — der Produktionspfad (SaveIo-Basisklasse) bleibt
## unangetastet. Nicht verbotene Operationen laufen ECHT (super), damit
## die Datei-Landschaft nach dem simulierten Fehler der Realität entspricht.

## Pfad-Endungen (ends_with-Match), für die oeffne_schreiben scheitert
## (Permission-Fehler auf der Zieldatei).
var open_verbieten: Array[String] = []
## Volle Platte: store_string schreibt nur die halbe Länge und meldet false.
var platte_voll := false
## Injizierter flush-Fehler (OK = kein Fehler).
var flush_fehler_injektion: Error = OK
## ZIEL-Endungen (ends_with-Match auf `nach`), für die benenne_um scheitert,
## ohne die Datei zu bewegen — so lässt sich das finale tmp→save-Rename
## (Ziel save_v5.json) getrennt von der Rotation (Ziele .bakN) verbieten.
var rename_verbieten: Array[String] = []
## true: entferne scheitert (Permission), Datei bleibt liegen.
var remove_verbieten := false
## Crash-Fenster: >= 0 = Anzahl noch erlaubter MUTIERENDER Operationen
## (oeffne_schreiben/schreibe/flushe/benenne_um/entferne). Ist das Budget
## aufgebraucht, "stirbt der Prozess": jede weitere Mutation wirkt nicht
## mehr und meldet einen Fehler — die Datei-Landschaft friert exakt auf
## dem Crash-Zeitpunkt ein. -1 = kein Crash.
var budget_mutationen := -1
## Mitschrift aller Operationen (Op + Dateiname) — pinnt die Reihenfolge
## Schreiben→Flush→Rotation→Rename im Test.
var protokoll: Array[String] = []

var _open_fehler: Error = OK


func existiert(pfad: String) -> bool:
	return super.existiert(pfad)


func lese_string(pfad: String) -> String:
	return super.lese_string(pfad)


func oeffne_schreiben(pfad: String) -> FileAccess:
	protokoll.append("open %s" % pfad.get_file())
	if _passt(pfad, open_verbieten) or not _mutation_erlaubt():
		_open_fehler = ERR_FILE_NO_PERMISSION
		return null
	_open_fehler = OK
	return super.oeffne_schreiben(pfad)


func letzter_open_fehler() -> Error:
	return _open_fehler if _open_fehler != OK else super.letzter_open_fehler()


func schreibe_string(f: FileAccess, text: String) -> bool:
	protokoll.append("write %d" % text.length())
	if not _mutation_erlaubt():
		return false
	if platte_voll:
		# Realistisch halb geschrieben: die .tmp enthält abgeschnittenes JSON.
		super.schreibe_string(f, text.substr(0, text.length() / 2))
		return false
	return super.schreibe_string(f, text)


func flushe(f: FileAccess) -> Error:
	protokoll.append("flush")
	if not _mutation_erlaubt():
		return ERR_FILE_CANT_WRITE
	if flush_fehler_injektion != OK:
		return flush_fehler_injektion
	return super.flushe(f)


func benenne_um(von: String, nach: String) -> Error:
	protokoll.append("rename %s -> %s" % [von.get_file(), nach.get_file()])
	if _passt(nach, rename_verbieten):
		return ERR_CANT_CREATE
	if not _mutation_erlaubt():
		return ERR_CANT_CREATE
	return super.benenne_um(von, nach)


func entferne(pfad: String) -> Error:
	protokoll.append("remove %s" % pfad.get_file())
	if remove_verbieten or not _mutation_erlaubt():
		return ERR_FILE_NO_PERMISSION
	return super.entferne(pfad)


static func _passt(pfad: String, muster: Array[String]) -> bool:
	for teil in muster:
		if pfad.ends_with(teil):
			return true
	return false


func _mutation_erlaubt() -> bool:
	if budget_mutationen < 0:
		return true
	if budget_mutationen == 0:
		return false
	budget_mutationen -= 1
	return true

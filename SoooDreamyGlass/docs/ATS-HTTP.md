# ATS-Entscheidung: Warum die App offenes HTTP erlaubt

Stand: v10.1 „Große Polish-Runde".

## Entscheidung

`NSAppTransportSecurity → NSAllowsArbitraryLoads: true` — global, ohne
Ausnahmen-Liste, in **beiden** Targets (App + Widget-Extension). Konfiguriert
in `SoooDreamy/ios/project.yml` (Info-Properties beider Targets).

## Begründung

- **Der private Paar-Server spricht NUR HTTP.** Er läuft zuhause bzw. auf
  einer eigenen Kiste (z. B. `http://138.201.60.230:4321`) ohne
  TLS-Terminierung. Ein Zertifikats-Setup (Let's Encrypt braucht Domain,
  Selbstsigniertes braucht Geräte-Profile) wäre für genau zwei
  Nutzer:innen reiner Overhead.
- **Die App ist privat und wird gesideloadet.** Kein App-Store-Review,
  keine ATS-Begründungspflicht gegenüber Apple. `NSAllowsArbitraryLoads`
  ist hier der vorgesehene, ehrliche Weg.
- **Keine Domain-Ausnahmen möglich:** Die Server-Adresse ist frei
  konfigurierbar (Settings → Server, mehrere Profile). Eine
  `NSExceptionDomains`-Liste kann eine erst zur Laufzeit eingetragene
  IP/Adresse prinzipiell nicht abdecken. Wichtig: KEIN
  `NSAllowsLocalNetworking` daneben setzen — das würde
  `NSAllowsArbitraryLoads` auf iOS wieder auf lokale Netze einschränken
  (genau der Bug, der in 10.0.1 gefixt wurde).

## Was das im Client bedeutet

- `ServerAddress.normalize` (Linux-getestet) ergänzt fehlende Schemata mit
  `http://` und schreibt `http://` NIE auf `https://` um.
- Das Serverfeld in den Einstellungen validiert nur Host/Schema und erklärt
  im Hilfetext (DE+EN), dass schlichtes `http://` völlig okay ist.
- WebSocket-Verbindungen (`ws://`) folgen derselben Policy.

## Rest-Risiko (bewusst akzeptiert)

Traffic zum Paar-Server ist auf Netzwerkebene unverschlüsselt. Akzeptiert,
weil: privates Zwei-Personen-System, Bearer-Token statt Passwörter,
sensible Inhalte (Vault) sind zusätzlich Ende-zu-Ende-verschlüsselt
(`VaultCrypto`). Wer später doch TLS will, trägt einfach eine
`https://`-Adresse ein — die funktioniert unverändert.

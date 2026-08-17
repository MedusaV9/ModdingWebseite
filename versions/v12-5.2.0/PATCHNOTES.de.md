# SoooDreamy 5.2.0 — Leistung & Verlässlichkeit

- Offline-Outbox für Chat, Reaktionen, Tagesantworten, Quest-Haken und Bewertungen mit stabilen Idempotenz-IDs.
- Verlustfreie Startmigration von `store.json` zu atomaren Paar-Segmenten; Speicher-/Medienquote in `/api/health`.
- Exponentieller WebSocket-Backoff mit Zufallsstreuung statt Reconnect-Sturm.
- Kaltstart-Signposts bis zum Dashboard und pixelbegrenztes Decoding großer Bilder.

Ehrlich: Medien-Uploads brauchen weiter eine aktive Verbindung; Startup-Zeiten
hängen vom Gerät ab. Das IPA ist unsigniert.

SoooDreamy — made by Sonic0810.

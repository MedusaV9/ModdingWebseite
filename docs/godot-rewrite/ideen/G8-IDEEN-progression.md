# G8-IDEEN — Progression, Ökonomie, Quests & Sammlungen (Ideen-Planner IP-5, Welle I)

**Bereich:** Level/XP (`scripts/logic/leveling.gd`, Max-Level 40) · Münzen
(`scripts/logic/economy.gd`, der EINE Geld-Pfad mit Tages-Deckel-Ledgern) · 24 Tagesquests
(`scripts/logic/quests/quest_engine.gd|quest_service.gd|quest_catalog.gd` +
`content/quests/data/quests.json`) · 44 Erfolge (`scripts/logic/achievements/*`, Münzsumme 3410) ·
4 Sammlungssets (`scripts/ui/album/collections_logic.gd`: fish 8 / veggies 8 / landmarks 6 /
treats 10) · 141 Sticker (`sticker_catalog.gd`/`sticker_unlocks.gd`, Rarities + Geheim-Sticker) ·
Codes (`scripts/ui/codes/codes_engine.gd` offline + `scripts/net/redeem_service.gd` Server) ·
Tagesbonus (`scripts/logic/daily/daily_bonus.gd`, Streak 1–7 mit Kulanztag).
**Quellen:** `UserFeedback.md` (komplett), Code-Streifzug NUR LESEND durch die o. g. Skripte plus
`reward_hub.gd`, `whats_next_advisor.gd`, `level_up_feier.gd`, `net_mail.gd`,
`scripts/social/visit_*.gd`, `scripts/ranch/quest/rquest_engine.gd`, `git log -30`
(Stand `bf77c0d7`). Vorhandene Planner-Lieferungen gelesen: `G8-IDEEN-home-seele.md` (IP-1) und
`G8-IDEEN-stadt-laeden-dlc.md` (IP-2) — Abgrenzung direkt darunter.

Aufwand als **S/M/L** (Umfang/Risiko/betroffene Systeme, keine Kalenderzeit), Impact **1–5**
(Langzeit-Motivation + Wohlfühl-Beitrag + Zeig-Wert), Risiko ehrlich mit Gegenmittel.

---

## Balance-Kompass (aus Code + UserFeedback destilliert)

**Ist-Ökonomie:** Ein entspannter Tag bringt grob 150–280 Münzen (3 Quests ≈ 60–90 + Brett-Bonus 50
+ Tagesbonus 20–100 + Post-Tagespaket 15–40 + Minispiele) — Senken dünnen nach IKEA-/Garderobe-
Sättigung aus, ab ~Level 15 stauen sich Münzen. Die großen Käufe (Goobye 2500 ab L12, Ranch ab L15)
sind gute Anker: **eine „große" Senke darf 1–2 entspannte Wochen kosten, nie mehr.** XP bis L40 sind
~41 000 (Kurve `100 + 50·(L−1)`) — Level sind das ehrliche Langzeit-Gerüst, aber ab ~L20 passiert
zwischen den Gates (L8 Schnell-Lieferung, L12 Goobye, L15 Ranch) NICHTS Sichtbares mehr.

**Was der User liebt/fordert (UserFeedback):** Dopamin-Momente (Konfetti, Count-Ups, Rekord-Feiern),
Liebe zum Detail, „EIN Spiel"-Gefühl, Läden/Orte die leben — und der Playtest-Fix `ec242ee3`
(farmbarer 0-Punkte-Reward) zeigt: **Ökonomie-Integrität ist ihm Feiern wert.** Wohlfühl-Regeln, die
JEDE Idee unten einhält: kein Fail-State, keine Deadline-Strafe (Vorbild: Streak-Kulanztag in
`daily_bonus.gd`), Belohnungen bevorzugt als Momente/Kosmetik/Props statt immer mehr Münzen
(Inflations-Bremse), alles Tages-/Wochen-Zufällige deterministisch geseedet
(`DailyQuestEngine.hash32` + mulberry32 — alle Freunde sehen dasselbe), Geld NUR über
`Economy.award/spend` mit reason-Tag, additive Save-Slices mit normalize (kein Version-Bump).

## Abgrenzung — was hier bewusst NICHT geplant wird

- **IP-2 besitzt die Laden-Ökonomie:** Goobye-Welle B, Preise, Warenkreisläufe, Stammkunden-Zähler,
  der **Wochenmarkt-SAMSTAG** (IP-2 P14) und die **Saison-Deko der STADT** (IP-2 P9). Meine
  Wochen-Ideen besetzen deshalb den **Sonntag**, meine Saison-Idee das **ALBUM** — zusammen ergibt
  das eine ganze Woche bzw. ein ganzes Jahr, ohne Doppelung.
- **IP-1 besitzt Haus-Seele + Erinnerungen:** das Andenken-Regal (IP-1 Nr. 3) zeigt SEELEN-Momente,
  meine Vitrine (Nr. 6) zeigt SAMMLER-Stolz — gleiche Möbel-Technik (SURFACE-Mini-Grid), zwei
  Inhalte; das Morgen-/Abend-Ritual (IP-1 Nr. 1) ist die BÜHNE des Tagesbonus, mein Stempelheft
  (Nr. 4) ist sein INHALT. Beides in den Konsolidierungs-Hinweisen verzahnt.

---

## TOP-3 (Begründung)

**🥇 Nr. 1 „Das Wochen-Vorhaben" — Ketten-Quests mit Mini-Geschichte.** Der Auftrag nennt
Ketten-Quests, Wochen-Rhythmus UND Langzeit ohne Grind — diese eine Idee liefert alle drei. Die
Bausteine sind komplett bewiesen: deterministische Seeds + Baseline-Zähler-Messung aus
`quest_engine.gd`, sequenzielle Ziel-Läufe aus `rquest_engine.gd` (Ranch macht Ketten seit RW-3
vor), Auszahlung über `quest_service._pay`. Kein neuer Event-Bus, keine Deadline — nur ein
erzählter Bogen über die Woche, der jedem Tag einen Grund gibt, „nur kurz reinzuschauen".

**🥈 Nr. 2 „Die Level-Reise" — Meilenstein-Feste statt stummer Zahlen.** Level sind das ehrlichste
Langzeit-System im Spiel (Max 40, ~41 000 XP), aber ab L15 unsichtbar: kein Spieler weiß, was als
Nächstes kommt, und ein Level-Up ist nur 2,6 s Konfetti (`level_up_feier.gd`). Eine Reise-Karte
mit echten Stationen (L8/L12/L15-Gates existieren im Code) plus gefeierte 5er-Meilensteine machen
aus derselben XP-Kurve Vorfreude — null Balancing-Risiko, weil keine Zahl angefasst wird
(der M2-Rework-Hook in `leveling.gd` bleibt unberührt).

**🥉 Nr. 3 „Geschenke mit Herz" — Wunschliste + Dankespost unter Freunden.** Der User will
„Langzeit-Motivation über Wochen MIT FREUNDEN", und die komplette Infrastruktur liegt schon da:
Mail mit Geschenk-Gutschrift (`net_mail.claim_gift`, Quota, Offline-Outbox, `mail_bounced`-
Rückbuchung), Freundesliste, Besuche. Es fehlt nur die SCHLEIFE: wissen was der Freund sich
wünscht → schenken → Danke zurückbekommen. Münzen wandern dabei NIE zwischen Spielern (der
Schenker KAUFT — Geschenke sind sogar eine charmante Münz-Senke), die Ökonomie bleibt dicht.

---

## Die priorisierte Liste (Nr. 1–16)

### 1. Das Wochen-Vorhaben — Ketten-Quest mit Mini-Geschichte
**Aufwand: M · Impact: 5 · Risiko: niedrig–mittel**

Jede Woche EIN „Vorhaben" mit 3–5 sequenziellen Schritten und einer kleinen Geschichte drum herum:
„Gooby will ein Drachenfest: 1) bastle einen Drachen (Craft), 2) übe im Park (Funkelpark-Besuch),
3) fang 3 windige Fische fürs Picknick, 4) Fest!" — der Abschluss ist ein sichtbarer Moment
(Prop im Garten für den Rest der Woche + Foto-Gelegenheit), dazu Münzen/XP über den EINEN Pfad
(`quest_service._pay`-Muster, reason `vorhaben`). Das Vorhaben wird deterministisch pro Woche
gezogen (`DailyQuestEngine.hash32("2026-W31")` + mulberry32, Wochen-String aus `clock.local_day()`),
Schritte messen sich am Baseline-Muster der Tagesquests (vorhandene `achievements.counters`/
`minigames.plays`-Differenzen), die Sequenz-Maschine kommt 1:1 vom Ranch-Vorbild
(`rquest_engine.gd`: zielIndex/zaehler, warte-Ziele erlaubt). WICHTIG fürs Wohlfühl: KEINE
Deadline — ein unfertiges Vorhaben läuft einfach weiter, das nächste startet erst nach Abschluss
(kein Verfall, kein Druck; der Wochen-Seed bestimmt nur das ANGEBOT). UI als zweiter Tab im
Quest-Blatt (`scripts/ui/quests/quest_panel.gd`), Inhalte als neue ContentRegistry-Domain
(`content/quests/data/vorhaben.json`, append-by-id — Packs können Wochen-Vorhaben nachliefern,
der `packs-v*`-Kanal existiert). Risiko: Text-Menge DE/EN (je Vorhaben ~10 Zeilen) und
Schritt-Balance — Gegenmittel: mit 6–8 Vorhaben starten, Golden-Test nach `roll_today`-Muster.

### 2. Die Level-Reise — Meilenstein-Feste statt stummer Zahlen
**Aufwand: M · Impact: 5 · Risiko: niedrig**

Tap auf den XP-Ring (`hud.set_level`-Anzeige) öffnet die „Level-Reise": ein geschwungener Pfad
1→40 mit ECHTEN Stationen aus dem Code — L8 Schnell-Lieferung (`Economy.QUICK_DELIVERY_LEVEL`),
L12 Goobye (`content/dlc` Unlock-Vorlage), L15 Ranch (`RanchKatalog.freischalt_level()`), dazu die
kleineren Level-Reads (Garderobe/Radio) und die künftigen DLC-Gates. Jedes 5. Level ist ein
MEILENSTEIN: die normale Feier (`level_up_feier.gd`, 2,6 s) wächst zum Fest — Torte-Prop im
Wohnzimmer, Stempel in den Reisepass (`passport_card.gd` hat die Stempelseite), eine Zeile von
Gooby („LEVEL 20! Ich sag's dem Kühlschrank!"), bei L40 die „Goldene Möhre"-Zeremonie als
Endspiel-Würdigung. Zwischen den echten Gates zeigt die Karte den nächsten Meilenstein als
Vorfreude-Ziel — der `whats_next_advisor.gd` (Prio-5-Zweig „level") verlinkt hierher. Die XP-Kurve
selbst bleibt UNANGETASTET (der M2-Rework-Hook in `leveling.gd` ist dokumentiert eingefroren; die
Karte LIEST nur `Leveling`-Konstanten und rendert sich bei einem späteren Rework einfach neu).
Risiko: praktisch keins — reine Sichtbarkeit + Feier-Ausbau über den vorhandenen `RewardHub`.

### 3. Geschenke mit Herz — Wunschliste, Dankespost, Schenker-Herzen
**Aufwand: M–L · Impact: 5 · Risiko: mittel**

Jeder Spieler pflegt eine Mini-Wunschliste (3 Slots, befüllbar aus IKEA-/Garderobe-Katalog), die
Freunde in der Telefon-Freunde-App (`friends_app.gd` seit G5-P34) und beim Besuch sehen. Schenken =
der Schenker KAUFT das Item zum Normalpreis (`Economy.spend`, reason `geschenk` — Münzen verlassen
seine Welt, wandern NIE zum Empfänger: Inflations-/Farming-Schutz bleibt wasserdicht) und es reist
über den VORHANDENEN Geschenk-Pfad (`net_mail.gd` send + `claim_gift` server-einmalig,
Offline-Outbox, `mail_bounced` bucht zurück; Server `GOOBY-SERVER/src/mail.js` + Tagesquota
existieren). Die Schleife zurück: der Empfänger-Gooby schreibt automatisch eine Dankeskarte mit
Foto des Items IM EINSATZ (Galerie-/Kamera-Pfad existiert), und der Schenker sammelt
„Schenker-Herzen" (neuer `achievements.counters`-Key `giftsSent` → Erfolgs-/Sticker-Linie
„Goldenes Herz" 1/5/20 — Zähler-Bump + `RewardHub.note_action`, Muster `questsDone`). Am
Geburtstag des Freundes (Profil-Datum) zählt ein Geschenk doppelt Herzen — die HAUS-Feier des
eigenen Geburtstags gehört IP-1 (Nr. 11), hier geht es nur um die Post-Ökonomie. Risiko: kleine
Server-Erweiterung (Wunschliste im Profil-Payload) + Missbrauchs-Kanten — Gegenmittel: vorhandene
Mail-Quota, keine Münz-Transfers, Herzen zählen nur bei UNTERSCHIEDLICHEN Empfängern pro Tag.

### 4. Das Monats-Stempelheft — der Tagesbonus wird zur Sammelkarte
**Aufwand: S–M · Impact: 4–5 · Risiko: sehr niedrig**

Der Tagesbonus plateaut ab Serientag 7 (`REWARD_TABLE`-Max 100 + Snack) — für „Wochen"-Motivation
fehlt die nächste Schicht. Neu: jeder Claim stempelt zusätzlich ein Monats-Stempelheft (additiver
Slice `daily.stempel = {monat: "YYYY-MM", tage: n}`, normalize nach Hausmuster), und bei 7/14/21
Stempeln IM MONAT gibt es Heft-Prämien: Sticker, ein kleines Saison-Prop, bei 21 etwas Besonderes
(z. B. exklusive Girlanden-Variante — Kosmetik statt Münzberg). Der Clou gegen Streak-Angst:
Stempel sind NICHT fortlaufend — verpasste Tage kosten nichts außer dem einen Stempel, 21 von ~30
ist mit entspanntem Rhythmus erreichbar (die Streak mit Kulanztag bleibt daneben unverändert
bestehen). Volle/abgelaufene Hefte wandern als Erinnerungsstücke ins Album („Stempelheft März" —
kleiner Sammel-Zeigewert gratis dazu). Anker: `daily_bonus.gd` (claim liefert schon alles),
`daily_bonus_popup.gd` (Heft-Rendering im Popup), `reward_hub.gd` (Feier). WICHTIG: IP-1 (Nr. 1)
inszeniert die Tagesbonus-BÜHNE im Morgen-Ritual — dieselbe Welle koordinieren, das Heft ist der
INHALT dieser Bühne. Risiko: praktisch keins; reine Additive.

### 5. Quest-Pool 24 → 40+ — neue Kategorien Stadt, Foto, Radio, Post
**Aufwand: S · Impact: 4 · Risiko: sehr niedrig**

Der Pool ist schief: 15 von 24 Quests sind Minispiel-Aufgaben, `economy` hat genau EINE, Stadt/
Foto/Radio/Post fehlen komplett — bei 3 Karten pro Tag wiederholt sich das Brett schnell. Neu:
~16 Quests als REINE DATEN in `content/quests/data/quests.json` über vorhandene Zähler („Mach 2
Fotos" — der `shutterbug`-Erfolg beweist den Foto-Zähler; „Hol das Post-Paket", „Fahr einmal
Guber", „Besuch 2 Orte", „Hör 10 Minuten Radio"); wo ein Zähler fehlt, ist der Bump eine Zeile an
der Quelle + `RewardHub.note_action` (Muster `questsDone` in `quest_service.claim`), maximal 1–2
neue `messung.typ`-Zweige in `_raw_progress` (Muster `spiele_verschieden`). Dazu `braucht`-Gates
für Level-Inhalte nutzen (Filter existiert) — und weil die Domain `quests` über die
ContentRegistry gemergt wird, können künftige Packs Quests OHNE App-Update nachliefern
(Live-Ops-Pfad gratis). Balance-Regel: neue Quests zahlen im bestehenden Korridor (10–30 Münzen,
5–15 XP), damit das Tageseinkommen stabil bleibt. Risiko: Tests, die das deterministische
Tagesbrett pinnen, müssen einmalig neu eingefroren werden (Pool-Größe ändert die Züge — bewusst,
Golden-Werte neu setzen).

### 6. Die Sammel-Vitrine — Sammlungen zum Herzeigen
**Aufwand: M · Impact: 4 · Risiko: niedrig**

Ein neues Möbel „Vitrine" (`furniture_catalog.gd`, erschwinglich ~300 Münzen — selbst eine kleine
Senke): unten rasten die 4 Set-Trophäen AUTOMATISCH ein, sobald ein Set geclaimt ist (Miniaturen
der vorhandenen `proc:goldfishBowl/goldenWateringCan/toyCity/candyJar`-Belohnungen + Messing-
Schildchen mit Claim-Datum aus `collections.claimedSets`-Timestamps); oben sind 3 Rahmen-Plätze,
in die man im Album Lieblings-Sticker pinnt (`sticker_card.gd` bekommt „Einrahmen"-Aktion). Beim
Besuch sehen FREUNDE die Vitrine — sie ist normales `home`-Inventar und reist damit über den
vorhandenen Besuchs-Schnappschuss (`scripts/social/visit_snapshot.gd`/`visit_room_view.gd`) —
Sammeln bekommt endlich Publikum. Gooby würdigt sie im Idle („Ich staube nur. Ich zähle NICHT
schon wieder die Fische.") und Tap auf ein Stück erzählt die `flavor_de`-Zeile aus dem
Sticker-Katalog. Abgrenzung: IP-1s Andenken-Regal (Nr. 3) zeigt Seelen-ERINNERUNGEN — gleiche
SURFACE-Grid-Technik, einmal bauen, zweimal einkleiden (Konsolidierungs-Hinweis unten). Risiko:
5–8 Miniatur-Props (prozedural nach F-Doc-Muster machbar).

### 7. Stadt-Stiftungen + Wunschbrunnen — Münz-Senken mit Charme
**Aufwand: M · Impact: 4 · Risiko: niedrig–mittel**

Gegen den Spät-Spiel-Münzstau zwei Senken mit Herz statt Preisschild-Erhöhung. (a) STIFTUNGS-TAFEL
am Park: Stadt-Projekte in Stufen anspenden (Brunnen-Lichter 500, Blüten-Allee 1200,
Funkelpark-Bank 2500 — Staffelung am Goobye-Anker „1–2 entspannte Wochen"), jede fertige Stufe
erscheint SICHTBAR in der Stadt + Messingschild „Gestiftet von {playerName}" + Einweihungs-Moment
mit Konfetti; Buchung als `Economy.spend(reason "stiftung")` + additiver Fortschritts-Slice
`city.stiftungen`, dazu eine kleine Erfolgs-/Sticker-Linie (Stifter 1/3). (b) WUNSCHBRUNNEN als
Mini-Ritual: 1–10 Münzen werfen, Gooby wünscht sich etwas (Soul-Line), Klimper-Sound — KEIN
Jackpot, keine Gegenleistung außer Worten (kein Glücksspiel-Loop; der vorhandene
`coinsSpent`-Sticker-Special in `sticker_unlocks.gd` zählt still mit). Koordination: die SICHTBARE
Deko-Seite (Einträge in `city_map.json`) gehört zu IP-2s Kulissen-Systemen — die Ökonomie-Schleife
(Stufen-Ledger, Zeremonie, Erfolge) liegt hier; im Konsolidierungs-Schnitt zusammenlegen. Risiko:
Deko-Assets pro Stufe — Gegenmittel: mit 3 Projekten starten, alles datengetrieben.

### 8. Der Sonntags-Ausklang — „Unsere Woche"-Kino + Sonntagsbrett
**Aufwand: M · Impact: 4 · Risiko: niedrig**

IP-2 macht den Samstag zum Markt-Höhepunkt (P14) — der Sonntag wird das Gegenstück zum Runterkommen,
damit die Woche einen ganzen Bogen hat: Mo Vorhaben-Start (Nr. 1) → Fr Markt-Gerücht (IP-2) →
Sa Markt (IP-2) → So Ausklang. Zwei Bausteine: (a) das Tagesbrett darf sonntags GEMÜTLICHE
Sonderquests ziehen („Picknick im Funkelpark", „Mach ein Foto von Gooby", „Geschichten-Stunde") —
dafür bekommt das `braucht`-Vokabular ein optionales `wochentag`-Feld (ein Zweig in
`DailyQuestEngine.requires_met` + Wochentag im `quest_service.ctx()`; der Tages-Seed bleibt
`hash32(day)`, Determinismus unangetastet); (b) beim ersten Heimkommen nach 17 Uhr bietet Gooby
das „Unsere Woche"-Kino an: 20-Sekunden-Montage aus ECHTEN Zählern der Woche (Quests erledigt,
Rekord der Woche, neuer Sticker, Vorhaben-Finale) über die VORHANDENE Rückblick-Technik
(`scripts/recap/recap_engine.gd`/`recap_service.gd`). Belohnung ist der Moment selbst (höchstens
ein 10-Münzen-Taschengeld) — kein zweites Bonus-System, keine Anwesenheitspflicht (verpasst =
nächsten Sonntag wieder). Risiko: niedrig; Wochen-Zähler-Snapshots als kleiner additiver Slice.

### 9. Brieflein von Nachbarn — Überraschungs-Quests von NPCs
**Aufwand: M · Impact: 4 · Risiko: mittel**

1–2× pro Woche (deterministisch: `hash32(day + ":npc")`-Gate, nie zwei gleichzeitig) steckt ein
handgeschriebenes Brieflein im Briefkasten (der Briefkasten existiert als Gestalten-Kategorie):
ein NPC bittet um etwas Kleines mit Mini-Geschichte — „Frau Rehwald: Mir ist der Blumenkasten
umgekippt… bringst du mir 2 Tomaten?", „Hilde: Der Wartezimmer-Gooby braucht ein Lächeln — ein
Foto von deinem?". Annehmen legt eine SONDER-Karte aufs Quest-Brett (additiver `quests.npc`-Slot,
gleiche Baseline-Messung wie Tagesquests, OHNE Deadline), der Abschluss bringt einen Dankesbrief
mit persönlicher Zeile + kleine Belohnungs-Rotation (Münzen, seltener ein Deko-Prop oder
Sticker-Fortschritt). Die Absender referenzieren den Stadt-Cast: WENN IP-2s benannte Figuren (P2)
landen, schreiben DIESELBEN — bis dahin die Laden-Inhaber; das näht Stadt und Progression zusammen
(„Ein-Spiel"-Gefühl auf der Quest-Ebene). Anker: `scripts/city/ui/post_sheet.gd`/Briefkasten,
`quest_engine.make_entry`-Muster, `quest_panel.gd`. Risiko: Text-Volumen DE/EN (je Brief ~6
Zeilen) — Gegenmittel: mit 8 Briefen starten, Domain-OWNERSHIP sauber eintragen.

### 10. Der Anbau — Haus-Ausbaustufen als große Wohlfühl-Senke
**Aufwand: L · Impact: 5 · Risiko: mittel–hoch**

Der Genre-Klassiker als GOOBY-Variante ohne Schulden: 2–3 zusätzliche Raum-Rohlinge
(Hobby-Zimmer, Wintergarten, Dachboden) als große Spar-Ziele (3000/5000 Münzen, Level-Gates nach
dem L12/L15-Muster) — KEIN Kredit, KEIN Nook-Brief: man spart hin (Synergie Nr. 14 Sparschwein)
und der Umbau ist ein Fest: Vorhang zu, Hammer-Qualm, Vorhang auf, Kamera-Schwenk durch den neuen
Raum (IP-2 nutzt exakt diese Dramaturgie für den Goobye-Umbau P5 — gleiche Bausteine teilen). Ein
neuer Raum ist ökonomisch ein Möbel-Multiplikator (mehr IKEA-Käufe = Folge-Senken) und emotional
„mein Zuhause WÄCHST mit uns". Anker: `scripts/home/home_state.gd` (Raum-Slices),
Baumodus-/NavMesh-Anschluss in `scripts/home/build_mode/`, `city`-Fassade wächst mit (Deko-Stufe).
Risiko: der teuerste Posten der Liste (Raum-Geometrie × Baumodus × Save-Migration additiv halten);
Gegenmittel: mit EINEM Raum-Rohling starten, Golden-Save-Tests, IP-1-Koordination (Haus-Gefühl).

### 11. Codewort der Woche — Codes als Community-Ritual
**Aufwand: M · Impact: 4 · Risiko: mittel**

Heute gibt es 3 statische Offline-Codes (`codes_engine.gd`), dabei ist die komplette
Kultur-Maschinerie schon gebaut: Server-Einlösung mit Zeitfenstern (`redeem_service.gd` kennt
`NOT_YET_VALID/EXPIRED/EXHAUSTED`, `GOOBY-SERVER/src/codes.js`), Pack-Updates für Offline-Codes
(`packs-v*`-Kanal). Neu ist die BÜHNE: jede Woche EIN Codewort, diegetisch verteilt — der
Radio-Moderator nuschelt es sonntags („Das Codewort der Woche ist… MÖHRENMONTAG!"), als Poster im
REHWEI-Schaufenster, gelegentlich versteckt im InstantGooby-Feed — und Freunde teilen es im
Discord (`discord.gg/BAPBAPMods`-Kultur… pardon: der GOOBY-Discord — genau die „mit Freunden über
Wochen"-Schleife). Belohnungen bewusst klein und kosmetisch (Sticker-Fortschritt, Hut-Farbe,
selten 50 Münzen) über das VORHANDENE Effekt-Vokabular (`coins/buff/sticker/unlock_flag`); die
Codes-Seite zeigt eingelöste Worte als kleines Sammelheft (`redeemed_entries` liefert die Historie
schon sortiert). Risiko: braucht wöchentliche Daten-Pflege — Gegenmittel: 8 Wochen vorproduzieren,
Server-Ausfall degradiert freundlich in die Outbox (existiert).

### 12. Saison-Seiten im Album — der Jahresring
**Aufwand: M–L · Impact: 4 · Risiko: mittel**

Die Saison-Mechanik existiert im Kleinen (4 `jz_*`-Sticker, `seasonsCollected`, `_season_of_day`
in `sticker_unlocks.gd`) — ausgebaut zu 4 kleinen Saison-Mini-Sets à 6 Einträge im Album, die man
NEBENBEI durch normale Aktivitäten in der echten Jahreszeit füllt (Winter-Fisch „Eisflosse" beim
Angeln, Frühlings-Blüte beim Gießen, Sommer-Eis beim Füttern…). Anti-FOMO fest eingebaut: eine
verpasste Saison kommt nächstes Jahr WIEDER (die Album-Seite sagt es wörtlich dazu: „Der Herbst
kommt wieder — versprochen."), nichts verfällt, Claims bleiben ewig möglich. Belohnung pro Set:
Saison-Deko (Girlanden-Varianten existieren als System) statt Münzen. Technisch:
`collections_logic.gd`-SETS von const auf Registry-gespeist erweitern (die `normalize_slice`
verliert nie fremde Einträge, `claimedSets` bleibt unantastbar — der Umbau ist save-sicher), die
Quell-Systeme buchen über das vorhandene `award_in_state`. Abgrenzung: IP-2 P9 macht die STADT
saisonal (Deko/Sortimente) — hier geht es um die SAMMLUNG; beide zusammen ergeben das Jahr.
Risiko: Content-Menge (24 Einträge + Props) — Gegenmittel: mit 2 Saisons launchen ist okay, der
Ring schließt sich übers Jahr.

### 13. Gerüchte-Ecke — die Geheim-Sticker bekommen eine Spur
**Aufwand: S · Impact: 3–4 · Risiko: niedrig**

Das Spiel hat liebevolle Geheimnisse (Schüttel-Secret, GOLDIGOLD, Rarity `geheim`,
Klopapier-Mumie), aber niemand erfährt, DASS es sie gibt — Entdecker-Kultur braucht Köder. Neu:
eine kleine „Man munkelt…"-Ecke (letzte Album-Seite oder GOB.TY-News-Ticker) zeigt pro Woche EIN
kryptisches Gerücht zu einem noch nicht gefundenen Geheimnis — deterministisch rotiert über die
gesperrten `secret`-Sticker, Text ist wörtlich deren VORHANDENES `hint_de`-Feld (die Rätsel sind
also schon geschrieben!). Gooby streut selten eine Gerüchte-Zeile im Idle
(`SeeleRunner.kommentar_global`, Frequenzbremse respektieren), und weil der n/N-Zähler
Geheim-Sticker weiterhin ausblendet (`page_progress`-Regel), entsteht Neugier statt
Komplettierungs-Druck. Freunde vergleichen Gerüchte → Discord-Gespräche → gemeinsames Entdecken
(zahlt direkt auf die Codes-/Geheimnis-Kultur ein, Schwester-Idee zu Nr. 11). Anker:
`sticker_catalog.gd` (`secret`/`hint_de`), `album_screen.gd`, `strings/de/soul_lines.json`.
Risiko: fast keins — reine Sichtbarkeit vorhandener Daten.

### 14. Das Sparschwein — große Käufe als Reise statt Wand
**Aufwand: S–M · Impact: 3–4 · Risiko: niedrig**

Goobye (2500) und Ranch stehen als Preis-Wände im Raum — ein Sparziel macht daraus eine Reise:
im Profil (oder am Sparschwein-Möbel) wählt man EIN Ziel („Ich spare auf: Ranch"), zahlt beliebig
ein, und ein kleines HUD-Schweinchen zeigt den Füllstand; Gooby feiert 25/50/75 % mit einer Zeile
und bei 100 % tanzt das Schwein und bietet den Kauf direkt an. Wohlfühl-Regeln: Auszahlen
jederzeit OHNE Abzug (kein Lock-in, kein Zins — Zinsen wären Inflation), das Ziel ist reine
Motivation (Goal-Gradient-Effekt). Technisch bewusst NICHT in `economy.gd` (die Datei ist
golden-geprüfte Web-Parität): eigener additiver Slice `sparziel = {ziel_id, eingezahlt}` mit
normalize, Ein-/Auszahlung als Paar `Economy.spend(reason "sparen")`/`Economy.award(reason
"sparenZurueck")` in EINEM `gs.update` — `coinsEarned/coinsSpent`-Statistik bleibt ehrlich, der
eine Geld-Pfad bleibt der eine. Anker: `game_state.update`, `hud.gd`-Chip, `profil_screen.gd`.
Risiko: niedrig; einzige Kante ist die Statistik-Semantik (oben gelöst).

### 15. Erfolgs-Momentum — „Fast geschafft" sichtbar machen
**Aufwand: S · Impact: 3 · Risiko: sehr niedrig**

Die 44 Erfolge sind ein stilles Langzeit-System: man sieht erledigte, aber nie, wie NAH man an
`feed100` oder `drive25` ist. Neu: der Erfolge-Screen (`achievements_screen.gd`) rendert pro
offenem Counter-Erfolg einen kleinen Fortschrittsbalken (`cond.count` vs.
`achievements.counters[key]` — die Engine liest das heute schon für den Unlock-Check) und oben
eine „Fast geschafft!"-Reihe mit den Top-3 nach Verhältnis (exakt die
`_best_open_quest`-Heuristik des `whats_next_advisor.gd`, wiederverwendet). Optional bekommt der
„Was nun?"-Hinweis eine niedrig-priore Erfolgs-Quelle („Nur noch 2 Wäschen bis ‚Schaumkanone'!") —
hinter den Quest-Prios, damit nichts drängelt. Kein neues System, keine neuen Belohnungen — nur
der vorhandene Sog wird sichtbar. Risiko: keins nennenswert; auf 6 Formaten gegenprüfen
(FB3-Konformität läuft ohnehin über den Screen).

### 16. Das Wochenglas — ein Koop-Ziel für den Freundeskreis
**Aufwand: L · Impact: 4 · Risiko: mittel–hoch**

Ein gemeinsames Wochenziel für den Freundeskreis: „Füllt zusammen das Möhrenglas — 300 Punkte!"
— Punkte fließen aus normalem Spielen (erledigte Quests, Minispiel-Runden; KEINE neuen
Grind-Aktionen), jeder Beitrag ist pro Spieler/Tag gedeckelt (das Tages-Ledger-Muster aus
`economy.gd::_book_day_ledger` als Vorlage — Vielspieler können Wenigspielern nichts wegnehmen
und nichts kaputt-farmen). Ist das Glas voll, bekommen ALLE im Kreis dieselbe Kosmetik/denselben
Sticker (bewusst NIE Münzen — die Spieler-Ökonomien bleiben getrennt), und das Glas selbst steht
als Prop sichtbar im Wohnzimmer und füllt sich live. Server-seitig ein kleines Modul nach der
bewährten Kopiervorlage (`GOOBY-SERVER/src/gvzmp.js`-Muster + `modules.js`-Registrierung +
Node-Tests), Client offline-first über die vorhandene Outbox. Das ist nach Nr. 3 der zweite
„Wochen mit Freunden"-Pfeiler — aber der teurere; erst nach Nr. 3 einplanen (teilt die
Freunde-App-UI). Risiko: Server-Aufwand + Schummel-Kanten — Gegenmittel: Caps, nur
Server-bestätigte Ereignisse zählen (Quest-Claims sind server-los → konservativ deckeln).

---

## Übersicht

| # | Idee | Aufwand | Impact | Kern-Anker |
|---|---|---|---|---|
| 1 | Wochen-Vorhaben (Ketten-Quest) | M | 5 | `quest_engine.gd`, `rquest_engine.gd`, `content/quests/` |
| 2 | Level-Reise & Meilenstein-Feste | M | 5 | `leveling.gd` (lesend), `level_up_feier.gd`, `passport_card.gd` |
| 3 | Geschenke mit Herz | M–L | 5 | `net_mail.gd`, `friends_app`, `GOOBY-SERVER/src/mail.js` |
| 4 | Monats-Stempelheft | S–M | 4–5 | `daily_bonus.gd`, `daily_bonus_popup.gd`, `reward_hub.gd` |
| 5 | Quest-Pool 24→40+ | S | 4 | `quests.json`, `quest_engine._raw_progress`, `RewardHub.note_action` |
| 6 | Sammel-Vitrine | M | 4 | `collections_logic.gd`, `furniture_catalog.gd`, `visit_snapshot.gd` |
| 7 | Stadt-Stiftungen + Wunschbrunnen | M | 4 | `economy.gd` (spend), `city_map.json` (IP-2-Koord.) |
| 8 | Sonntags-Ausklang | M | 4 | `recap_engine.gd`, `requires_met` (+`wochentag`) |
| 9 | Brieflein von Nachbarn | M | 4 | `post_sheet.gd`, `quest_engine.make_entry`, Stadt-Cast (IP-2 P2) |
| 10 | Der Anbau (Haus-Ausbau) | L | 5 | `home_state.gd`, `build_mode/`, Level-Gate-Muster |
| 11 | Codewort der Woche | M | 4 | `codes_engine.gd`, `redeem_service.gd`, `codes.js`, Radio |
| 12 | Saison-Seiten im Album | M–L | 4 | `collections_logic.gd`, `sticker_unlocks._season_of_day` |
| 13 | Gerüchte-Ecke (Geheimnisse) | S | 3–4 | `sticker_catalog.gd` (`hint_de`), `album_screen.gd` |
| 14 | Sparschwein mit Sparziel | S–M | 3–4 | eigener Slice + `Economy.spend/award`, `hud.gd` |
| 15 | Erfolgs-Momentum | S | 3 | `achievements_screen.gd`, `whats_next_advisor.gd` |
| 16 | Wochenglas (Koop-Ziel) | L | 4 | `modules.js`-Vorlage, `outbox.gd`, Tages-Ledger-Muster |

## Hinweise für den Konsolidierer (Welle J+)

- **Der Kadenz-Verbund ist das eigentliche Produkt:** Tag (Brett + Stempelheft) → Woche (Vorhaben,
  Sonntags-Ausklang, Codewort, Wochenglas) → Monat (Heft-Prämien) → Jahr (Saison-Seiten) → Karriere
  (Level-Reise, Anbau, Vitrine). Ideal ein „Wochen-Paket" (1+8+4) in EINER Welle testen — ein
  gemeinsamer Zeitsprung-Testlauf über 8 simulierte Tage deckt alle drei ab (`clock`-Pinning
  existiert überall).
- **IP-Koordination:** Nr. 6 teilt die SURFACE-Grid-Möbeltechnik mit IP-1 Nr. 3 (einmal bauen);
  Nr. 4 ist der Inhalt der IP-1-Nr.-1-Bühne (Tagesbonus im Morgen-Ritual); Nr. 7-Deko und Nr. 9-
  Absender laufen über IP-2-Systeme (P1/P2/P9-Kulissen bzw. Cast) — zusammenlegen, nicht doppeln.
- **Ökonomie-Leitplanken (bindend für ALLE Ideen):** Geld nur über `Economy.award/spend` mit
  reason-Tag; farmbare neue Quellen an ein Tages-Ledger hängen (`_book_day_ledger`-Muster); keine
  Münz-Transfers zwischen Spielern (Nr. 3/16 zahlen in Kosmetik/Momenten); neue Belohnungen im
  bestehenden Korridor (Quests 10–30 Münzen) — Langzeit-Motivation kommt aus SICHTBARKEIT und
  RITUALEN, nicht aus größeren Zahlen.
- **Determinismus + Tests:** alles Tages-/Wochen-Gewürfelte über `hash32`/mulberry32 mit
  injizierter Uhr (headless- und Playtest-Harness-tauglich, G7-P58); Pool-Änderungen (Nr. 5/8)
  frieren die Brett-Golden-Werte einmalig neu ein; `leveling.gd`/`economy.gd` selbst NICHT
  anfassen (Web-Paritäts-Golden + M2-Rework-Hook) — alle Ideen lesen nur bzw. buchen über die
  öffentlichen Pfade.
- **Wohlfühl-Abnahme je Idee:** keine Deadline, kein Verfall, kein Fail-State; jede neue Schleife
  braucht ihren „verpasst = kommt wieder"-Satz wörtlich im UI (Vorbilder: Streak-Kulanz,
  Tagesbonus-„Später"-Semantik).

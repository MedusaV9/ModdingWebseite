# Altar UI 2 (F-074) — Wiring-Notizen für den Hauptagenten

Task: Lesbarkeit + Kaufbestätigung + Kauf-Animation im `AltarScreen`, Nach-Kauf-
Mini-Zeremonie in der Welt (`economy/AltarBuyCeremony`). Diese Datei listet alles,
was NICHT im Task-Scope verdrahtet werden durfte und zentral nachgezogen wird.

## 1. Lang-Keys (Pflicht — sonst zeigt das Bestätigungs-Overlay rohe Keys)

`docs/plans_v3/langdrop/altar_ui2.json` (en_us + de_de) in
`assets/eclipse/lang/en_us.json` / `de_de.json` mergen. Sechs neue Keys, alle
`gui.eclipse.altar.confirm.*` (title, price, after, hint, buy, cancel). Alle
anderen vom neuen Screen benutzten Keys existieren bereits (altarui.json-Welle).

## 2. Payloads — KEINE Änderung an `EclipsePayloads.java` nötig

`network/altar/AltarPayloads.java` hat eine eigene Registrar-Route
(`RegisterPayloadHandlersEvent`-Subscriber auf dem MOD-Bus, Muster
`network.economy.ShardPayloads`). Dort minimal-additiv erweitert:

- Versionsgruppe `v5altarui3` → **`v6altarui4`** (Wire-Format von `ShopEntry`
  geändert; Client und Server müssen zusammen aktualisiert werden — bei uns
  immer der Fall, ein Jar).
- `ShopEntry` + 7. Feld `rewardItemId` (Item-Registry-ID der Belohnung, `""`
  für Nicht-Item-Angebote). Stream-Codec deshalb von `composite` auf
  handgerollt `StreamCodec.of` umgestellt (composite endet bei 6 Feldern).
- **Neu:** `S2CAltarBuyResultPayload` (`eclipse:altar/buy_result` — pos,
  offerId, success) → registriert in derselben Registrar-Route, Handler
  reicht an `AltarScreen.handleBuyResult` weiter. NICHT zusätzlich in
  `EclipsePayloads` registrieren.

## 3. WIRING(altar-model): "gift"-Animation des neuen GeckoLib-Altars

`economy/AltarBuyCeremony.Run#beatOpening()` trägt den markierten Kommentar:

```
// WIRING(altar-model): trigger "gift" animation here — ...
```

Wenn die parallele Altar-Modell-Welle gelandet ist (neuer
`AltarBlockEntity`-Renderer / `ritual/AltarModelTriggers`), dort den
"gift"-Trigger einhängen: der Beat feuert genau EINMAL pro erfolgreichem Kauf,
t = 0 des Zeremonie-Skripts (28 Ticks nach dem Server-Kauf, wenn das UI-Panel
seine eigene Kauf-Animation beendet hat). Position: `Run.altarPos`. Kein
weiterer Umbau nötig — nur der eine Aufruf.

## 4. Sonstiges (nur zur Kenntnis, nichts zu tun)

- Kein neuer FX-Cue, kein `FxCues`-Eintrag: die Welt-Zeremonie komponiert
  ausschließlich vorhandene Primitive (`S2CQuasarPayload` altar_beam /
  altar_pillar / altar_levelup_ring / heart_burst, `FxPayloads.FX_SHOCKWAVE`,
  vanilla `sendParticles`, `Display.ItemDisplay` nach dem
  `HeraldSummonSequence`-Muster).
- Kein neuer Photon-Effekt → kein `tools/photon/altar_buy_fx.py` nötig.
- Aufräum-Garantie der Gift-Displays: Tag `eclipse_altar_buy_gift` +
  Live-UUID-Sweep (StormDebrisFx-Doktrin). `/kill @e[tag=eclipse_altar_buy_gift]`
  räumt immer.

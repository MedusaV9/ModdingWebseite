// Admin-Dashboard (GAME-DESIGN §7.6) — server-gerendertes, selbst-tragendes
// HTML unter /admin: PIN-Gate (Env), dann die 5 Reports als Token-KARTEN im
// Banana-Vault-Look (W4-CSS-Pass: Sticker-Karten, KPI-Chips, Zebra-Tabellen —
// gleiche Struktur, nur Stil). tokens.css wird inline eingebettet;
// @font-face wird gestrippt — Fonts fallen auf System zurück.
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

let tokensCache: string | null = null;

function tokensCss(): string {
  if (tokensCache !== null) return tokensCache;
  const kandidaten = [
    resolve(process.cwd(), "client/shared/styles/tokens.css"),
    resolve(fileURLToPath(new URL(".", import.meta.url)), "../../client/shared/styles/tokens.css"),
  ];
  for (const pfad of kandidaten) {
    if (existsSync(pfad)) {
      tokensCache = readFileSync(pfad, "utf8").replace(/@font-face\s*\{[^}]*\}/g, "");
      return tokensCache;
    }
  }
  tokensCache =
    ":root{--mm-jungle-night:#0e2a1f;--mm-deep-palm:#14532d;--mm-vault-gold:#f5b301;--mm-ticket-paper:#fff6e3;--mm-curtain:#c2183b;--mm-leaf:#22a559;--mm-studio-led:#29d9d5;--mm-radius-s:6px;--mm-radius-m:12px;--mm-radius-l:20px;--mm-radius-rund:999px;--mm-outline:#1a1208;--mm-flaeche-tief:#123a28;--mm-text-gedimmt:#9dbfa9;--mm-coin-shine:#ffde6b;--mm-banana-leaf:#8fe04b;--mm-schatten-farbe:rgb(26 18 8 / 40%);--mm-schatten-sticker:2px 2px 0 0 var(--mm-schatten-farbe);--mm-schatten-sticker-gross:4px 4px 0 0 var(--mm-schatten-farbe)}";
  return tokensCache;
}

export function adminHtml(): string {
  return `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>MONKEY MONEY — Admin</title>
<style>
${tokensCss()}
body{margin:0 auto;max-width:1460px;background:radial-gradient(1100px 380px at 50% -120px,rgb(34 165 89 / 30%),rgb(34 165 89 / 0%)) var(--mm-jungle-night);color:var(--mm-ticket-paper);font-family:Rubik,system-ui,sans-serif;padding:28px 22px 64px}
h1{font-family:Bungee,system-ui;color:var(--mm-vault-gold);margin:0 0 4px;letter-spacing:0.02em;text-shadow:3px 3px 0 var(--mm-schatten-farbe,rgb(26 18 8 / 40%))}
h2{font-family:Bungee,system-ui;font-size:0.98rem;margin:30px 0 10px;color:var(--mm-studio-led);display:table;background:var(--mm-flaeche-tief,#123a28);border:3px solid var(--mm-outline,#1a1208);border-radius:var(--mm-radius-m,12px);box-shadow:var(--mm-schatten-sticker,2px 2px 0 0 rgb(26 18 8 / 40%));padding:5px 16px;rotate:-0.6deg}
.karte{background:var(--mm-deep-palm);border:3px solid var(--mm-outline,#1a1208);border-radius:var(--mm-radius-l,20px);box-shadow:var(--mm-schatten-sticker-gross,4px 4px 0 0 rgb(26 18 8 / 40%));padding:16px 18px;margin-top:10px;overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:0.9rem}
th{text-align:left;color:var(--mm-coin-shine,#ffde6b);font-size:0.72rem;text-transform:uppercase;letter-spacing:0.07em;padding:4px 12px 6px 8px;border-bottom:2px solid rgb(26 18 8 / 55%)}
td{padding:7px 12px 7px 8px;border-bottom:1px solid rgb(26 18 8 / 30%);vertical-align:top;font-variant-numeric:tabular-nums}
tr:nth-child(odd) td{background:rgb(26 18 8 / 12%)}
tr:last-child td{border-bottom:0}
.muted{color:var(--mm-text-gedimmt,#9dbfa9)}
.warn{color:var(--mm-vault-gold);font-weight:600}
.alarm{color:#ff7d9b;font-weight:700}
.ok{color:var(--mm-banana-leaf,#8fe04b);font-weight:600}
.pill{display:inline-block;padding:1px 9px;border-radius:var(--mm-radius-rund,999px);background:var(--mm-flaeche-tief,#123a28);border:2px solid var(--mm-outline,#1a1208);box-shadow:var(--mm-schatten-sticker,2px 2px 0 0 rgb(26 18 8 / 40%));font-size:.78rem;font-weight:600;margin:1px 0}
input,button{font:inherit;padding:9px 14px;border-radius:var(--mm-radius-m,12px);border:3px solid var(--mm-outline,#1a1208);background:var(--mm-flaeche-tief,#123a28);color:var(--mm-ticket-paper)}
input:focus{outline:3px solid var(--mm-vault-gold);outline-offset:1px}
button{cursor:pointer;background:var(--mm-vault-gold);color:var(--mm-outline,#1a1208);font-weight:800;box-shadow:var(--mm-schatten-sticker,2px 2px 0 0 rgb(26 18 8 / 40%))}
button:active{translate:1px 1px;box-shadow:1px 1px 0 0 var(--mm-schatten-farbe,rgb(26 18 8 / 40%))}
button.mini{padding:3px 11px;font-size:0.78rem;font-weight:700;background:var(--mm-flaeche-tief,#123a28);color:var(--mm-ticket-paper);border:2px solid var(--mm-outline,#1a1208);border-radius:var(--mm-radius-rund,999px);margin:2px 5px 2px 0}
button.mini:hover{background:var(--mm-deep-palm)}
button.mini.alarmierend{color:#ff7d9b;border-color:#ff7d9b}
#gate{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:34px auto;max-width:520px;background:var(--mm-deep-palm);border:3px solid var(--mm-outline,#1a1208);border-radius:var(--mm-radius-l,20px);box-shadow:var(--mm-schatten-sticker-gross,4px 4px 0 0 rgb(26 18 8 / 40%));padding:22px 24px;rotate:-0.5deg}
#gate input{flex:1;min-width:160px}
#kopf{display:flex;gap:12px;align-items:center;flex-wrap:wrap;background:transparent;border:0;box-shadow:none;padding:0;overflow:visible}
.kpi{display:inline-flex;flex-direction:column;gap:2px;background:var(--mm-flaeche-tief,#123a28);border:3px solid var(--mm-outline,#1a1208);border-radius:var(--mm-radius-m,12px);box-shadow:var(--mm-schatten-sticker,2px 2px 0 0 rgb(26 18 8 / 40%));padding:8px 16px;margin:0;font-size:0.78rem;color:var(--mm-text-gedimmt,#9dbfa9);text-transform:uppercase;letter-spacing:0.05em}
.kpi b{font-family:Bungee,system-ui;font-size:1.35rem;color:var(--mm-vault-gold);font-variant-numeric:tabular-nums;letter-spacing:0}
#kopf .muted{flex-basis:100%;font-size:0.82rem}
.kopfzeile{display:flex;gap:12px;align-items:center;flex-wrap:wrap}
.kopfzeile h2{margin:30px 0 10px}
.kopfzeile .mini{margin-top:20px}
#refresh-status{margin-top:20px;font-size:0.82rem}
</style>
</head>
<body>
<h1>🐒 MONKEY MONEY — Admin</h1>
<p class="muted">Die 5 Analytics-Reports (GAME-DESIGN §7.6) aus dem Event-Log. Nur lokal.</p>
<div id="gate">
  <input id="pin" type="password" placeholder="Admin-PIN" autocomplete="off" />
  <button id="rein">Rein da!</button>
  <span id="gate-fehler" class="alarm"></span>
</div>
<div id="inhalt" style="display:none">
  <div class="karte" id="kopf"></div>
  <div class="kopfzeile">
    <h2 id="titel-fehlerhaft">1 · Fehlerhaft-Queue</h2>
    <button id="refresh" class="mini" title="Aggregate neu berechnen und Reports neu laden">🔄 Aktualisieren</button>
    <span id="refresh-status" class="muted"></span>
  </div>
  <div class="karte" id="r-fehlerhaft"></div>
  <h2>2 · Schwierigkeits-Drift (Umstufungs-Vorschläge)</h2><div class="karte" id="r-drift"></div>
  <h2>3 · Abnutzung / zu oft gespielt</h2><div class="karte" id="r-abnutzung"></div>
  <h2>4 · Kategorie-Lücken (Soll aus CONTENT-PLAN)</h2><div class="karte" id="r-luecken"></div>
  <h2>5 · Feedback-Inbox</h2><div class="karte" id="r-feedback"></div>
  <h2>6 · Client-Fehler (pageerror-Telemetrie, letzte 20)</h2><div class="karte" id="r-clientfehler"></div>
</div>
<script>
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const pct = (q) => q === null || q === undefined ? "—" : Math.round(q * 100) + " %";

function tabelle(kopf, zeilen, leerText) {
  if (zeilen.length === 0) return '<p class="muted">' + esc(leerText) + "</p>";
  return "<table><tr>" + kopf.map((k) => "<th>" + esc(k) + "</th>").join("") + "</tr>" +
    zeilen.map((z) => "<tr>" + z.map((c) => "<td>" + c + "</td>").join("") + "</tr>").join("") + "</table>";
}

// ---------- Fehlerhaft-Queue-Aktionen (W20): Quarantäne / Entkräften / Geprüft ----------

function aktionen(f) {
  const qid = esc(f.questionId);
  return (f.quarantaene
      ? '<button class="mini" data-aktion="quarantaene" data-an="0" data-qid="' + qid + '" title="Frage wieder in die Match-Rotation aufnehmen">▶️ Zurück in Rotation</button>'
      : '<button class="mini alarmierend" data-aktion="quarantaene" data-an="1" data-qid="' + qid + '" title="Frage sofort aus der Match-Rotation nehmen">⛔ Quarantäne</button>') +
    (f.anzahl > 0
      ? '<button class="mini" data-aktion="entkraeften" data-an="1" data-qid="' + qid + '" title="Bisherige Flags ausblenden — neue Flags zählen wieder">🧹 Entkräften</button>'
      : "") +
    (f.geprueftTs
      ? '<button class="mini" data-aktion="geprueft" data-an="0" data-qid="' + qid + '" title="Geprüft-Vermerk entfernen">↩️ Prüfung aufheben</button>'
      : '<button class="mini" data-aktion="geprueft" data-an="1" data-qid="' + qid + '" title="Als inhaltlich geprüft markieren (mit Datum)">✓ Geprüft markieren</button>');
}

async function aktion(qid, pfad, an) {
  const pin = sessionStorage.getItem("mm:adminpin") || $("pin").value || "";
  const resp = await fetch("/api/admin/frage/" + encodeURIComponent(qid) + "/" + pfad, {
    method: "POST",
    headers: { "x-admin-pin": pin, "content-type": "application/json" },
    body: JSON.stringify({ an }),
  });
  if (!resp.ok) { $("refresh-status").textContent = "Aktion fehlgeschlagen (" + resp.status + ")"; return; }
  $("refresh-status").textContent = "";
  await lade(false);
}

function zeige(r) {
  $("gate").style.display = "none";
  $("inhalt").style.display = "block";
  $("kopf").innerHTML =
    '<span class="kpi">Matches verarbeitet <b>' + r.matchesVerarbeitet + "</b></span>" +
    '<span class="kpi">Fragen-Vorrat <b>' + r.luecken.gesamtIst + "</b> / Soll " + r.luecken.gesamtSoll + "</span>" +
    '<span class="kpi">Gesamt-Lücke <b>' + r.luecken.gesamtLuecke + "</b></span>" +
    '<span class="muted">Stand: ' + (r.aktualisiertTs ? new Date(r.aktualisiertTs).toLocaleString("de-DE") : "noch keine Daten") + "</span>";

  $("titel-fehlerhaft").textContent = "1 · Fehlerhaft-Queue (Stand " +
    (r.aktualisiertTs ? new Date(r.aktualisiertTs).toLocaleString("de-DE") : "noch keine Daten") + ")";
  $("r-fehlerhaft").innerHTML = tabelle(
    ["Frage", "Flags", "Gründe", "Status", "Aktionen"],
    r.fehlerhaft.map((f) => [
      esc(f.text) + ' <span class="muted">' + esc(f.questionId) + "</span>",
      f.anzahl,
      f.flags.map((x) => '<span class="pill" title="' + esc(new Date(x.ts).toLocaleString("de-DE")) + ' · Match ' + esc(x.matchId) + '">' + esc(x.grund) + "</span>").join(" "),
      (f.quarantaene ? '<span class="alarm">⛔ QUARANTÄNE (aus der Rotation)</span> ' : "") +
        (!f.quarantaene && f.ausRotationEmpfohlen ? '<span class="warn">Empfehlung: Quarantäne (≥ 2 Flags)</span> ' : "") +
        (!f.quarantaene && !f.ausRotationEmpfohlen && f.anzahl > 0 ? '<span class="warn">beobachten</span> ' : "") +
        (f.geprueftTs ? '<span class="ok" title="' + esc(new Date(f.geprueftTs).toLocaleString("de-DE")) + '">✓ geprüft ' + esc(new Date(f.geprueftTs).toLocaleDateString("de-DE")) + "</span>" : ""),
      aktionen(f),
    ]),
    "Keine geflaggten Fragen — saubere Show!");
  document.querySelectorAll("#r-fehlerhaft button[data-aktion]").forEach((b) =>
    b.addEventListener("click", () => aktion(b.dataset.qid, b.dataset.aktion, b.dataset.an === "1")));

  $("r-drift").innerHTML = tabelle(
    ["Frage", "Stufe", "Quote (bereinigt)", "n", "Vorschlag"],
    r.drift.map((d) => [
      esc(d.text) + ' <span class="muted">' + esc(d.questionId) + "</span>",
      esc(d.stufe),
      pct(d.quote),
      d.antworten,
      d.urteil === "quarantaene"
        ? '<span class="alarm">QUARANTÄNE' + (d.zielStufe ? " → " + esc(d.zielStufe) : "") + "</span>"
        : '<span class="warn">Umstufen → ' + esc(d.zielStufe) + "</span>",
    ]),
    "Keine Drift — alle Fragen sitzen in ihrem Schwierigkeits-Band.");

  $("r-abnutzung").innerHTML = tabelle(
    ["Frage", "Ausspielungen", "in 60 Tagen", "Quote", "Empfehlung"],
    r.abnutzung.map((a) => [
      esc(a.text) + ' <span class="muted">' + esc(a.questionId) + "</span>",
      a.ausspielungen,
      a.in60Tagen,
      pct(a.quote),
      (a.cooldownEmpfohlen ? '<span class="warn">Cooldown empfohlen (≥ 3×/60 T)</span> ' : '<span class="ok">ok</span> ') +
        (a.frageDerSchande ? '<span class="alarm">🏆 Frage der Schande (0 %)</span>' : ""),
    ]),
    "Noch keine Ausspielungen erfasst.");

  $("r-luecken").innerHTML = tabelle(
    ["Unterkategorie", "Ober", "Kern", "leicht", "mittel", "schwer", "ultra", "Lücke", "60-T-Verbrauch", "Reichweite"],
    r.luecken.zeilen.map((l) => [
      esc(l.slug), esc(l.oberkategorie), l.kern ? "★" : "",
      l.ist.leicht + "/" + l.soll.leicht, l.ist.mittel + "/" + l.soll.mittel,
      l.ist.schwer + "/" + l.soll.schwer, l.ist.ultrahard + "/" + l.soll.ultrahard,
      l.luecke > 0 ? '<span class="warn">' + l.luecke + "</span>" : '<span class="ok">0</span>',
      l.gespielt60,
      l.reichweiteAbende === null ? "—" : "≈ " + l.reichweiteAbende + " Abende",
    ]),
    "Kein Content-Verzeichnis gefunden.");

  $("r-feedback").innerHTML = tabelle(
    ["Wann", "Wer", "Match", "Text"],
    r.feedback.map((f) => [
      new Date(f.ts).toLocaleString("de-DE"),
      esc(f.name) + (f.profileId ? ' <span class="pill">Profil</span>' : ""),
      '<span class="muted">' + esc(f.matchId) + "</span>",
      esc(f.text),
    ]),
    "Noch kein Feedback — der GM kann am Match-Ende die Feedback-Runde starten.");
}

function zeigeClientFehler(fehler) {
  $("r-clientfehler").innerHTML = tabelle(
    ["Wann", "Phase", "Minigame", "Seite", "Meldung"],
    fehler.map((f) => [
      new Date(f.ts).toLocaleString("de-DE"),
      f.phase ? esc(f.phase) : '<span class="muted">—</span>',
      f.minigameId ? '<span class="pill">' + esc(f.minigameId) + "</span>" : '<span class="muted">—</span>',
      '<span class="muted">' + esc(f.url ?? "—") + "</span>",
      esc(f.msg) + (f.stack ? '<br /><span class="muted">' + esc(f.stack.split("\\n").slice(0, 3).join(" · ")) + "</span>" : ""),
    ]),
    "Keine gemeldeten Client-Fehler — saubere Front!");
}

async function lade(neuBerechnen) {
  // neuBerechnen=false ⇒ nur den materialisierten Stand lesen (schnell, nach
  // Moderations-Aktionen); sonst Aggregate frisch rechnen (Refresh/Erst-Laden).
  const frisch = neuBerechnen === false ? "0" : "1";
  const pin = $("pin").value || sessionStorage.getItem("mm:adminpin") || "";
  const resp = await fetch("/api/admin/reports?refresh=" + frisch, { headers: { "x-admin-pin": pin } });
  if (resp.status === 403) { $("gate-fehler").textContent = "PIN falsch."; return; }
  if (!resp.ok) { $("gate-fehler").textContent = "Fehler " + resp.status; return; }
  sessionStorage.setItem("mm:adminpin", pin);
  zeige((await resp.json()).reports);
  try {
    const fResp = await fetch("/api/admin/fehler", { headers: { "x-admin-pin": pin } });
    zeigeClientFehler(fResp.ok ? (await fResp.json()).fehler : []);
  } catch { zeigeClientFehler([]); }
}
$("rein").addEventListener("click", () => lade(true));
$("pin").addEventListener("keydown", (e) => e.key === "Enter" && lade(true));
$("refresh").addEventListener("click", async () => {
  $("refresh-status").textContent = "rechnet …";
  await lade(true);
  $("refresh-status").textContent = "aktualisiert " + new Date().toLocaleTimeString("de-DE");
});
if (sessionStorage.getItem("mm:adminpin")) lade(true);
</script>
</body>
</html>`;
}

// Die 6 Panel-Seiten (server-rendered). Alle Nutzerdaten via esc().

import { esc, layout, barChart, fmtTs, fmtDur } from './html.js';
import { analyticsData } from '../src/analytics.js';
import { codesData } from '../src/codes.js';
import { eventsData } from '../src/events.js';
import { friendsData } from '../src/friends.js';
import { dayKey } from '../src/config.js';

function playerName(ctx, deviceId) {
  const p = ctx.players[deviceId];
  return p ? `${p.name} (${p.friendCode})` : deviceId.slice(0, 12);
}

// ---------- Dashboard ----------
export function dashboardPage(ctx, { flash = '' } = {}) {
  const now = ctx.clock.now();
  const online = ctx.hub.onlineConns();
  const onlineRows = online
    .map(
      (c) => `<tr><td>${esc(c.friendCode)}</td><td>${esc(c.name)}</td>
      <td>${esc(c.presence?.label || 'ist online')}</td><td>${esc(fmtDur(now - c.connectedAt))}</td></tr>`
    )
    .join('');
  const rooms = [...ctx.rooms.rooms.values()];
  const roomRows = rooms
    .map(
      (r) =>
        `<tr><td><code>${esc(r.id)}</code></td><td>${r.members.size}</td><td>${esc(fmtDur(now - r.createdAt))}</td></tr>`
    )
    .join('');
  const recent = [...analyticsData(ctx).recent].reverse().slice(0, 10);
  const recentRows = recent
    .map(
      (s) => `<tr><td>${esc(playerName(ctx, s.deviceId))}</td>
      <td>${esc(fmtTs(s.startedAt))}</td><td>${esc(String(s.minutes))} min</td></tr>`
    )
    .join('');
  const body = `
  <div class="grid">
    <div class="card"><h2>Online</h2><div class="kpi">${online.length}</div>
      <table><tr><th>FriendCode</th><th>Name</th><th>Aktivität</th><th>Verbunden</th></tr>
      ${onlineRows || '<tr><td colspan="4" class="muted">Niemand online.</td></tr>'}</table></div>
    <div class="card"><h2>Aktive Rooms</h2><div class="kpi">${rooms.length}</div>
      <table><tr><th>Room</th><th>Mitglieder</th><th>Alter</th></tr>
      ${roomRows || '<tr><td colspan="3" class="muted">Keine aktiven Rooms.</td></tr>'}</table></div>
  </div>
  <div class="card"><h2>Letzte Sessions</h2>
    <table><tr><th>Spieler</th><th>Start</th><th>Dauer</th></tr>
    ${recentRows || '<tr><td colspan="3" class="muted">Noch keine Sessions gemeldet.</td></tr>'}</table></div>
  <div class="card"><h2>Server</h2>
    <p>Uptime: <strong>${esc(fmtDur(now - ctx.startedAt))}</strong> ·
       Spieler gesamt: <strong>${Object.keys(ctx.players).length}</strong> ·
       Datenverzeichnis: <strong>${Math.round(ctx.store.dataSizeBytes() / 1024)} KB</strong></p></div>`;
  return layout('Dashboard', body, { active: '/panel/', flash });
}

// ---------- Analytics (WICHTIGSTE Seite: Spielzeit) ----------
export function analyticsPage(ctx, query = {}) {
  const data = analyticsData(ctx);
  const tz = ctx.cfg.tz;
  const now = ctx.clock.now();
  const filter = typeof query.player === 'string' && query.player ? query.player : null;

  // Minuten/Tag, letzte 30 Tage (optional pro Spieler gefiltert).
  const days = [];
  for (let i = 29; i >= 0; i--) {
    const key = dayKey(now - i * 24 * 3600_000, tz);
    const bucket = data.days[key] || {};
    let minutes = 0;
    let sessions = 0;
    for (const [deviceId, agg] of Object.entries(bucket)) {
      if (filter && deviceId !== filter) continue;
      minutes += agg.minutes;
      sessions += agg.sessions;
    }
    days.push({ label: key.slice(8), hint: key, value: Math.round(minutes), sessions });
  }

  // Pro-Spieler-Tabelle: wie lange (gesamt), wie oft (Sessions), zuletzt.
  const perPlayer = Object.entries(data.perPlayer)
    .sort((a, b) => b[1].minutes - a[1].minutes)
    .map(
      ([deviceId, s]) => `<tr><td><a href="/panel/analytics?player=${esc(encodeURIComponent(deviceId))}">${esc(
        playerName(ctx, deviceId)
      )}</a></td>
      <td>${esc(String(Math.round(s.minutes)))} min</td><td>${s.sessions}</td>
      <td>${esc(String(Math.round((s.minutes / Math.max(s.sessions, 1)) * 10) / 10))} min</td>
      <td>${esc(fmtTs(s.lastAt))}</td></tr>`
    )
    .join('');

  // Top-Spielzeiten: beste Tage insgesamt.
  const topDays = Object.entries(data.days)
    .map(([key, bucket]) => ({
      key,
      minutes: Object.entries(bucket)
        .filter(([id]) => !filter || id === filter)
        .reduce((sum, [, v]) => sum + v.minutes, 0),
    }))
    .filter((d) => d.minutes > 0)
    .sort((a, b) => b.minutes - a.minutes)
    .slice(0, 10)
    .map((d) => `<tr><td>${esc(d.key)}</td><td>${esc(String(Math.round(d.minutes)))} min</td></tr>`)
    .join('');

  // Wann wird gespielt: Session-Starts pro Stunde.
  const hours = Array.from({ length: 24 }, (_, h) => ({
    label: String(h),
    hint: `${h}:00–${h}:59 Uhr`,
    value: data.hours[String(h).padStart(2, '0')] || 0,
  }));

  const filterNote = filter
    ? `<div class="notice">Gefiltert auf <strong>${esc(playerName(ctx, filter))}</strong>
       — <a href="/panel/analytics">Filter entfernen</a></div>`
    : '';
  const body = `${filterNote}
  <div class="card"><h2>Spielzeit pro Tag (Minuten, letzte 30 Tage${filter ? ', gefiltert' : ''})</h2>
    ${barChart(days, { unit: ' min' })}</div>
  <div class="card"><h2>Sessions pro Spieler (wie oft / wie lange)</h2>
    <table><tr><th>Spieler</th><th>Gesamt</th><th>Sessions</th><th>Ø Länge</th><th>Zuletzt</th></tr>
    ${perPlayer || '<tr><td colspan="5" class="muted">Noch keine Daten.</td></tr>'}</table></div>
  <div class="grid">
    <div class="card"><h2>Top-Spielzeiten (beste Tage)</h2>
      <table><tr><th>Tag</th><th>Minuten</th></tr>
      ${topDays || '<tr><td colspan="2" class="muted">Noch keine Daten.</td></tr>'}</table></div>
    <div class="card"><h2>Wann wird gespielt? (Session-Starts pro Stunde, ${esc(tz)})</h2>
      ${barChart(hours, { color: '#59c9b9' })}</div>
  </div>`;
  return layout('Analytics', body, { active: '/panel/analytics' });
}

// ---------- Codes ----------
export function codesPage(ctx, { flash = '' } = {}) {
  const data = codesData(ctx);
  const rows = Object.entries(data.codes)
    .sort((a, b) => b[1].createdAt - a[1].createdAt)
    .map(([name, c]) => {
      const status = c.active ? '<span class="ok">aktiv</span>' : '<span class="off">deaktiviert</span>';
      const uses = `${c.uses}${c.maxUses ? ` / ${c.maxUses}` : ''}`;
      const window = `${c.validFrom ? fmtTs(c.validFrom) : '—'} → ${c.validUntil ? fmtTs(c.validUntil) : '—'}`;
      const deactivate = c.active
        ? `<form class="inline" method="post" action="/panel/api/codes/deactivate">
           <input type="hidden" name="code" value="${esc(name)}"><button class="small">Deaktivieren</button></form>`
        : '';
      return `<tr><td><code>${esc(name)}</code></td><td><code>${esc(JSON.stringify(c.reward))}</code></td>
      <td>${esc(uses)}</td><td>${Object.keys(c.redemptions).length}</td><td>${esc(window)}</td><td>${status} ${deactivate}</td></tr>`;
    })
    .join('');
  const body = `
  <div class="card"><h2>Neuen Code anlegen</h2>
  <form method="post" action="/panel/api/codes"><div class="formrow">
    <label>Code<input name="code" placeholder="SOMMER26" required></label>
    <label>Reward (JSON)<input name="reward" value='{"coins":500}' size="30" required></label>
    <label>Max. Nutzungen<input name="maxUses" type="number" min="1" placeholder="unbegrenzt"></label>
    <label>Gültig bis (YYYY-MM-DD)<input name="validUntil" placeholder="optional"></label>
    <button type="submit">Anlegen</button></div></form>
  <p class="muted">Einlösung: 1× pro Gerät. Client-Endpoint: <code>POST /api/codes/redeem</code>.</p></div>
  <div class="card"><h2>Codes</h2>
  <table><tr><th>Code</th><th>Reward</th><th>Nutzungen</th><th>Einlösungen</th><th>Gültigkeit</th><th>Status</th></tr>
  ${rows || '<tr><td colspan="6" class="muted">Noch keine Codes.</td></tr>'}</table></div>`;
  return layout('Codes', body, { active: '/panel/codes', flash });
}

// ---------- Events ----------
export function eventsPage(ctx, { flash = '' } = {}) {
  const data = eventsData(ctx);
  const now = ctx.clock.now();
  const rows = Object.entries(data.events)
    .sort((a, b) => b[1].at - a[1].at)
    .slice(0, 50)
    .map(([id, e]) => {
      const state = e.expiresAt > now ? '<span class="ok">läuft</span>' : '<span class="off">abgelaufen</span>';
      return `<tr><td><code>${esc(id)}</code></td><td>${esc(e.type)}</td>
      <td><code>${esc(JSON.stringify(e.params))}</code></td><td>${esc(e.target)}</td>
      <td>${esc(fmtTs(e.at))}</td><td>${e.deliveredTo.length}</td><td>${state}</td></tr>`;
    })
    .join('');
  const body = `
  <div class="card"><h2>Event auslösen</h2>
  <form method="post" action="/panel/api/events"><div class="formrow">
    <label>Typ<select name="type">
      <option value="WEATHER_RAIN">WEATHER_RAIN (Regen)</option>
      <option value="DOUBLE_COINS">DOUBLE_COINS (Doppel-Münzen)</option>
      <option value="ANNOUNCEMENT">ANNOUNCEMENT (Ansage-Text)</option>
      <option value="CUSTOM">CUSTOM (Typ aus Params-Feld „type“)</option>
    </select></label>
    <label>Params (JSON)<input name="params" value='{"durationMin":60}' size="26"></label>
    <label>Ziel<input name="target" value="all" size="12"></label>
    <label>Gültig (Minuten)<input name="ttlMin" type="number" value="1440" min="1"></label>
    <button type="submit">Senden</button></div></form>
  <p class="muted">Online-Clients bekommen sofort einen <code>SERVER_EVENT</code>-Push; Offline-Clients
  holen das Event beim nächsten Boot ab (<code>WELCOME.pendingEvents</code>).</p></div>
  <div class="card"><h2>Verlauf</h2>
  <table><tr><th>ID</th><th>Typ</th><th>Params</th><th>Ziel</th><th>Ausgelöst</th><th>Zugestellt an</th><th>Status</th></tr>
  ${rows || '<tr><td colspan="7" class="muted">Noch keine Events.</td></tr>'}</table></div>`;
  return layout('Events', body, { active: '/panel/events', flash });
}

// ---------- Freunde-Graph ----------
export function friendsPage(ctx) {
  const data = friendsData(ctx);
  const codes = [...new Set(data.edges.flatMap((e) => [e.a, e.b]))];
  // Simples Kreis-Layout: Knoten auf einem Kreis, Kanten als Linien, grün = online.
  const size = 460;
  const cx = size / 2;
  const cy = size / 2;
  const r = size / 2 - 70;
  const pos = new Map(
    codes.map((code, i) => {
      const angle = (2 * Math.PI * i) / Math.max(codes.length, 1) - Math.PI / 2;
      return [code, [cx + r * Math.cos(angle), cy + r * Math.sin(angle)]];
    })
  );
  const lines = data.edges
    .map((e) => {
      const [x1, y1] = pos.get(e.a);
      const [x2, y2] = pos.get(e.b);
      return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="#4a3b36" stroke-width="2" opacity="0.5"/>`;
    })
    .join('');
  const nodes = codes
    .map((code) => {
      const [x, y] = pos.get(code);
      const deviceId = ctx.byCode.get(code);
      const online = deviceId && ctx.hub.isOnline(deviceId);
      const name = deviceId ? ctx.players[deviceId]?.name : code;
      return `<g><title>${esc(code)}</title>
      <circle cx="${x}" cy="${y}" r="16" fill="${online ? '#2e9e6b' : '#ff7ba9'}" stroke="#4a3b36" stroke-width="2"/>
      <text x="${x}" y="${y + 30}" font-size="11" text-anchor="middle" fill="#4a3b36">${esc(name)}</text></g>`;
    })
    .join('');
  const edgeRows = data.edges
    .map((e) => {
      const nameOf = (code) => {
        const id = ctx.byCode.get(code);
        return id ? `${ctx.players[id].name} (${code})` : code;
      };
      return `<tr><td>${esc(nameOf(e.a))}</td><td>${esc(nameOf(e.b))}</td><td>${esc(fmtTs(e.since))}</td></tr>`;
    })
    .join('');
  const reqRows = data.requests
    .map((r) => `<tr><td>${esc(r.from)}</td><td>${esc(r.to)}</td><td>${esc(fmtTs(r.at))}</td></tr>`)
    .join('');
  const body = `
  <div class="grid">
    <div class="card"><h2>Wer ist mit wem befreundet? (grün = online)</h2>
      ${codes.length ? `<svg viewBox="0 0 ${size} ${size}" width="100%">${lines}${nodes}</svg>` : '<p class="muted">Noch keine Freundschaften.</p>'}</div>
    <div>
    <div class="card"><h2>Freundschaften</h2>
      <table><tr><th>Spieler</th><th>Spieler</th><th>Seit</th></tr>
      ${edgeRows || '<tr><td colspan="3" class="muted">Keine.</td></tr>'}</table></div>
    <div class="card"><h2>Offene Anfragen</h2>
      <table><tr><th>Von</th><th>An</th><th>Am</th></tr>
      ${reqRows || '<tr><td colspan="3" class="muted">Keine.</td></tr>'}</table></div>
    </div>
  </div>`;
  return layout('Freunde-Graph', body, { active: '/panel/friends' });
}

// ---------- Spieler ----------
export function playersPage(ctx) {
  const rows = Object.entries(ctx.players)
    .sort((a, b) => (b[1].lastSeenAt || 0) - (a[1].lastSeenAt || 0))
    .map(([deviceId, p]) => {
      const online = ctx.hub.isOnline(deviceId);
      return `<tr><td>${esc(p.friendCode)}</td><td>${esc(p.name)}</td><td>${esc(p.goobyName)}</td>
      <td>${online ? '<span class="ok">online</span>' : esc(fmtTs(p.lastSeenAt))}</td>
      <td>${esc(String(p.coins))}${p.coinsUpdatedAt ? '' : ' <span class="muted">(nie gemeldet)</span>'}</td>
      <td>${esc(fmtTs(p.createdAt))}</td></tr>`;
    })
    .join('');
  const body = `<div class="card"><h2>Spieler (${Object.keys(ctx.players).length})</h2>
  <table><tr><th>FriendCode</th><th>Spitzname</th><th>Gooby</th><th>Zuletzt online</th><th>Coins (Cache)</th><th>Dabei seit</th></tr>
  ${rows || '<tr><td colspan="6" class="muted">Noch keine Spieler.</td></tr>'}</table>
  <p class="muted">Coins sind ein Anzeige-Cache (Client meldet per SYNC) — die echte Balance liegt client-seitig.</p></div>`;
  return layout('Spieler', body, { active: '/panel/players' });
}

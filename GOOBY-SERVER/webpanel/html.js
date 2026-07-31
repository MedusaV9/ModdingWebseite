// Panel-Rendering: reine Template-Strings, KEIN Frontend-Build, kein EJS.
// Jede Interpolation von Nutzerdaten läuft durch esc() (XSS-Sanitize).

export function esc(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

const NAV = [
  ['/panel/', 'Dashboard'],
  ['/panel/analytics', 'Analytics'],
  ['/panel/pal', 'GoobyPal'],
  ['/panel/spiele', 'Spiele & Besuche'],
  ['/panel/ranch', 'Ranch'],
  ['/panel/codes', 'Codes'],
  ['/panel/events', 'Events'],
  ['/panel/friends', 'Freunde-Graph'],
  ['/panel/players', 'Spieler'],
];

const CSS = `
  :root { --bg:#fff6ec; --card:#ffffff; --ink:#4a3b36; --pink:#ff7ba9; --teal:#59c9b9; --gold:#ffd166; }
  * { box-sizing:border-box; }
  body { margin:0; font-family:system-ui,-apple-system,"Segoe UI",sans-serif; background:var(--bg); color:var(--ink); }
  header { background:var(--ink); color:#fff; padding:10px 20px; display:flex; align-items:center; gap:18px; flex-wrap:wrap; }
  header h1 { font-size:18px; margin:0; }
  header a { color:#ffd166; text-decoration:none; font-weight:600; font-size:14px; }
  header a.active { color:#fff; border-bottom:2px solid var(--pink); }
  header form { margin-left:auto; }
  main { max-width:1100px; margin:24px auto; padding:0 16px; }
  .card { background:var(--card); border:2px solid var(--ink); border-radius:14px; padding:16px 18px; margin-bottom:18px; box-shadow:3px 3px 0 rgba(74,59,54,.15); }
  .card h2 { margin:0 0 10px; font-size:16px; }
  table { border-collapse:collapse; width:100%; font-size:14px; }
  th, td { text-align:left; padding:6px 10px; border-bottom:1px solid #eadfd4; }
  th { background:#fdeede; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(300px,1fr)); gap:18px; }
  .kpi { font-size:28px; font-weight:800; color:var(--pink); }
  .muted { color:#9a877e; font-size:12px; }
  .ok { color:#2e9e6b; font-weight:700; } .off { color:#b0a49b; }
  input, select, textarea, button { font:inherit; padding:6px 10px; border:2px solid var(--ink); border-radius:8px; background:#fff; color:var(--ink); }
  button { background:var(--pink); color:#fff; font-weight:700; cursor:pointer; }
  button.small { padding:2px 8px; font-size:12px; }
  form.inline { display:inline; }
  .formrow { display:flex; gap:10px; flex-wrap:wrap; align-items:flex-end; margin-top:8px; }
  .formrow label { display:flex; flex-direction:column; font-size:12px; gap:4px; }
  .err { background:#ffe1e1; border:2px solid #c04a4a; padding:8px 12px; border-radius:8px; margin-bottom:12px; }
  .notice { background:#e2f6ef; border:2px solid #2e9e6b; padding:8px 12px; border-radius:8px; margin-bottom:12px; }
  code { background:#fdeede; padding:1px 5px; border-radius:5px; }
`;

export function layout(title, body, { active = '', flash = '' } = {}) {
  const nav = NAV.map(
    ([href, label]) =>
      `<a href="${href}" class="${active === href ? 'active' : ''}">${esc(label)}</a>`
  ).join('');
  return `<!doctype html>
<html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} — GOOBY Panel</title><style>${CSS}</style></head>
<body><header><h1>GOOBY&nbsp;Panel</h1>${nav}
<form method="post" action="/panel/logout"><button class="small">Logout</button></form></header>
<main>${flash}${body}</main></body></html>`;
}

export function loginPage({ error = '' } = {}) {
  return `<!doctype html>
<html lang="de"><head><meta charset="utf-8"><title>Login — GOOBY Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1"><style>${CSS}
.login { max-width:360px; margin:12vh auto; }</style></head>
<body><main class="login"><div class="card"><h2>GOOBY Panel — Login</h2>
${error ? `<div class="err">${esc(error)}</div>` : ''}
<form method="post" action="/panel/login">
<div class="formrow"><label>Admin-Passwort
<input type="password" name="password" autofocus autocomplete="current-password"></label>
<button type="submit">Anmelden</button></div></form>
<p class="muted">Gesetzt über die ENV-Variable <code>GOOBY_ADMIN_PASSWORD</code>.</p>
</div></main></body></html>`;
}

// Simples Balkendiagramm als Inline-SVG: items = [{label, value, hint?}].
export function barChart(items, { width = 1000, height = 220, color = '#ff7ba9', unit = '' } = {}) {
  if (!items.length) return '<p class="muted">Noch keine Daten.</p>';
  const max = Math.max(...items.map((i) => i.value), 1);
  const bw = Math.max(6, Math.floor(width / items.length) - 4);
  const chartH = height - 40;
  const bars = items
    .map((item, idx) => {
      const h = Math.max(1, Math.round((item.value / max) * chartH));
      const x = idx * (bw + 4) + 2;
      const y = 10 + (chartH - h);
      const title = `${esc(item.hint ?? item.label)}: ${esc(String(item.value))}${esc(unit)}`;
      const label =
        items.length <= 40
          ? `<text x="${x + bw / 2}" y="${height - 6}" font-size="9" text-anchor="middle" fill="#9a877e">${esc(item.label)}</text>`
          : '';
      return `<g><title>${title}</title><rect x="${x}" y="${y}" width="${bw}" height="${h}" rx="3" fill="${color}"></rect>${label}</g>`;
    })
    .join('');
  const w = items.length * (bw + 4) + 4;
  return `<svg viewBox="0 0 ${w} ${height}" width="100%" preserveAspectRatio="xMinYMid meet" role="img">${bars}</svg>`;
}

export function fmtTs(ms) {
  if (!ms) return '—';
  return new Date(ms).toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
}

export function fmtDur(ms) {
  const min = Math.floor(ms / 60_000);
  if (min < 60) return `${min} min`;
  return `${Math.floor(min / 60)} h ${min % 60} min`;
}

// Rennzeit-Format für Bestenlisten: "1:23,456" (Minuten:Sekunden,Millis).
export function fmtZeit(ms) {
  if (!Number.isFinite(ms)) return '—';
  const min = Math.floor(ms / 60_000);
  const sec = Math.floor((ms % 60_000) / 1000);
  const rest = Math.floor(ms % 1000);
  return `${min}:${String(sec).padStart(2, '0')},${String(rest).padStart(3, '0')}`;
}

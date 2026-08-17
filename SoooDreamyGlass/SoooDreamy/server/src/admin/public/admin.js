/* SoooDreamy admin panel — vanilla JS, no build step.
   Talks to /admin/api/* with the httpOnly session cookie. */
(() => {
  'use strict';

  // --- i18n -----------------------------------------------------------------

  const I18N = {
    de: {
      'app.admin': 'Admin',
      'nav.logout': 'Abmelden',
      'nav.refresh': 'Aktualisieren',
      'login.title': 'Willkommen zurück',
      'login.hint': 'Das Passwort steht in der Server-Konsole — bei jedem Start neu.',
      'login.placeholder': 'wolke-herz-funke-mond',
      'login.submit': 'Anmelden',
      'login.err.bad': 'Falsches Passwort.',
      'login.err.rate': 'Zu viele Versuche — bitte kurz warten.',
      'login.err.generic': 'Anmeldung fehlgeschlagen.',
      'server.title': 'Server',
      'server.version': 'Version',
      'server.uptime': 'Läuft seit',
      'server.couples': 'Paare',
      'server.segments': 'Segmente',
      'server.media': 'Medien',
      'server.quarantine': 'Quarantäne',
      'server.quarantine.none': 'keine 🎉',
      'server.files': 'Dateien',
      'backup.title': 'Backups',
      'backup.now': 'Backup jetzt',
      'backup.last': 'Letztes Backup',
      'backup.none': 'noch keins',
      'backup.count': 'Vorhanden',
      'backup.interval': 'Automatik',
      'backup.interval.off': 'aus',
      'backup.every': 'alle {n} min',
      'backup.done': 'Backup erstellt ✓',
      'couples.title': 'Paare',
      'couples.empty': 'Noch keine Paare auf diesem Server.',
      'couple.code': 'Code',
      'couple.created': 'erstellt',
      'couple.lastActive': 'zuletzt aktiv',
      'couple.never': 'noch nie',
      'health.ok': 'gesund',
      'health.recovered': 'aus Backup geheilt',
      'health.quarantined': 'Quarantäne',
      'health.quarantined.hint': 'Daten beschädigt — mit `npm run restore` wiederherstellen. Dateien liegen unter data/quarantine/.',
      'counts.messages': 'Nachrichten',
      'counts.photos': 'Fotos',
      'counts.videos': 'Videos',
      'counts.events': 'Termine',
      'counts.games': 'Spiele',
      'counts.songs': 'Songs',
      'counts.coupons': 'Gutscheine',
      'member.online': 'online',
      'member.lastSeen': 'zuletzt',
      'member.sessions': '{n} Gerät(e)',
      'member.app': 'App',
      'member.app.unknown': 'App-Version unbekannt',
      'tab.sessions': 'Geräte',
      'tab.codes': 'Codes',
      'tab.qr': 'Login-QR',
      'sessions.none': 'Keine Sitzungen.',
      'sessions.revoke': 'Ausloggen',
      'sessions.revokeAll': 'Alle Geräte von {name} ausloggen',
      'sessions.revoked': 'widerrufen',
      'sessions.expired': 'abgelaufen',
      'sessions.live': 'aktiv',
      'sessions.adminQr': 'Admin-QR',
      'sessions.revoked.toast': 'Sitzung widerrufen ✓',
      'sessions.revokedAll.toast': '{n} Sitzung(en) widerrufen ✓',
      'confirm.no': 'Abbrechen',
      'confirm.yes': 'Ja, machen',
      'confirm.revoke.title': 'Gerät ausloggen?',
      'confirm.revoke.text': '„{name}“ wird sofort abgemeldet und muss sich neu verbinden.',
      'confirm.revokeAll.title': 'Alle Geräte ausloggen?',
      'confirm.revokeAll.text': 'Alle Sitzungen von {name} werden sofort ungültig.',
      'confirm.invite.title': 'Neuen Einladungs-Code erzeugen?',
      'confirm.invite.text': 'Der alte Code {code} wird sofort ungültig.',
      'confirm.recovery.title': 'Neuen Recovery-Schlüssel für {name}?',
      'confirm.recovery.text': 'Der bisherige Schlüssel wird ungültig. Der neue wird genau EINMAL angezeigt.',
      'confirm.replace.title': 'Neuen Ersatz-Code für {name}?',
      'confirm.replace.text': 'Damit kann sich ein neues Gerät auf den Platz von {name} verbinden. Ältere Ersatz-Codes werden ungültig.',
      'codes.invite': 'Einladungs-Code des Paares',
      'codes.invite.new': 'Neuen Code erzeugen',
      'codes.recovery': 'Recovery-Schlüssel',
      'codes.recovery.set': 'gesetzt {when}',
      'codes.recovery.unset': 'noch keiner',
      'codes.recovery.new': 'Neu erzeugen',
      'codes.replace': 'Ersatz-Code',
      'codes.replace.present': 'einer ist hinterlegt',
      'codes.replace.absent': 'keiner hinterlegt',
      'codes.replace.new': 'Neu erzeugen',
      'codes.once': 'Nur jetzt sichtbar — sicher weitergeben!',
      'codes.copy': 'Kopieren',
      'codes.copied': 'Kopiert ✓',
      'qr.hint': 'Frischer Rejoin-Token als QR — mit der SoooDreamy-App scannen, dann verbindet sich das Handy wieder mit seinem Platz.',
      'qr.server': 'Server-URL im QR',
      'qr.generate': 'QR für {name} erzeugen',
      'qr.validUntil': 'Token gültig bis {when} — der QR bleibt danach als Rejoin-Beweis nutzbar, bis er verwendet oder das Gerät ausgeloggt wird.',
      'qr.copy': 'Deep-Link kopieren',
      'logs.title': 'Server-Log',
      'logs.empty': 'Noch keine Log-Zeilen.',
      'audit.title': 'Admin-Protokoll',
      'audit.empty': 'Noch keine Admin-Aktionen.',
      'audit.login': 'Anmeldung',
      'audit.login_failed': 'Fehlversuch bei der Anmeldung',
      'audit.logout': 'Abmeldung',
      'audit.invite_code_reset': 'Einladungs-Code erneuert',
      'audit.recovery_key_reset': 'Recovery-Schlüssel erneuert',
      'audit.replace_code_reset': 'Ersatz-Code erzeugt',
      'audit.session_revoked': 'Sitzung widerrufen',
      'audit.sessions_revoked_all': 'Alle Sitzungen widerrufen',
      'audit.rejoin_qr_issued': 'Login-QR erzeugt',
      'audit.backup_created': 'Backup erstellt',
      'footer.note': 'Mit 💜 verwaltet · made by Sonic0810',
      'err.generic': 'Das hat nicht geklappt.',
      'err.unauthorized': 'Sitzung abgelaufen — bitte neu anmelden.',
      'time.now': 'gerade eben',
      'time.min': 'vor {n} min',
      'time.hours': 'vor {n} Std.',
      'time.days': 'vor {n} Tagen',
    },
    en: {
      'app.admin': 'Admin',
      'nav.logout': 'Log out',
      'nav.refresh': 'Refresh',
      'login.title': 'Welcome back',
      'login.hint': 'The password is in the server console — new on every start.',
      'login.placeholder': 'cloud-heart-spark-moon',
      'login.submit': 'Sign in',
      'login.err.bad': 'Wrong password.',
      'login.err.rate': 'Too many attempts — please wait a moment.',
      'login.err.generic': 'Login failed.',
      'server.title': 'Server',
      'server.version': 'Version',
      'server.uptime': 'Up since',
      'server.couples': 'Couples',
      'server.segments': 'Segments',
      'server.media': 'Media',
      'server.quarantine': 'Quarantine',
      'server.quarantine.none': 'none 🎉',
      'server.files': 'files',
      'backup.title': 'Backups',
      'backup.now': 'Backup now',
      'backup.last': 'Latest backup',
      'backup.none': 'none yet',
      'backup.count': 'Available',
      'backup.interval': 'Automatic',
      'backup.interval.off': 'off',
      'backup.every': 'every {n} min',
      'backup.done': 'Backup created ✓',
      'couples.title': 'Couples',
      'couples.empty': 'No couples on this server yet.',
      'couple.code': 'Code',
      'couple.created': 'created',
      'couple.lastActive': 'last active',
      'couple.never': 'never',
      'health.ok': 'healthy',
      'health.recovered': 'healed from backup',
      'health.quarantined': 'quarantined',
      'health.quarantined.hint': 'Data damaged — restore with `npm run restore`. Files are kept under data/quarantine/.',
      'counts.messages': 'messages',
      'counts.photos': 'photos',
      'counts.videos': 'videos',
      'counts.events': 'events',
      'counts.games': 'games',
      'counts.songs': 'songs',
      'counts.coupons': 'coupons',
      'member.online': 'online',
      'member.lastSeen': 'seen',
      'member.sessions': '{n} device(s)',
      'member.app': 'App',
      'member.app.unknown': 'app version unknown',
      'tab.sessions': 'Devices',
      'tab.codes': 'Codes',
      'tab.qr': 'Login QR',
      'sessions.none': 'No sessions.',
      'sessions.revoke': 'Log out',
      'sessions.revokeAll': 'Log out all devices of {name}',
      'sessions.revoked': 'revoked',
      'sessions.expired': 'expired',
      'sessions.live': 'active',
      'sessions.adminQr': 'Admin QR',
      'sessions.revoked.toast': 'Session revoked ✓',
      'sessions.revokedAll.toast': '{n} session(s) revoked ✓',
      'confirm.no': 'Cancel',
      'confirm.yes': 'Yes, do it',
      'confirm.revoke.title': 'Log out device?',
      'confirm.revoke.text': '“{name}” is signed out immediately and must reconnect.',
      'confirm.revokeAll.title': 'Log out all devices?',
      'confirm.revokeAll.text': 'Every session of {name} becomes invalid immediately.',
      'confirm.invite.title': 'Generate a new invite code?',
      'confirm.invite.text': 'The old code {code} becomes invalid immediately.',
      'confirm.recovery.title': 'New recovery key for {name}?',
      'confirm.recovery.text': 'The previous key becomes invalid. The new one is shown exactly ONCE.',
      'confirm.replace.title': 'New replace code for {name}?',
      'confirm.replace.text': 'A new device can re-attach to {name}’s slot with it. Older replace codes become invalid.',
      'codes.invite': 'Couple invite code',
      'codes.invite.new': 'Generate new code',
      'codes.recovery': 'Recovery key',
      'codes.recovery.set': 'set {when}',
      'codes.recovery.unset': 'none yet',
      'codes.recovery.new': 'Generate new',
      'codes.replace': 'Replace code',
      'codes.replace.present': 'one is stored',
      'codes.replace.absent': 'none stored',
      'codes.replace.new': 'Generate new',
      'codes.once': 'Visible only now — hand over securely!',
      'codes.copy': 'Copy',
      'codes.copied': 'Copied ✓',
      'qr.hint': 'A fresh rejoin token as a QR — scan it with the SoooDreamy app and the phone re-attaches to its slot.',
      'qr.server': 'Server URL inside the QR',
      'qr.generate': 'Generate QR for {name}',
      'qr.validUntil': 'Token valid until {when} — afterwards the QR still works as rejoin proof until used or the device is logged out.',
      'qr.copy': 'Copy deep link',
      'logs.title': 'Server log',
      'logs.empty': 'No log lines yet.',
      'audit.title': 'Admin audit trail',
      'audit.empty': 'No admin actions yet.',
      'audit.login': 'Login',
      'audit.login_failed': 'Failed login attempt',
      'audit.logout': 'Logout',
      'audit.invite_code_reset': 'Invite code reset',
      'audit.recovery_key_reset': 'Recovery key reset',
      'audit.replace_code_reset': 'Replace code issued',
      'audit.session_revoked': 'Session revoked',
      'audit.sessions_revoked_all': 'All sessions revoked',
      'audit.rejoin_qr_issued': 'Login QR issued',
      'audit.backup_created': 'Backup created',
      'footer.note': 'Managed with 💜 · made by Sonic0810',
      'err.generic': 'That did not work.',
      'err.unauthorized': 'Session expired — please sign in again.',
      'time.now': 'just now',
      'time.min': '{n} min ago',
      'time.hours': '{n} h ago',
      'time.days': '{n} days ago',
    },
  };

  let lang = localStorage.getItem('sooodreamy-admin-lang')
    || (navigator.language?.toLowerCase().startsWith('de') ? 'de' : 'en');
  if (!I18N[lang]) lang = 'en';

  function t(key, vars = {}) {
    let text = I18N[lang][key] ?? I18N.en[key] ?? key;
    for (const [name, value] of Object.entries(vars)) text = text.replaceAll(`{${name}}`, String(value));
    return text;
  }

  function applyStaticI18n() {
    document.documentElement.lang = lang;
    for (const node of document.querySelectorAll('[data-i18n]')) node.textContent = t(node.dataset.i18n);
    for (const node of document.querySelectorAll('[data-i18n-placeholder]')) {
      node.placeholder = t(node.dataset.i18nPlaceholder);
    }
    $('#lang-toggle').textContent = lang.toUpperCase();
  }

  // --- helpers ----------------------------------------------------------------

  const $ = (selector, root = document) => root.querySelector(selector);

  function el(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) {
      if (key === 'class') node.className = value;
      else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
      else if (value !== undefined && value !== null) node.setAttribute(key, value);
    }
    for (const child of children.flat()) {
      if (child === null || child === undefined) continue;
      node.append(child.nodeType ? child : document.createTextNode(String(child)));
    }
    return node;
  }

  function fmtWhen(iso) {
    if (!iso) return t('couple.never');
    const ms = Date.now() - Date.parse(iso);
    if (Number.isNaN(ms)) return String(iso);
    if (ms < 90 * 1000) return t('time.now');
    if (ms < 60 * 60 * 1000) return t('time.min', { n: Math.round(ms / 60000) });
    if (ms < 48 * 60 * 60 * 1000) return t('time.hours', { n: Math.round(ms / 3600000) });
    return t('time.days', { n: Math.round(ms / 86400000) });
  }

  function fmtClock(iso) {
    try {
      return new Date(iso).toLocaleString(lang === 'de' ? 'de-DE' : 'en-GB', {
        dateStyle: 'medium',
        timeStyle: 'short',
      });
    } catch {
      return String(iso);
    }
  }

  function fmtBytes(bytes) {
    if (!Number.isFinite(bytes)) return '–';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
    return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
  }

  function toast(message, kind = 'ok') {
    const node = el('div', { class: `toast ${kind}` }, message);
    $('#toasts').append(node);
    setTimeout(() => node.remove(), 3200);
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      toast(t('codes.copied'));
    } catch {
      window.prompt('Copy:', text);
    }
  }

  function confirmDialog(title, text) {
    return new Promise((resolve) => {
      $('#confirm-title').textContent = title;
      $('#confirm-text').textContent = text;
      const backdrop = $('#confirm-backdrop');
      backdrop.hidden = false;
      const done = (answer) => {
        backdrop.hidden = true;
        yes.removeEventListener('click', onYes);
        no.removeEventListener('click', onNo);
        resolve(answer);
      };
      const yes = $('#confirm-yes');
      const no = $('#confirm-no');
      const onYes = () => done(true);
      const onNo = () => done(false);
      yes.addEventListener('click', onYes);
      no.addEventListener('click', onNo);
    });
  }

  async function api(method, path, body) {
    const response = await fetch(`/admin/api${path}`, {
      method,
      headers: body === undefined ? {} : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let payload = null;
    try {
      payload = await response.json();
    } catch { /* non-JSON error body */ }
    if (response.status === 401) {
      showLogin();
      throw Object.assign(new Error('unauthorized'), { code: 'admin_unauthorized', status: 401 });
    }
    if (!response.ok) {
      throw Object.assign(new Error(payload?.message ?? 'request failed'), {
        code: payload?.error ?? 'error',
        status: response.status,
      });
    }
    return payload;
  }

  // --- views ---------------------------------------------------------------------

  const state = {
    server: null,
    couples: [],
    quarantined: [],
    openPanel: null, // {coupleId, tab}
    secrets: {}, // coupleId -> {invite?, [memberId_recovery]?, [memberId_replace]?}
    qr: {}, // coupleId -> {svg, deepLink, expiresAt, memberId}
    refreshTimer: null,
  };

  function showLogin() {
    $('#login-view').hidden = false;
    $('#dash-view').hidden = true;
    $('#topbar').hidden = false;
    $('#logout-btn').hidden = true;
    clearInterval(state.refreshTimer);
    setTimeout(() => $('#login-password').focus(), 60);
  }

  function showDash() {
    $('#login-view').hidden = true;
    $('#dash-view').hidden = false;
    $('#topbar').hidden = false;
    $('#logout-btn').hidden = false;
    clearInterval(state.refreshTimer);
    state.refreshTimer = setInterval(() => {
      if (!document.hidden) refresh().catch(() => {});
    }, 60000);
  }

  async function refresh() {
    const data = await api('GET', '/state');
    state.server = data.server;
    state.couples = data.couples;
    state.quarantined = data.quarantined;
    renderServer();
    renderBackup();
    renderCouples();
    renderLogs().catch(() => {});
    renderAudit().catch(() => {});
  }

  function kvRow(key, value) {
    return el('div', { class: 'kv-row' },
      el('span', { class: 'k' }, key),
      el('span', { class: 'v' }, value));
  }

  function renderServer() {
    const server = state.server;
    const storage = server.storage ?? {};
    const quarantineCount = (storage.quarantine?.couples ?? 0) + state.quarantined.length > 0
      ? `${state.quarantined.length || storage.quarantine?.couples || 0} ⚠️`
      : t('server.quarantine.none');
    const card = $('#server-card');
    card.replaceChildren(
      el('div', { class: 'card-head' },
        el('h2', {}, `💌 ${t('server.title')}`),
        el('span', { class: 'chip' }, `v${server.version}`)),
      el('div', { class: 'kv' },
        kvRow(t('server.uptime'), fmtClock(server.startedAt)),
        kvRow(t('server.couples'), String(storage.couples ?? state.couples.length)),
        kvRow(t('server.segments'), `${storage.segmentFiles ?? '–'} ${t('server.files')} · ${fmtBytes(storage.segmentBytes)}`),
        kvRow(t('server.media'), `${storage.mediaFiles ?? '–'} ${t('server.files')} · ${fmtBytes(storage.mediaBytes)}`),
        kvRow(t('server.quarantine'), quarantineCount)));
  }

  function renderBackup() {
    const server = state.server;
    const latest = server.latestBackup;
    const interval = server.backupIntervalMinutes;
    const button = el('button', {
      class: 'btn btn-accent btn-small',
      type: 'button',
      onclick: async (event) => {
        const btn = event.currentTarget;
        btn.disabled = true;
        try {
          await api('POST', '/backups');
          toast(t('backup.done'));
          await refresh();
        } catch (err) {
          toast(err.message || t('err.generic'), 'err');
        } finally {
          btn.disabled = false;
        }
      },
    }, `⬇ ${t('backup.now')}`);
    $('#backup-card').replaceChildren(
      el('div', { class: 'card-head' }, el('h2', {}, `🗄 ${t('backup.title')}`), button),
      el('div', { class: 'kv' },
        kvRow(t('backup.last'), latest ? `${fmtWhen(latest.createdAt)} · ${fmtBytes(latest.bytes)}` : t('backup.none')),
        kvRow(t('backup.interval'), interval > 0 ? t('backup.every', { n: interval }) : t('backup.interval.off'))));
  }

  function healthBadge(health) {
    if (health === 'quarantined') return el('span', { class: 'badge badge-danger' }, `⛑ ${t('health.quarantined')}`);
    if (health === 'recovered') return el('span', { class: 'badge badge-warn' }, `🩹 ${t('health.recovered')}`);
    return el('span', { class: 'badge badge-ok' }, `✓ ${t('health.ok')}`);
  }

  function coupleDisplayName(couple) {
    if (couple.name) return couple.name;
    const names = couple.members.map((m) => m.name).filter(Boolean);
    return names.length > 0 ? names.join(' & ') : couple.id;
  }

  function renderCouples() {
    const list = $('#couples-list');
    list.replaceChildren();
    if (state.couples.length === 0 && state.quarantined.length === 0) {
      list.append(el('div', { class: 'glass card empty' }, t('couples.empty')));
      return;
    }
    for (const couple of state.couples) list.append(coupleCard(couple));
    for (const entry of state.quarantined) list.append(quarantinedCard(entry));
  }

  function quarantinedCard(entry) {
    return el('article', { class: 'glass couple' },
      el('div', { class: 'couple-head' },
        el('div', { class: 'couple-title' },
          el('span', { class: 'couple-name' }, entry.id),
          healthBadge('quarantined'))),
      el('p', { class: 'muted', style: 'margin:10px 0 0; font-size:13.5px;' }, t('health.quarantined.hint')),
      el('div', { class: 'chips', style: 'margin-top:10px;' },
        entry.files.map((file) => el('span', { class: 'chip' }, `${file.file}`))));
  }

  function memberTile(couple, member) {
    const app = member.appVersions[0] ?? null;
    return el('div', { class: 'member' },
      el('span', { class: 'avatar' }, member.avatar ?? '💞',
        el('span', { class: `dot${member.online ? ' online' : ''}` })),
      el('div', { class: 'member-info' },
        el('div', { class: 'member-name' }, member.name ?? member.id),
        el('div', { class: 'member-meta' },
          member.online ? t('member.online') : `${t('member.lastSeen')} ${fmtWhen(member.lastSeenAt)}`),
        el('div', { class: 'member-meta', title: member.appVersions.join('\n') },
          app ? `${t('member.app')}: ${app}` : t('member.app.unknown')),
        el('div', { class: 'member-meta' }, t('member.sessions', { n: member.activeSessions }))));
  }

  function coupleCard(couple) {
    const open = state.openPanel?.coupleId === couple.id ? state.openPanel.tab : null;
    const tabButton = (tab, label) => el('button', {
      class: `pill${open === tab ? ' active' : ''}`,
      type: 'button',
      onclick: () => {
        state.openPanel = open === tab ? null : { coupleId: couple.id, tab };
        renderCouples();
      },
    }, label);

    const counts = Object.entries(couple.counts)
      .filter(([, count]) => count > 0)
      .map(([key, count]) => el('span', { class: 'chip' }, `${count} ${t(`counts.${key}`)}`));
    if (couple.segmentBytes !== null) counts.push(el('span', { class: 'chip' }, fmtBytes(couple.segmentBytes)));

    const card = el('article', { class: 'glass couple' },
      el('div', { class: 'couple-head' },
        el('div', { class: 'couple-title' },
          el('span', { class: 'couple-name' }, coupleDisplayName(couple)),
          el('span', { class: 'chip code' }, couple.code),
          healthBadge(couple.health)),
        el('span', { class: 'muted', style: 'font-size:12.5px;' },
          `${t('couple.lastActive')}: ${fmtWhen(couple.lastActiveAt)} · ${t('couple.created')} ${fmtClock(couple.createdAt)}`)),
      el('div', { class: 'members' }, couple.members.map((member) => memberTile(couple, member))),
      el('div', { class: 'chips' }, counts),
      el('div', { class: 'couple-actions' },
        tabButton('sessions', `📱 ${t('tab.sessions')}`),
        tabButton('codes', `🔑 ${t('tab.codes')}`),
        tabButton('qr', `🔳 ${t('tab.qr')}`)));

    if (open) {
      const detail = el('div', { class: 'detail' });
      card.append(detail);
      if (open === 'sessions') renderSessionsPanel(detail, couple);
      if (open === 'codes') renderCodesPanel(detail, couple);
      if (open === 'qr') renderQrPanel(detail, couple);
    }
    return card;
  }

  // --- sessions panel ---------------------------------------------------------

  async function renderSessionsPanel(root, couple) {
    root.replaceChildren(el('div', { class: 'empty' }, '…'));
    let sessions;
    try {
      ({ sessions } = await api('GET', `/couples/${couple.id}/sessions`));
    } catch (err) {
      root.replaceChildren(el('div', { class: 'empty' }, err.message));
      return;
    }
    root.replaceChildren();
    if (sessions.length === 0) {
      root.append(el('div', { class: 'empty' }, t('sessions.none')));
      return;
    }
    for (const session of sessions) {
      const status = session.revokedAt
        ? el('span', { class: 'badge badge-danger' }, t('sessions.revoked'))
        : session.live
          ? el('span', { class: 'badge badge-ok' }, t('sessions.live'))
          : el('span', { class: 'badge badge-warn' }, t('sessions.expired'));
      const revokeButton = session.revokedAt ? null : el('button', {
        class: 'btn btn-danger btn-small',
        type: 'button',
        onclick: async () => {
          const sure = await confirmDialog(
            t('confirm.revoke.title'),
            t('confirm.revoke.text', { name: session.deviceName }));
          if (!sure) return;
          try {
            await api('POST', `/sessions/${session.sessionId}/revoke`);
            toast(t('sessions.revoked.toast'));
            renderSessionsPanel(root, couple);
          } catch (err) {
            toast(err.message || t('err.generic'), 'err');
          }
        },
      }, t('sessions.revoke'));
      root.append(el('div', { class: 'session-row' },
        el('div', { class: 'session-main' },
          el('div', { class: 'session-name' },
            `${session.kind === 'adminQr' ? '🔳 ' : ''}${session.deviceName} · ${session.memberName}`),
          el('div', { class: 'session-meta' },
            `${t('member.lastSeen')} ${fmtWhen(session.lastUsedAt)}${session.userAgent ? ` · ${session.userAgent}` : ''}`)),
        el('div', { class: 'session-side' }, status, revokeButton)));
    }
    const buttons = couple.members.map((member) => el('button', {
      class: 'btn btn-small',
      type: 'button',
      onclick: async () => {
        const sure = await confirmDialog(
          t('confirm.revokeAll.title'),
          t('confirm.revokeAll.text', { name: member.name }));
        if (!sure) return;
        try {
          const result = await api('POST', `/couples/${couple.id}/members/${member.id}/sessions/revoke-all`);
          toast(t('sessions.revokedAll.toast', { n: result.revoked }));
          renderSessionsPanel(root, couple);
        } catch (err) {
          toast(err.message || t('err.generic'), 'err');
        }
      },
    }, `🚪 ${t('sessions.revokeAll', { name: member.name })}`));
    root.append(el('div', { class: 'row-actions' }, buttons));
  }

  // --- codes panel --------------------------------------------------------------

  function secretBox(value) {
    return el('div', {},
      el('div', { class: 'secret' },
        el('span', {}, value),
        el('button', { class: 'pill', type: 'button', onclick: () => copyText(value) }, t('codes.copy'))),
      el('div', { class: 'muted', style: 'font-size:12px; margin-top:4px;' }, `⚠️ ${t('codes.once')}`));
  }

  function renderCodesPanel(root, couple) {
    const secrets = state.secrets[couple.id] ?? {};
    root.replaceChildren();

    root.append(el('div', { class: 'slot-block' },
      el('div', { class: 'slot-title' }, `💌 ${t('codes.invite')}`),
      el('div', { class: 'row-actions' },
        el('span', { class: 'chip code' }, couple.code),
        el('button', {
          class: 'btn btn-small',
          type: 'button',
          onclick: async () => {
            const sure = await confirmDialog(
              t('confirm.invite.title'),
              t('confirm.invite.text', { code: couple.code }));
            if (!sure) return;
            try {
              const result = await api('POST', `/couples/${couple.id}/invite-code/reset`);
              (state.secrets[couple.id] ??= {}).invite = result.code;
              await refresh();
              state.openPanel = { coupleId: couple.id, tab: 'codes' };
              renderCouples();
            } catch (err) {
              toast(err.message || t('err.generic'), 'err');
            }
          },
        }, t('codes.invite.new'))),
      secrets.invite ? secretBox(secrets.invite) : null));

    for (const member of couple.members) {
      const recoverySecret = secrets[`${member.id}_recovery`];
      const replaceSecret = secrets[`${member.id}_replace`];
      root.append(el('div', { class: 'slot-block' },
        el('div', { class: 'slot-title' }, `${member.avatar ?? '💞'} ${member.name}`),
        el('div', { class: 'row-actions' },
          el('span', { class: 'chip' },
            `🛟 ${t('codes.recovery')}: ${member.recoveryKeySetAt
              ? t('codes.recovery.set', { when: fmtWhen(member.recoveryKeySetAt) })
              : t('codes.recovery.unset')}`),
          el('button', {
            class: 'btn btn-small',
            type: 'button',
            onclick: async () => {
              const sure = await confirmDialog(
                t('confirm.recovery.title', { name: member.name }),
                t('confirm.recovery.text'));
              if (!sure) return;
              try {
                const result = await api('POST', `/couples/${couple.id}/members/${member.id}/recovery-key/reset`);
                (state.secrets[couple.id] ??= {})[`${member.id}_recovery`] = result.recoveryKey;
                await refresh();
                state.openPanel = { coupleId: couple.id, tab: 'codes' };
                renderCouples();
              } catch (err) {
                toast(err.message || t('err.generic'), 'err');
              }
            },
          }, t('codes.recovery.new'))),
        recoverySecret ? secretBox(recoverySecret) : null,
        el('div', { class: 'row-actions' },
          el('span', { class: 'chip' },
            `🎟 ${t('codes.replace')}: ${member.hasReplaceCode ? t('codes.replace.present') : t('codes.replace.absent')}`),
          el('button', {
            class: 'btn btn-small',
            type: 'button',
            onclick: async () => {
              const sure = await confirmDialog(
                t('confirm.replace.title', { name: member.name }),
                t('confirm.replace.text', { name: member.name }));
              if (!sure) return;
              try {
                const result = await api('POST', `/couples/${couple.id}/members/${member.id}/replace-code/reset`);
                (state.secrets[couple.id] ??= {})[`${member.id}_replace`] = result.replaceCode;
                await refresh();
                state.openPanel = { coupleId: couple.id, tab: 'codes' };
                renderCouples();
              } catch (err) {
                toast(err.message || t('err.generic'), 'err');
              }
            },
          }, t('codes.replace.new'))),
        replaceSecret ? secretBox(replaceSecret) : null));
    }
  }

  // --- QR panel --------------------------------------------------------------------

  function renderQrPanel(root, couple) {
    const current = state.qr[couple.id];
    root.replaceChildren();
    root.append(el('p', { class: 'muted', style: 'margin:0; font-size:13.5px;' }, t('qr.hint')));
    const serverInput = el('input', {
      class: 'input',
      type: 'url',
      value: current?.server ?? window.location.origin,
      'aria-label': t('qr.server'),
    });
    root.append(el('div', { class: 'slot-block' },
      el('span', { class: 'muted', style: 'font-size:12.5px;' }, t('qr.server')),
      serverInput));
    root.append(el('div', { class: 'row-actions' }, couple.members.map((member) => el('button', {
      class: 'btn btn-small btn-accent',
      type: 'button',
      onclick: async (event) => {
        const btn = event.currentTarget;
        btn.disabled = true;
        try {
          const result = await api('POST', `/couples/${couple.id}/members/${member.id}/rejoin-qr`, {
            server: serverInput.value.trim(),
          });
          state.qr[couple.id] = result;
          renderQrPanel(root, couple);
        } catch (err) {
          toast(err.message || t('err.generic'), 'err');
        } finally {
          btn.disabled = false;
        }
      },
    }, `🔳 ${t('qr.generate', { name: member.name })}`))));

    if (current) {
      const svgHost = el('div', { class: 'qr-svg' });
      svgHost.innerHTML = current.svg; // server-rendered, trusted SVG
      const memberName = couple.members.find((m) => m.id === current.memberId)?.name ?? current.memberId;
      root.append(el('div', { class: 'qr-area' },
        el('div', { class: 'slot-title', style: 'text-align:center;' }, `${memberName} 💜`),
        svgHost,
        el('div', { class: 'deeplink' }, current.deepLink),
        el('div', { class: 'row-actions', style: 'justify-content:center;' },
          el('button', { class: 'pill', type: 'button', onclick: () => copyText(current.deepLink) }, t('qr.copy'))),
        el('p', { class: 'muted', style: 'margin:0; font-size:12px; text-align:center;' },
          t('qr.validUntil', { when: fmtClock(current.expiresAt) }))));
    }
  }

  // --- logs & audit ---------------------------------------------------------------

  async function renderLogs() {
    const { lines } = await api('GET', '/logs');
    const card = $('#logs-card');
    const box = el('div', { class: 'log-box' },
      lines.length === 0
        ? t('logs.empty')
        : lines.map((entry) => `${entry.at.slice(11, 19)} ${entry.line}`).join('\n'));
    card.replaceChildren(
      el('div', { class: 'card-head' }, el('h2', {}, `📜 ${t('logs.title')}`)),
      box);
    box.scrollTop = box.scrollHeight;
  }

  async function renderAudit() {
    const { entries } = await api('GET', '/audit');
    const card = $('#audit-card');
    card.replaceChildren(el('div', { class: 'card-head' }, el('h2', {}, `🛡 ${t('audit.title')}`)));
    if (entries.length === 0) {
      card.append(el('div', { class: 'empty' }, t('audit.empty')));
      return;
    }
    const list = el('div', {});
    for (const entry of entries.slice(0, 30)) {
      const what = [
        t(`audit.${entry.action}`) === `audit.${entry.action}` ? entry.action : t(`audit.${entry.action}`),
        entry.coupleId ? `· ${entry.coupleId}` : '',
        entry.memberId ? `· ${entry.memberId}` : '',
        entry.revoked !== undefined ? `(${entry.revoked})` : '',
      ].filter(Boolean).join(' ');
      list.append(el('div', { class: 'audit-row' },
        el('span', { class: 'audit-when' }, fmtWhen(entry.at)),
        el('span', { class: 'audit-what' }, what)));
    }
    card.append(list);
  }

  // --- boot -----------------------------------------------------------------------

  function applyTheme() {
    const stored = localStorage.getItem('sooodreamy-admin-theme');
    const theme = stored ?? (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
    document.documentElement.dataset.theme = theme;
    $('#theme-toggle').textContent = theme === 'dark' ? '🌙' : '☀️';
  }

  $('#theme-toggle').addEventListener('click', () => {
    const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    localStorage.setItem('sooodreamy-admin-theme', next);
    applyTheme();
  });

  $('#lang-toggle').addEventListener('click', () => {
    lang = lang === 'de' ? 'en' : 'de';
    localStorage.setItem('sooodreamy-admin-lang', lang);
    applyStaticI18n();
    if (!$('#dash-view').hidden) refresh().catch(() => {});
  });

  $('#logout-btn').addEventListener('click', async () => {
    try {
      await api('POST', '/logout');
    } catch { /* session may already be gone */ }
    showLogin();
  });

  $('#login-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const errorBox = $('#login-error');
    const submit = $('#login-submit');
    errorBox.hidden = true;
    submit.disabled = true;
    try {
      await api('POST', '/login', { password: $('#login-password').value });
      $('#login-password').value = '';
      showDash();
      await refresh();
    } catch (err) {
      errorBox.textContent = err.status === 429
        ? t('login.err.rate')
        : err.code === 'admin_bad_password' ? t('login.err.bad') : t('login.err.generic');
      errorBox.hidden = false;
    } finally {
      submit.disabled = false;
    }
  });

  applyTheme();
  applyStaticI18n();

  api('GET', '/me')
    .then(async () => {
      showDash();
      await refresh();
    })
    .catch(() => showLogin());
})();

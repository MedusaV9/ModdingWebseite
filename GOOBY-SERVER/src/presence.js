// Presence (Doc C §3.2): Client meldet Status-Strings (kind); der deutsche Anzeige-Text
// wird SERVER-seitig aus goobyName + kind gebaut (Templates per Server-Update änderbar).
// Push FRIEND_PRESENCE an alle Online-Freunde — auch bei online/offline-Wechseln.

import { LIMITS } from './ratelimit.js';
import { friendCodesOf } from './friends.js';

// {gooby} wird durch den Gooby-Spitznamen ersetzt.
const TEMPLATES = {
  online: 'ist online',
  home: 'ist mit {gooby} zuhause',
  park: 'ist gerade mit {gooby} im Park',
  city: 'ist mit {gooby} in der Stadt unterwegs',
  ikea: 'stöbert mit {gooby} im Möbelhaus',
  garden: 'ist mit {gooby} im Garten',
  visit: 'ist mit {gooby} zu Besuch bei einem Freund',
  board: 'spielt eine Runde Schiffe versenken',
  drive: 'fährt mit {gooby} eine Runde',
  vacation: 'ist mit {gooby} im Urlaub',
  sleep: 'schläft — pssst, {gooby} auch',
};

export function buildActivity(kind, goobyName) {
  let label;
  if (TEMPLATES[kind]) {
    label = TEMPLATES[kind];
  } else if (kind.startsWith('minigame:')) {
    label = `spielt gerade „${kind.slice('minigame:'.length)}“`;
  } else {
    label = 'ist mit {gooby} unterwegs';
  }
  return { kind, label: label.replaceAll('{gooby}', goobyName || 'Gooby') };
}

export function broadcastPresence(ctx, conn, online) {
  const payload = {
    friendCode: conn.friendCode,
    online,
    activity: online ? conn.presence || buildActivity('online', conn.goobyName) : null,
  };
  for (const code of friendCodesOf(ctx, conn.friendCode)) {
    const deviceId = ctx.byCode.get(code);
    if (deviceId) ctx.hub.sendToDevice(deviceId, 'FRIEND_PRESENCE', payload);
  }
}

export function register(ctx) {
  const { hub, cfg } = ctx;

  hub.on('PRESENCE_SET', (conn, msg) => {
    const kind = msg.d.kind;
    if (typeof kind !== 'string' || kind.length === 0 || kind.length > cfg.limits.presenceKindLen) {
      hub.sendError(conn, 'BAD_MESSAGE', { re: msg.seq });
      return;
    }
    if (conn.presence && conn.presence.kind === kind) {
      hub.send(conn, 'OK', {}, { re: msg.seq }); // idempotent, kein Broadcast-Spam
      return;
    }
    if (!ctx.buckets.take(`pres:${conn.deviceId}`, LIMITS.presenceSet)) {
      hub.sendError(conn, 'RATE_LIMIT', { re: msg.seq });
      return;
    }
    conn.presence = buildActivity(kind, conn.goobyName);
    hub.send(conn, 'OK', {}, { re: msg.seq });
    broadcastPresence(ctx, conn, true);
  });

  hub.onAuthenticated((conn) => broadcastPresence(ctx, conn, true));
  hub.onDisconnect((conn) => broadcastPresence(ctx, conn, false));
}

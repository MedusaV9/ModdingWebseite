import { httpError, id, nowIso, readJsonObject, sendJson } from './util.js';
import { emitAppEvent } from './events.js';

const LIMITS = Object.freeze({
  calendars: 30,
  doors: 31,
  title: 100,
  emoji: 16,
  payload: 1_000,
});

const CALENDAR_KINDS = ['advent', 'birthday', 'anniversary', 'countdown'];
const PAYLOAD_KINDS = ['prompt', 'quest', 'letter', 'game'];

function calendarsOf(couple) {
  if (!couple.seasonCalendars) couple.seasonCalendars = [];
  return couple.seasonCalendars;
}

function partnerOf(couple, memberId) {
  return couple.members.find((member) => member.id !== memberId) ?? null;
}

function requireCalendar(couple, calendarId) {
  const calendar = calendarsOf(couple).find((candidate) => candidate.id === calendarId);
  if (!calendar) throw httpError(404, 'not_found', 'Unknown season calendar');
  return calendar;
}

function requireDoor(calendar, doorId) {
  const door = calendar.doors.find((candidate) => candidate.id === doorId);
  if (!door) throw httpError(404, 'not_found', 'Unknown calendar door');
  return door;
}

function asTimestamp(value, field) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) {
    throw httpError(400, 'bad_date', `"${field}" must be an ISO-8601 timestamp`);
  }
  return new Date(value).toISOString();
}

function calendarView(calendar, viewerId) {
  const author = calendar.createdBy === viewerId;
  const now = Date.now();
  return {
    ...calendar,
    doors: calendar.doors.map((door) => {
      const unlocked = Date.parse(door.unlockAt) <= now;
      const revealed = author || door.openedAt != null;
      return {
        id: door.id,
        number: door.number,
        unlockAt: door.unlockAt,
        openedAt: door.openedAt,
        unlocked,
        payload: revealed ? door.payload : null,
      };
    }),
  };
}

function broadcastCalendar(c, calendar, deleted = false) {
  for (const member of c.auth.couple.members) {
    c.realtime.sendToMember(c.auth.coupleId, member.id, 'season_calendar_changed', {
      calendar: deleted ? null : calendarView(calendar, member.id),
      calendarId: calendar.id,
      deleted,
    });
  }
}

export function registerSeasonalRoutes(route, { asString, asEnum }) {
  route('GET', '/api/season-calendars', { auth: true }, (c) => {
    const calendars = calendarsOf(c.auth.couple)
      .slice()
      .reverse()
      .map((calendar) => calendarView(calendar, c.auth.memberId));
    sendJson(c.res, 200, { calendars });
  });

  route('GET', '/api/season-calendars/:id', { auth: true }, (c) => {
    const calendar = requireCalendar(c.auth.couple, c.params.id);
    sendJson(c.res, 200, { calendar: calendarView(calendar, c.auth.memberId) });
  });

  route('POST', '/api/season-calendars', { auth: true }, async (c) => {
    const partner = partnerOf(c.auth.couple, c.auth.memberId);
    if (!partner) throw httpError(409, 'no_partner', 'A calendar needs a recipient');
    const body = await readJsonObject(c.req);
    const title = asString(body.title, 'title', { max: LIMITS.title });
    const kind = asEnum(body.kind ?? 'countdown', 'kind', CALENDAR_KINDS);
    const emoji = body.emoji == null ? null : asString(body.emoji, 'emoji', { max: LIMITS.emoji });
    if (!Array.isArray(body.doors) || body.doors.length < 1 || body.doors.length > LIMITS.doors) {
      throw httpError(400, 'bad_doors', `"doors" must contain 1 to ${LIMITS.doors} items`);
    }
    const doors = body.doors.map((raw, index) => {
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
        throw httpError(400, 'bad_door', `door ${index + 1} must be an object`);
      }
      const payload = raw.payload;
      if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
        throw httpError(400, 'bad_payload', `door ${index + 1} needs a payload`);
      }
      return {
        id: id('door'),
        number: index + 1,
        unlockAt: asTimestamp(raw.unlockAt, `doors[${index}].unlockAt`),
        payload: {
          kind: asEnum(payload.kind, 'payload.kind', PAYLOAD_KINDS),
          text: asString(payload.text, 'payload.text', { max: LIMITS.payload }),
        },
        openedAt: null,
      };
    });
    doors.sort((a, b) => a.unlockAt.localeCompare(b.unlockAt));
    doors.forEach((door, index) => { door.number = index + 1; });

    const calendar = {
      id: id('calendar'),
      title,
      emoji,
      kind,
      createdBy: c.auth.memberId,
      recipientId: partner.id,
      createdAt: nowIso(),
      doors,
    };
    const calendars = calendarsOf(c.auth.couple);
    calendars.push(calendar);
    if (calendars.length > LIMITS.calendars) {
      const removable = calendars.findIndex((item) => item.doors.every((door) => door.openedAt == null));
      calendars.splice(removable === -1 ? 0 : removable, 1);
    }
    c.store.markDirty();
    emitAppEvent({
      store: c.store,
      realtime: c.realtime,
      couple: c.auth.couple,
      type: 'season_calendar_created',
      memberId: c.auth.memberId,
      data: { calendarId: calendar.id, kind, doorCount: doors.length },
      dedupeKey: calendar.id,
    });
    broadcastCalendar(c, calendar);
    sendJson(c.res, 201, { calendar: calendarView(calendar, c.auth.memberId) });
  });

  route('PATCH', '/api/season-calendars/:id', { auth: true }, async (c) => {
    const calendar = requireCalendar(c.auth.couple, c.params.id);
    if (calendar.createdBy !== c.auth.memberId) {
      throw httpError(403, 'not_yours', 'Only the author can edit this calendar');
    }
    const body = await readJsonObject(c.req);
    if (body.title !== undefined) calendar.title = asString(body.title, 'title', { max: LIMITS.title });
    if (body.emoji !== undefined) {
      calendar.emoji = body.emoji == null ? null : asString(body.emoji, 'emoji', { max: LIMITS.emoji });
    }
    c.store.markDirty();
    broadcastCalendar(c, calendar);
    sendJson(c.res, 200, { calendar: calendarView(calendar, c.auth.memberId) });
  });

  route('POST', '/api/season-calendars/:id/open', { auth: true }, async (c) => {
    const calendar = requireCalendar(c.auth.couple, c.params.id);
    if (calendar.recipientId !== c.auth.memberId) {
      throw httpError(403, 'not_for_you', 'Only the recipient can open this door');
    }
    const body = await readJsonObject(c.req);
    const doorId = asString(body.doorId, 'doorId', { max: 100 });
    const door = requireDoor(calendar, doorId);
    if (Date.parse(door.unlockAt) > Date.now()) {
      throw httpError(409, 'door_still_locked', 'This door is still locked');
    }
    if (!door.openedAt) {
      door.openedAt = nowIso();
      c.store.markDirty();
      emitAppEvent({
        store: c.store,
        realtime: c.realtime,
        couple: c.auth.couple,
        type: 'season_calendar_door_opened',
        memberId: c.auth.memberId,
        data: { calendarId: calendar.id, doorId: door.id, kind: door.payload.kind },
        dedupeKey: door.id,
      });
      broadcastCalendar(c, calendar);
    }
    sendJson(c.res, 200, { calendar: calendarView(calendar, c.auth.memberId), doorId: door.id });
  });

  route('DELETE', '/api/season-calendars/:id', { auth: true }, (c) => {
    const calendars = calendarsOf(c.auth.couple);
    const index = calendars.findIndex((candidate) => candidate.id === c.params.id);
    if (index === -1) throw httpError(404, 'not_found', 'Unknown season calendar');
    const calendar = calendars[index];
    if (calendar.createdBy !== c.auth.memberId) {
      throw httpError(403, 'not_yours', 'Only the author can delete this calendar');
    }
    if (calendar.doors.some((door) => door.openedAt != null)) {
      throw httpError(409, 'already_opened', 'Opened calendars stay in the shared archive');
    }
    calendars.splice(index, 1);
    c.store.markDirty();
    broadcastCalendar(c, calendar, true);
    sendJson(c.res, 200, { ok: true });
  });
}

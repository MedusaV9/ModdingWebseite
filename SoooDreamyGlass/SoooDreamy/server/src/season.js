function monthKey(value) {
  return String(value ?? '').slice(0, 7);
}

function normalizeWordleDay(day) {
  if (!day) return {};
  if (Object.keys(day).every((key) => key === 'de' || key === 'en')) return day;
  const normalized = {};
  for (const result of Object.values(day)) {
    const lang = result?.lang === 'de' ? 'de' : 'en';
    (normalized[lang] ??= {})[result.memberId] = result;
  }
  return normalized;
}

function scoreWordle(result) {
  if (!result?.win) return 0;
  return Math.max(1, 7 - Number(result.rows ?? 6));
}

/**
 * One canonical, client-independent season ledger. Finished co-op games count
 * as shared 1:1 results; competitive games preserve their server scores.
 * Wordle contributes one match per language/day once both partners finished.
 */
export function aggregateSeason(couple, requestedMonth = null) {
  const memberIds = couple.members.map((member) => member.id);
  const matches = [];
  for (const game of couple.games ?? []) {
    if (game.state !== 'ended' || game.result?.cancelled) continue;
    const month = monthKey(game.createdAt);
    if (requestedMonth && month !== requestedMonth) continue;
    const storedScores = game.result?.scores;
    const scores = Object.fromEntries(memberIds.map((memberId) => [
      memberId,
      Number.isFinite(Number(storedScores?.[memberId]))
        ? Number(storedScores[memberId])
        : 1,
    ]));
    matches.push({
      id: game.id,
      type: game.type,
      monthKey: month,
      createdAt: game.createdAt,
      scores,
      source: 'game',
    });
  }

  for (const [dateKey, rawDay] of Object.entries(couple.wordle ?? {})) {
    const month = monthKey(dateKey);
    if (requestedMonth && month !== requestedMonth) continue;
    const day = normalizeWordleDay(rawDay);
    for (const lang of ['de', 'en']) {
      const byMember = day[lang] ?? {};
      if (memberIds.length !== 2 || !memberIds.every((id) => byMember[id])) continue;
      matches.push({
        id: `wordle-${dateKey}-${lang}`,
        type: `wordle-${lang}`,
        monthKey: month,
        createdAt: `${dateKey}T12:00:00.000Z`,
        scores: Object.fromEntries(memberIds.map((id) => [id, scoreWordle(byMember[id])])),
        source: 'wordle',
      });
    }
  }

  matches.sort((left, right) =>
    left.createdAt === right.createdAt
      ? left.id.localeCompare(right.id)
      : left.createdAt.localeCompare(right.createdAt));
  const months = [...new Set(matches.map((match) => match.monthKey))].sort().reverse();
  return {
    month: requestedMonth,
    matches,
    months,
    total: matches.length,
  };
}

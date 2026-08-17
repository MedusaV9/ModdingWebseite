export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Entity-id shapes the server mints (`util.js id()`), plus arena device ids. */
export const ID_RE = /^(?:[a-z]{1,4}_(?:[a-z]{1,4}_)?[0-9a-f]{16}|arena-c\d+-m\d+-d\d+)$/;

/** Couple markers embedded in every arena-generated text: ⟦A<coupleIdx>⟧. */
export const MARKER_RE = /⟦A(\d+)⟧/g;

export function marker(coupleIdx) {
  return `⟦A${coupleIdx}⟧`;
}

/** Recursively collects every string value inside a JSON-ish structure. */
export function collectStrings(value, out = [], depth = 0) {
  if (depth > 12 || value == null) return out;
  if (typeof value === 'string') {
    out.push(value);
  } else if (Array.isArray(value)) {
    for (const item of value) collectStrings(item, out, depth + 1);
  } else if (typeof value === 'object') {
    for (const item of Object.values(value)) collectStrings(item, out, depth + 1);
  }
  return out;
}

/** Order-insensitive-for-objects deep equality (arrays stay ordered). */
export function deepEqual(a, b) {
  if (a === b) return true;
  if (typeof a !== typeof b) return false;
  if (a == null || b == null) return false;
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false;
    return a.every((item, i) => deepEqual(item, b[i]));
  }
  if (typeof a === 'object') {
    const keysA = Object.keys(a).sort();
    const keysB = Object.keys(b).sort();
    if (keysA.length !== keysB.length) return false;
    return keysA.every((key, i) => key === keysB[i] && deepEqual(a[key], b[key]));
  }
  return false;
}

/** First differing path between two structures — for readable diff reports. */
export function firstDiff(a, b, path = '$') {
  if (a === b) return null;
  if (a == null || b == null || typeof a !== typeof b || typeof a !== 'object') {
    return { path, before: a, after: b };
  }
  if (Array.isArray(a) !== Array.isArray(b)) return { path, before: a, after: b };
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const key of keys) {
    const hit = firstDiff(a[key], b[key], `${path}.${key}`);
    if (hit) return hit;
  }
  return null;
}

/** Compact JSON for report lines (truncated). */
export function brief(value, max = 300) {
  let text;
  try {
    text = JSON.stringify(value);
  } catch {
    text = String(value);
  }
  if (text && text.length > max) text = `${text.slice(0, max)}…`;
  return text;
}

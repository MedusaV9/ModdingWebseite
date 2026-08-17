// V6/D4 (PLAN6 Wave D) — rendered-emoji audit gate. Fails (exit 1) on raw
// emoji/pictograph codepoints inside STRING LITERALS (and template strings)
// of src/**/*.js, plus anywhere in src/ui/styles.css outside comments
// (`content:` rules are the only way CSS text renders — scanning the whole
// sheet sans comments over-approximates safely). Comments never count: the
// scanner is a small JS tokenizer, not a blind codepoint purge, so DE prose,
// arrows and glyph talk in comments stay legal.
//
// Detection ranges reuse + extend the RAW_GLYPH_RE work from src/ui/icons.js
// (Misc Symbols, Dingbats, Emoticons/Transport/Supplemental via the 1F000
// plane, Misc Technical watch/hourglass/media, arrows, variation selectors)
// and add the Geometric Shapes block so text-presentation pictographs used
// as UI iconography (▶ ◀ ▲ ● ◆ ■ …) are gated too.
//
// Classification (what counts as "reaching rendering"):
//   - JS/CSS comments never count (tokenized away), including CSS comments
//     embedded inside injected `…CSS…` template literals.
//   - String hits on `console.*(…)` / `throw new Error(…)` lines are
//     DEV-diagnostic output (terminal/devtools), not game UI — excluded by
//     classification (e.g. the `a → b` arrows in [audio]/[medley] debug logs).
//   - Everything else in a string literal is treated as rendered and must be
//     authored art (src/ui/icons.js, src/ui/foodIcons.js) unless allowlisted.
//
// Allowlist (exhaustive — justify every addition):
//   1. `notify.*` title/body string VALUES in src/data/strings*.js modules —
//      OS notification copy renders on the OS surface where SVG is
//      impossible; emoji are the sanctioned iconography there (PLAN6 D4
//      acceptance names bodies; titles share the exact same OS surface, so
//      the same justification applies — see D2's v6-vacation-content titles).
//   2. `bubblePop.logic.js` BUBBLE_STYLES `symbol:` glyphs — deliberate
//      color-blind a11y device (color is redundant with a high-contrast
//      shape); documented sanctioned site, idea 10 Tier 3.
// No external allowlist file is needed today; add entries to ALLOW_SITES
// below with a justification comment if a new sanctioned surface appears.
//
// Usage: npm run emoji-audit         (CLI — prints file:line:codepoint)
//        import { runEmojiAudit }    (test/emojiAudit.test.js runs in-process)

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// ── detection ────────────────────────────────────────────────────────────────
// Codepoints written as escapes on purpose: this file must pass its own gate.
/* eslint-disable no-misleading-character-class -- matching LONE variation
   selectors / ZWJ is intentional (same ruling as icons.js RAW_GLYPH_RE):
   a stray sequence fragment in a rendered string is itself a violation. */
const EMOJI_RANGES =
  '\u{1F000}-\u{1FAFF}' + // Mahjong…Symbols & Pictographs Ext-A (emoticons, transport, supplemental)
  '\u{2600}-\u{27BF}' + //   Misc Symbols + Dingbats (\u2615 \u26F3 \u2728 \u2764 …)
  '\u{2B00}-\u{2BFF}' + //   Misc Symbols and Arrows (\u2B50 …)
  '\u{2190}-\u{21FF}' + //   Arrows (\u2192 …)
  '\u{25A0}-\u{25FF}' + //   Geometric Shapes (\u25B6 \u25CF … — text-presentation pictographs)
  '\u{231A}\u{231B}' + //    watch + hourglass
  '\u{23CF}\u{23E9}-\u{23FA}' + // eject + media/clock (Misc Technical)
  '\u{20E3}' + //            combining enclosing keycap
  '\u{FE0E}\u{FE0F}' + //    variation selectors
  '\u{200D}'; //             zero-width joiner
const EMOJI_RE = new RegExp(`[${EMOJI_RANGES}]`, 'gu');
/* eslint-enable no-misleading-character-class */

// ── allowlist ────────────────────────────────────────────────────────────────
/**
 * Sanctioned sites. A hit is allowed when its file matches `file` (relative,
 * forward slashes) and the full source LINE it sits on matches `lineRe`.
 * @type {Array<{file: RegExp, lineRe: RegExp, why: string}>}
 */
const ALLOW_SITES = [
  {
    // OS notification copy (strings modules only): emoji are the only
    // iconography the OS surface supports — explicitly exempt per PLAN6 D4.
    file: /^src\/data\/strings(\.js|\/[\w-]+\.js)$/,
    lineRe: /['"]notify\.[\w.]+\.(?:body|title)['"]\s*:/,
    why: 'OS notification copy (no SVG possible on the OS surface)',
  },
  {
    // bubblePop color-blind bubble symbols: deliberate a11y shape coding.
    file: /^src\/minigames\/games\/bubblePop\.logic\.js$/,
    lineRe: /symbol:\s*'[\u25B2\u25CF\u25C6\u2605]'/u,
    why: 'color-blind a11y shape glyph (BUBBLE_STYLES)',
  },
];

/**
 * @param {string} rel repo-relative path (forward slashes)
 * @param {string} lineText full source line
 * @returns {boolean} true when the hit is a sanctioned exemption
 */
function isAllowed(rel, lineText) {
  return ALLOW_SITES.some((s) => s.file.test(rel) && s.lineRe.test(lineText));
}

/**
 * DEV-diagnostic line: console output / thrown error messages never reach
 * the game UI (see the classification notes in the header).
 * @param {string} lineText full source line
 * @returns {boolean}
 */
function isDiagnostic(lineText) {
  return /(?:^|[^\w.])console\.(?:debug|info|log|warn|error|trace)\s*\(|throw new (?:Error|TypeError|RangeError)\s*\(/.test(lineText);
}

// ── JS tokenizer (comment/string/code classification) ────────────────────────
/**
 * Walk JS source and yield every string-literal / template-string span plus
 * non-comment code spans. Comments are dropped. Template interpolations
 * `${…}` are re-classified as code (nested templates handled via a stack).
 * Regex literals are detected with the standard prev-token heuristic and
 * classified as code so their quote/slash characters cannot derail the state
 * machine.
 * @param {string} src
 * @returns {Array<{kind: 'string'|'code', text: string, line: number}>}
 *   line = 1-based line of the span START.
 */
export function tokenizeJs(src) {
  const spans = [];
  let i = 0;
  let line = 1;
  let state = 'code';
  let spanStart = 0;
  let spanLine = 1;
  /** template nesting: each entry is the interpolation brace depth */
  const tplStack = [];
  /** last significant char before a `/` (regex-vs-divide heuristic) */
  let prevSig = '';

  const push = (kind, end) => {
    if (end > spanStart) spans.push({ kind, text: src.slice(spanStart, end), line: spanLine });
    spanStart = end;
  };
  const bumpLines = (text) => {
    for (let k = 0; k < text.length; k += 1) if (text[k] === '\n') line += 1;
  };

  while (i < src.length) {
    const c = src[i];
    const c2 = src[i + 1];
    if (state === 'code') {
      if (c === '/' && c2 === '/') {
        push('code', i);
        const nl = src.indexOf('\n', i);
        const end = nl === -1 ? src.length : nl;
        i = end;
        spanStart = i;
        spanLine = line;
        continue;
      }
      if (c === '/' && c2 === '*') {
        push('code', i);
        const close = src.indexOf('*/', i + 2);
        const end = close === -1 ? src.length : close + 2;
        bumpLines(src.slice(i, end));
        i = end;
        spanStart = i;
        spanLine = line;
        continue;
      }
      if (c === '/' && /(^|[(,=:[!&|?{};+\-*%<>~^]|return|typeof|case|in|of|new|do|else|void|yield|await|delete|instanceof)$/.test(prevSig)) {
        // regex literal — consume it as code (escapes + char classes)
        let j = i + 1;
        let inClass = false;
        while (j < src.length) {
          const r = src[j];
          if (r === '\\') j += 2;
          else if (r === '[') { inClass = true; j += 1; }
          else if (r === ']') { inClass = false; j += 1; }
          else if (r === '/' && !inClass) { j += 1; break; }
          else if (r === '\n') break; // unterminated — bail, stay safe
          else j += 1;
        }
        bumpLines(src.slice(i, j));
        i = j;
        prevSig = '/';
        continue;
      }
      if (c === "'" || c === '"') {
        push('code', i);
        state = c === "'" ? 'sq' : 'dq';
        spanStart = i + 1;
        spanLine = line;
        i += 1;
        continue;
      }
      if (c === '`') {
        push('code', i);
        tplStack.push(0);
        state = 'tpl';
        spanStart = i + 1;
        spanLine = line;
        i += 1;
        continue;
      }
      if (c === '}' && tplStack.length > 0) {
        if (tplStack[tplStack.length - 1] === 0) {
          // close of a ${…} interpolation — back into the template string
          push('code', i);
          state = 'tpl';
          spanStart = i + 1;
          spanLine = line;
          i += 1;
          continue;
        }
        tplStack[tplStack.length - 1] -= 1;
      } else if (c === '{' && tplStack.length > 0) {
        tplStack[tplStack.length - 1] += 1;
      }
      if (c === '\n') line += 1;
      if (!/\s/.test(c)) {
        // track a small trailing window so keyword regex contexts match
        prevSig = /[A-Za-z$_]/.test(c) ? (prevSig + c).slice(-10) : c;
      }
      i += 1;
      continue;
    }
    if (state === 'sq' || state === 'dq') {
      const quote = state === 'sq' ? "'" : '"';
      if (c === '\\') { i += 2; continue; }
      if (c === quote) {
        push('string', i);
        state = 'code';
        spanStart = i + 1;
        spanLine = line;
        prevSig = quote;
        i += 1;
        continue;
      }
      if (c === '\n') line += 1; // invalid JS, but keep line numbers sane
      i += 1;
      continue;
    }
    // state === 'tpl'
    if (c === '\\') { i += 2; continue; }
    if (c === '`') {
      push('string', i);
      tplStack.pop();
      state = 'code';
      spanStart = i + 1;
      spanLine = line;
      prevSig = '`';
      i += 1;
      continue;
    }
    if (c === '$' && c2 === '{') {
      push('string', i);
      state = 'code';
      spanStart = i + 2;
      spanLine = line;
      prevSig = '{';
      i += 2;
      continue;
    }
    if (c === '\n') line += 1;
    i += 1;
  }
  push(state === 'code' ? 'code' : 'string', src.length);
  return spans;
}

/** Strip CSS comments, preserving newlines so line numbers survive. */
function stripCssComments(css) {
  return css.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
}

// ── audit core ───────────────────────────────────────────────────────────────
/**
 * @param {string} rel repo-relative file path
 * @param {string} text scannable text (comments already removed/blanked)
 * @param {number} startLine 1-based line the text starts on
 * @param {string[]} sourceLines full original file split into lines
 * @param {Array} out violations sink
 */
function scanText(rel, text, startLine, sourceLines, out) {
  let lineOffset = 0;
  let lastIndex = 0;
  EMOJI_RE.lastIndex = 0;
  for (const m of text.matchAll(EMOJI_RE)) {
    for (let k = lastIndex; k < m.index; k += 1) if (text[k] === '\n') lineOffset += 1;
    lastIndex = m.index;
    const lineNo = startLine + lineOffset;
    const lineText = sourceLines[lineNo - 1] ?? '';
    if (isAllowed(rel, lineText) || isDiagnostic(lineText)) continue;
    const cp = m[0].codePointAt(0);
    out.push({
      file: rel,
      line: lineNo,
      codepoint: `U+${cp.toString(16).toUpperCase().padStart(4, '0')}`,
      glyph: m[0],
      context: lineText.trim().slice(0, 90),
    });
  }
}

/** @returns {string[]} repo-relative paths of every js file under src/ */
function walkJsFiles(dir, out = []) {
  for (const name of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, name.name);
    if (name.isDirectory()) walkJsFiles(full, out);
    else if (name.name.endsWith('.js')) out.push(path.relative(ROOT, full).replaceAll('\\', '/'));
  }
  return out;
}

/**
 * Run the audit over src/**\/*.js + src/ui/styles.css.
 * @returns {Array<{file: string, line: number, codepoint: string, glyph: string, context: string}>}
 */
export function runEmojiAudit() {
  const violations = [];
  for (const rel of walkJsFiles(path.join(ROOT, 'src')).sort()) {
    const src = fs.readFileSync(path.join(ROOT, rel), 'utf8');
    if (!EMOJI_RE.test(src)) { EMOJI_RE.lastIndex = 0; continue; }
    EMOJI_RE.lastIndex = 0;
    const sourceLines = src.split('\n');
    for (const span of tokenizeJs(src)) {
      // Injected-CSS template literals carry CSS comments of their own —
      // blank them (they never render) before scanning the string content.
      const text = span.kind === 'string' && span.text.includes('/*')
        ? stripCssComments(span.text)
        : span.text;
      scanText(rel, text, span.line, sourceLines, violations);
    }
  }
  const cssRel = 'src/ui/styles.css';
  const css = fs.readFileSync(path.join(ROOT, cssRel), 'utf8');
  scanText(cssRel, stripCssComments(css), 1, css.split('\n'), violations);
  violations.sort((a, b) => (a.file === b.file ? a.line - b.line : a.file < b.file ? -1 : 1));
  return violations;
}

// ── thin CLI ─────────────────────────────────────────────────────────────────
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const violations = runEmojiAudit();
  for (const v of violations) {
    console.error(`emoji-audit: ${v.file}:${v.line}: ${v.codepoint} ${v.glyph}  ${v.context}`);
  }
  if (violations.length > 0) {
    console.error(`emoji-audit: FAILED — ${violations.length} rendered raw glyph(s); use authored icons (src/ui/icons.js, src/ui/foodIcons.js) or extend ALLOW_SITES with justification`);
    process.exit(1);
  }
  console.log('emoji-audit: OK — no rendered raw emoji outside sanctioned sites');
}

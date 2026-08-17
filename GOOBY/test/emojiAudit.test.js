// V6/D4 (PLAN6 Wave D) — the permanent zero-raw-emoji gate. Runs the
// scripts/emoji-audit.mjs core IN-PROCESS (the CLI stays a thin wrapper) and
// asserts the whole src/ tree renders ZERO raw emoji/pictograph glyphs
// outside the two sanctioned surfaces (OS notification copy, bubblePop's
// color-blind a11y shapes). Later waves (E/F) are policed automatically:
// any new rendered glyph fails this test with a file:line:codepoint report.
//
// Also pins the tokenizer's classification behavior (comments/diagnostics
// never count; strings do) so the gate cannot silently rot into a blind
// codepoint purge — risk row 3 of PLAN6.

import test from 'node:test';
import assert from 'node:assert/strict';
import { runEmojiAudit, tokenizeJs } from '../scripts/emoji-audit.mjs';

test('V6/D4: src/ renders zero raw emoji outside sanctioned sites', () => {
  const violations = runEmojiAudit();
  const report = violations
    .map((v) => `${v.file}:${v.line}: ${v.codepoint} ${v.glyph}  ${v.context}`)
    .join('\n');
  assert.equal(violations.length, 0, `rendered raw glyph(s) found:\n${report}`);
});

test('V6/D4: tokenizer classifies comments vs strings vs code', () => {
  const src = [
    "// line comment with a glyph \u{1F955} stays a comment",
    "/* block \u2192 comment */ const a = 'string one';",
    'const b = `template ${a} tail`;',
    "const re = /['\"]/g; // regex quotes must not open a string",
    "const c = 'after regex';",
  ].join('\n');
  const spans = tokenizeJs(src);
  const strings = spans.filter((s) => s.kind === 'string').map((s) => s.text);
  assert.deepEqual(strings, ['string one', 'template ', ' tail', 'after regex']);
  const code = spans.filter((s) => s.kind === 'code').map((s) => s.text).join('');
  assert.ok(!code.includes('\u{1F955}'), 'line comment content leaked into code');
  assert.ok(!code.includes('\u2192'), 'block comment content leaked into code');
});

test('V6/D4: template-string glyphs are caught with correct line numbers', () => {
  const src = "const x = 1;\nconst y = `chip \u2605 ${x}`;\n";
  const spans = tokenizeJs(src);
  const hit = spans.find((s) => s.kind === 'string' && s.text.includes('\u2605'));
  assert.ok(hit, 'template string span not found');
  assert.equal(hit.line, 2);
});

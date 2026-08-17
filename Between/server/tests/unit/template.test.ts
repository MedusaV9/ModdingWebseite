import { test } from 'node:test'
import assert from 'node:assert/strict'
import { renderTemplate } from '../../src/lib/template.ts'

const VARS = { server: 'Lobby One', state: 'running', players: '3', user: 'Steve' }

test('renderTemplate substitutes known placeholders', () => {
  assert.equal(renderTemplate('say Welcome {user} to {server}!', VARS), 'say Welcome Steve to Lobby One!')
  assert.equal(
    renderTemplate('The server state is {state} and {players} users are connected', VARS),
    'The server state is running and 3 users are connected',
  )
})

test('renderTemplate leaves unknown placeholders verbatim', () => {
  assert.equal(renderTemplate('say {nope} and {server}', VARS), 'say {nope} and Lobby One')
  assert.equal(renderTemplate('{completely.unknown}', VARS), '{completely.unknown}')
})

test('renderTemplate escaping: {{ renders a literal {', () => {
  assert.equal(renderTemplate('json {{ "a": 1 }', VARS), 'json { "a": 1 }')
  // Escaped opening brace disarms the placeholder that follows.
  assert.equal(renderTemplate('{{user}', VARS), '{user}')
  // Escape + real placeholder + literal close: {{{user}} → "{Steve}".
  assert.equal(renderTemplate('{{{user}}', VARS), '{Steve}')
})

test('renderTemplate tolerates malformed braces without crashing', () => {
  assert.equal(renderTemplate('lonely { brace', VARS), 'lonely { brace')
  assert.equal(renderTemplate('unclosed {server', VARS), 'unclosed {server')
  assert.equal(renderTemplate('empty {} braces', VARS), 'empty {} braces')
  assert.equal(renderTemplate('', VARS), '')
})

test('renderTemplate is single-pass: substituted values are never re-expanded', () => {
  // A player named "{state}" must come out literally, not as "running".
  const out = renderTemplate('kick {user}', { ...VARS, user: '{state}' })
  assert.equal(out, 'kick {state}')
  // …even when the value key itself exists.
  assert.equal(renderTemplate('{a}', { a: '{a}' }), '{a}')
})

test('renderTemplate cannot be polluted through prototype key names', () => {
  assert.equal(renderTemplate('{__proto__} {constructor} {hasOwnProperty}', VARS), '{__proto__} {constructor} {hasOwnProperty}')
  // Even with Object.prototype temporarily carrying a matching key, only own
  // properties resolve.
  assert.equal(renderTemplate('{toString}', VARS), '{toString}')
})

test('renderTemplate inserts values literally (no regex replacement patterns, no string escape)', () => {
  // $& / $1 / $' are String.replace specials — must come through untouched.
  assert.equal(renderTemplate('say {user}', { user: '$& $1 $\' $`' }), "say $& $1 $' $`")
  // Quotes/backslashes stay verbatim: the output is one opaque console line,
  // there is no surrounding string context to break out of (and no shell).
  assert.equal(renderTemplate('say {user}', { user: '"; rm -rf / #\\' }), 'say "; rm -rf / #\\')
})

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { applyToml, parseToml } from '../../src/lib/toml.ts'

const VELOCITY_STYLE = `# Velocity-style proxy config
config-version = "2.7"
bind = "0.0.0.0:25577"
motd = "A Velocity Server"  # shown in the server list
show-max-players = 500
online-mode = true

[servers]
lobby = "127.0.0.1:30066"
factions = "127.0.0.1:30067"

[advanced]
compression-threshold = 256   # bytes
login-ratelimit = 3000
`

test('applyToml updates an existing top-level key in place', () => {
  const next = applyToml(VELOCITY_STYLE, { motd: 'Hello' })
  assert.match(next, /motd = "Hello"  # shown in the server list\n/)
  // untouched neighbours, comments included
  assert.match(next, /# Velocity-style proxy config/)
  assert.match(next, /show-max-players = 500\n/)
})

test('applyToml updates keys inside tables via dot-paths', () => {
  const next = applyToml(VELOCITY_STYLE, { 'advanced.compression-threshold': '512', 'servers.lobby': '127.0.0.1:31000' })
  assert.match(next, /compression-threshold = 512   # bytes\n/)
  assert.match(next, /lobby = "127\.0\.0\.1:31000"\n/)
  assert.match(next, /factions = "127\.0\.0\.1:30067"\n/)
})

test('applyToml inserts missing keys into an existing table without duplicating headers', () => {
  const next = applyToml(VELOCITY_STYLE, { 'servers.try': 'lobby' })
  assert.equal(next.match(/\[servers\]/g)?.length, 1)
  const serversAt = next.indexOf('[servers]')
  const advancedAt = next.indexOf('[advanced]')
  const keyAt = next.indexOf('try = "lobby"')
  assert.ok(keyAt > serversAt && keyAt < advancedAt, 'new key lives inside [servers]')
})

test('applyToml appends genuinely new tables at the end', () => {
  const next = applyToml(VELOCITY_STYLE, { 'query.port': '25577' })
  assert.match(next, /\[query\]\nport = 25577$/)
})

test('applyToml treats the last dot segment as the key and the rest as the table', () => {
  const next = applyToml('', { 'a.b.c': 'x' })
  assert.equal(next, '\n[a.b]\nc = "x"')
  const updated = applyToml(next, { 'a.b.c': 'y' })
  assert.match(updated, /\[a\.b\]\nc = "y"/)
})

test('applyToml quotes strings and leaves numbers/booleans bare', () => {
  const next = applyToml('', { s: 'hello world', n: '42', f: '1.5', b: 'true', q: 'say "hi"', ver: '1.2.3' })
  assert.match(next, /s = "hello world"/)
  assert.match(next, /n = 42/)
  assert.match(next, /f = 1\.5/)
  assert.match(next, /b = true/)
  assert.match(next, /q = "say \\"hi\\""/)
  assert.match(next, /ver = "1\.2\.3"/)
})

test('applyToml never edits inside arrays of tables', () => {
  const doc = '[[metrics]]\nenabled = true\n'
  const next = applyToml(doc, { enabled: 'false' })
  assert.match(next, /\[\[metrics\]\]\nenabled = true/)
  // the top-level key is added at the top instead
  assert.match(next, /^enabled = false\n/)
})

test('applyToml never throws on malformed input', () => {
  assert.doesNotThrow(() => applyToml('[unclosed\n= = =\n"\n', { 'a.b': '1' }))
})

test('applyToml quotes leading-zero and lossy numbers so they survive a round-trip', () => {
  // Bare "08" is invalid TOML (leading zeros are illegal) and "3.0"/"1.10"
  // would read back as 3/1.1 — keep such values as strings instead.
  const next = applyToml('', { a: '08', b: '007', c: '3.0', d: '1.10', e: '00' })
  assert.match(next, /a = "08"/)
  assert.match(next, /b = "007"/)
  assert.match(next, /c = "3.0"/)
  assert.match(next, /d = "1.10"/)
  assert.match(next, /e = "00"/)
  const parsed = parseToml(next)
  assert.equal(parsed.a, '08')
  assert.equal(parsed.c, '3.0')
  // canonical numbers still land bare
  assert.match(applyToml('', { n: '42', f: '3.14', z: '0' }), /n = 42\nf = 3\.14\nz = 0/)
})

test('parseToml never pollutes Object.prototype via table names or dotted keys', () => {
  for (const doc of [
    '[__proto__]\npolluted = "bad"\n',
    '__proto__.polluted = "bad"\n',
    '[a.__proto__]\npolluted = "bad"\n',
    'a.constructor.prototype.polluted = "bad"\n',
  ]) {
    parseToml(doc)
    assert.equal(({} as Record<string, unknown>).polluted, undefined, `polluted via ${JSON.stringify(doc)}`)
    assert.equal(Object.prototype.hasOwnProperty('polluted'), false)
  }
})

test('parseToml parses a realistic document into a nested object', () => {
  const parsed = parseToml(VELOCITY_STYLE)
  assert.equal(parsed['config-version'], '2.7')
  assert.equal(parsed['show-max-players'], 500)
  assert.equal(parsed['online-mode'], true)
  assert.equal(parsed['motd'], 'A Velocity Server')
  assert.deepEqual(parsed.servers, { lobby: '127.0.0.1:30066', factions: '127.0.0.1:30067' })
  assert.equal((parsed.advanced as Record<string, unknown>)['compression-threshold'], 256)
})

test('parseToml handles literal strings, escapes, arrays and dotted keys', () => {
  const parsed = parseToml('lit = \'C:\\path\'\nesc = "a\\nb"\narr = [1, 2, 3]\nstrs = ["a", "b"]\nnested.key = 5\n')
  assert.equal(parsed.lit, 'C:\\path')
  assert.equal(parsed.esc, 'a\nb')
  assert.deepEqual(parsed.arr, [1, 2, 3])
  assert.deepEqual(parsed.strs, ['a', 'b'])
  assert.deepEqual(parsed.nested, { key: 5 })
})

test('parseToml skips arrays of tables and never throws on garbage', () => {
  const parsed = parseToml('a = 1\n[[units]]\nname = "x"\n[real]\nb = 2\n')
  assert.equal(parsed.a, 1)
  assert.equal(parsed.units, undefined)
  assert.deepEqual(parsed.real, { b: 2 })
  assert.doesNotThrow(() => parseToml(']]]]\n===\n\x00'))
  assert.deepEqual(parseToml(''), {})
})

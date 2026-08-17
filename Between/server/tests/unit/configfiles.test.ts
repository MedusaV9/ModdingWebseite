import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  parseProperties,
  applyProperties,
  applyIni,
  applyJson,
  applyKeyValue,
  applyConfigUpdates,
  getConfigValue,
  isStructuredFormat,
} from '../../src/lib/configfiles.ts'

test('parseProperties reads keys and skips comments', () => {
  const text = '# comment\nserver-port=25565\nmotd=Hello World\n\n! also comment\nempty=\n'
  const parsed = parseProperties(text)
  assert.equal(parsed['server-port'], '25565')
  assert.equal(parsed['motd'], 'Hello World')
  assert.equal(parsed['empty'], '')
  assert.ok(!('# comment' in parsed))
})

test('applyProperties updates existing keys and appends missing ones', () => {
  const text = '# minecraft\nserver-port=25565\nmotd=Old\n'
  const next = applyProperties(text, { 'server-port': '25600', 'max-players': '40' })
  assert.match(next, /server-port=25600/)
  assert.match(next, /motd=Old/)
  assert.match(next, /max-players=40/)
  assert.match(next, /# minecraft/) // comments preserved
})

test('applyIni updates keys inside sections', () => {
  const text = '[ServerSettings]\nServerName=Old Name\nPort=8211\n\n[Other]\nFoo=1\n'
  const next = applyIni(text, { 'ServerSettings.ServerName': 'New Name', 'Other.Foo': '2', 'Other.New': 'x' })
  assert.match(next, /ServerName=New Name/)
  assert.match(next, /Port=8211/)
  assert.match(next, /Foo=2/)
  assert.match(next, /New=x/)
})

test('applyIni handles sectionless keys', () => {
  const text = 'globalKey=1\n[Section]\na=2\n'
  const next = applyIni(text, { globalKey: '9' })
  assert.match(next, /globalKey=9/)
})

test('applyIni inserts new keys into an EXISTING section without duplicating headers', () => {
  const text = '[ServerSettings]\nPort=8211\n\n[Other]\nFoo=1\n'
  const next = applyIni(text, { 'ServerSettings.NewKey': 'val' })
  // no duplicate [ServerSettings] header
  assert.equal(next.match(/\[ServerSettings\]/g)?.length, 1)
  // the new key must live INSIDE the ServerSettings section (before [Other])
  const secStart = next.indexOf('[ServerSettings]')
  const otherStart = next.indexOf('[Other]')
  const keyPos = next.indexOf('NewKey=val')
  assert.ok(keyPos > secStart && keyPos < otherStart, `NewKey at ${keyPos} not within section (${secStart}..${otherStart})`)
})

test('applyIni appends genuinely new sections at the end', () => {
  const text = '[A]\nx=1\n'
  const next = applyIni(text, { 'B.y': '2' })
  assert.match(next, /\[B\]\ny=2/)
})

test('applyIni puts new global keys at the top, not after the last section', () => {
  const text = '[A]\nx=1\n'
  const next = applyIni(text, { globalKey: '9' })
  const keyPos = next.indexOf('globalKey=9')
  const secPos = next.indexOf('[A]')
  assert.ok(keyPos >= 0 && keyPos < secPos, 'global key must come before the first section header')
})

test('applyJson sets dot-paths and preserves other values', () => {
  const text = JSON.stringify({ game: { port: 7777, name: 'old' }, keep: true }, null, 2)
  const next = applyJson(text, { 'game.port': '7878', 'game.new.deep': 'yes' })
  const parsed = JSON.parse(next)
  assert.equal(parsed.game.port, 7878) // numeric coercion
  assert.equal(parsed.game.name, 'old')
  assert.equal(parsed.game.new.deep, 'yes')
  assert.equal(parsed.keep, true)
})

test('applyJson coerces booleans and numbers', () => {
  const next = applyJson('{}', { a: 'true', b: '42', c: 'hello' })
  const parsed = JSON.parse(next)
  assert.equal(parsed.a, true)
  assert.equal(parsed.b, 42)
  assert.equal(parsed.c, 'hello')
})

test('applyJson never pollutes Object.prototype via dangerous dot-paths', () => {
  // These keys are reachable from the config-file PUT API (user-supplied
  // configKey) and from a malicious egg's mappings during config sync.
  for (const key of ['__proto__.polluted', 'constructor.prototype.polluted', 'a.__proto__.polluted']) {
    const next = applyJson('{}', { [key]: 'bad' })
    assert.equal(({} as Record<string, unknown>).polluted, undefined, `polluted via ${key}`)
    assert.equal(Object.prototype.hasOwnProperty('polluted'), false)
    // and the dangerous write is dropped, not silently redirected elsewhere
    assert.equal(JSON.parse(next).polluted, undefined)
  }
})

test('applyKeyValue space-separated format', () => {
  const text = 'hostname "Old Server"\nmaxplayers 16\n'
  const next = applyKeyValue(text, { hostname: 'New Server', rcon_port: '27015' })
  assert.match(next, /hostname "New Server"/)
  assert.match(next, /maxplayers 16/)
  assert.match(next, /rcon_port 27015/)
})

test('isStructuredFormat covers every format except raw', () => {
  for (const format of ['properties', 'ini', 'json', 'keyvalue', 'yaml', 'toml']) assert.equal(isStructuredFormat(format), true)
  assert.equal(isStructuredFormat('raw'), false)
  assert.equal(isStructuredFormat('nonsense'), false)
})

test('applyConfigUpdates dispatches to the right engine per format', () => {
  assert.match(applyConfigUpdates('properties', 'a=1\n', { a: '2' }), /a=2/)
  assert.match(applyConfigUpdates('ini', '[s]\na=1\n', { 's.a': '2' }), /a=2/)
  assert.equal(JSON.parse(applyConfigUpdates('json', '{"a":1}', { a: '2' })).a, 2)
  assert.match(applyConfigUpdates('keyvalue', 'a 1\n', { a: '2' }), /a 2/)
  assert.match(applyConfigUpdates('yaml', 'a: 1\n', { a: '2' }), /a: 2/)
  assert.match(applyConfigUpdates('toml', 'a = 1\n', { a: '2' }), /a = 2/)
})

test('getConfigValue reads the current value per format', () => {
  assert.equal(getConfigValue('properties', 'server-port=25565\n', 'server-port'), '25565')
  assert.equal(getConfigValue('ini', 'global=1\n[Server]\nPort=8211\n', 'Server.Port'), '8211')
  assert.equal(getConfigValue('ini', 'global=1\n[Server]\nPort=8211\n', 'global'), '1')
  assert.equal(getConfigValue('json', '{"game":{"port":7777}}', 'game.port'), '7777')
  assert.equal(getConfigValue('keyvalue', 'hostname "My Server"\n', 'hostname'), 'My Server')
  assert.equal(getConfigValue('yaml', 'server:\n  motd: hello\n', 'server.motd'), 'hello')
  assert.equal(getConfigValue('toml', '[server]\nport = 25565\n', 'server.port'), '25565')
})

test('getConfigValue returns undefined for missing keys and malformed documents', () => {
  assert.equal(getConfigValue('json', 'not json at all', 'a'), undefined)
  assert.equal(getConfigValue('yaml', 'a: 1\n', 'b.c'), undefined)
  assert.equal(getConfigValue('toml', '[t]\nx = 1\n', 't.y'), undefined)
  assert.equal(getConfigValue('ini', '[s]\na=1\n', 'other.a'), undefined)
  assert.equal(getConfigValue('properties', '', 'missing'), undefined)
  assert.equal(getConfigValue('keyvalue', '// comment only\n', 'missing'), undefined)
})

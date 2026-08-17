import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseYamlDoc, stringifyYamlDoc, YamlDocError } from '../../src/lib/yamldoc.ts'

test('parses nested mappings, sequences of maps and typed scalars', () => {
  const doc = parseYamlDoc(`
# a template-ish document
id: my-game
name: "My Game"
port: 25565
fraction: 2.5
enabled: true
missing: null
platforms: [linux, win32]
variables:
  - key: SERVER_NAME
    label: Server name
    type: string
    default: My Server
  - key: PORT
    label: Port
    type: number
    default: 7777
    isPort: true
stop:
  type: command
  command: stop
`)
  assert.deepEqual(doc, {
    id: 'my-game',
    name: 'My Game',
    port: 25565,
    fraction: 2.5,
    enabled: true,
    missing: null,
    platforms: ['linux', 'win32'],
    variables: [
      { key: 'SERVER_NAME', label: 'Server name', type: 'string', default: 'My Server' },
      { key: 'PORT', label: 'Port', type: 'number', default: 7777, isPort: true },
    ],
    stop: { type: 'command', command: 'stop' },
  })
})

test('block scalars keep comment lines and blank lines literal', () => {
  const doc = parseYamlDoc(`
install:
  - type: writeFile
    path: start.sh
    content: |
      #!/bin/sh
      # this comment must survive

      echo "hello"
`) as { install: { content: string }[] }
  assert.equal(doc.install[0].content, '#!/bin/sh\n# this comment must survive\n\necho "hello"\n')
})

test('block scalar chomping: strip, clip and keep', () => {
  const doc = parseYamlDoc('a: |-\n  x\n\n\nb: |\n  y\n\n\nc: >-\n  one\n  two\n') as Record<string, string>
  assert.equal(doc.a, 'x')
  assert.equal(doc.b, 'y\n')
  assert.equal(doc.c, 'one two')
})

test('quoting: single, double with escapes, values containing colons and hashes', () => {
  const doc = parseYamlDoc(`
url: https://example.com/path
motd: "line1\\nline2"
quote: 'it''s fine'
note: value with spaces # trailing comment stripped
hash: "kept # inside quotes"
`) as Record<string, string>
  assert.equal(doc.url, 'https://example.com/path')
  assert.equal(doc.motd, 'line1\nline2')
  assert.equal(doc.quote, "it's fine")
  assert.equal(doc.note, 'value with spaces')
  assert.equal(doc.hash, 'kept # inside quotes')
})

test('leading-zero numerals stay strings (007 must not become 7)', () => {
  const doc = parseYamlDoc('a: 007\nb: 0\nc: -12\nd: 1.50\n') as Record<string, unknown>
  assert.equal(doc.a, '007')
  assert.equal(doc.b, 0)
  assert.equal(doc.c, -12)
  assert.equal(doc.d, 1.5)
})

test('flow collections nest and reject trailing garbage', () => {
  const doc = parseYamlDoc('m: {a: 1, b: [x, "y z"], c: {d: true}}\n') as Record<string, unknown>
  assert.deepEqual(doc.m, { a: 1, b: ['x', 'y z'], c: { d: true } })
  assert.throws(() => parseYamlDoc('m: [1, 2] trailing\n'), YamlDocError)
})

test('rejects tabs, anchors, multi-doc, duplicate and dangerous keys', () => {
  assert.throws(() => parseYamlDoc('a:\n\tb: 1\n'), /tab indentation/)
  assert.throws(() => parseYamlDoc('a: &anchor 1\n'), /anchors/)
  assert.throws(() => parseYamlDoc('a: 1\n---\nb: 2\n'), /multi-document/)
  assert.throws(() => parseYamlDoc('a: 1\na: 2\n'), /duplicate key/)
  assert.throws(() => parseYamlDoc('__proto__:\n  polluted: true\n'), /not allowed/)
  assert.throws(() => parseYamlDoc('m: {__proto__: {x: 1}}\n'), /not allowed/)
  const empty = {} as Record<string, unknown>
  assert.equal(empty.polluted, undefined, 'Object.prototype must stay clean')
})

test('sequence items: lone dash with nested block, null items, block scalar items', () => {
  const doc = parseYamlDoc(`
list:
  -
    a: 1
  -
  - |-
    text
`) as { list: unknown[] }
  assert.deepEqual(doc.list, [{ a: 1 }, null, 'text'])
})

test('stringifyYamlDoc round-trips arbitrary blueprint-shaped data', () => {
  const value = {
    id: 'round-trip',
    name: 'Round "Trip" — game',
    platforms: ['linux', 'win32'],
    startCommand: './run.sh -port {{PORT}} +set name "{{NAME}}"',
    install: [
      { type: 'writeFile', path: 'run.sh', content: '#!/bin/sh\n# keep me\n\nexec ./srv "$@"\n' },
      { type: 'steamcmd', appId: 896660 },
    ],
    variables: [
      { key: 'PORT', type: 'number', default: 2456, isPort: true },
      { key: 'VERSION', type: 'string', default: '007' },
      { key: 'FLAG', type: 'boolean', default: false },
    ],
    stop: { type: 'signal', signal: 'SIGINT' },
    empties: { arr: [], obj: {} },
  }
  const dumped = stringifyYamlDoc(value)
  assert.deepEqual(parseYamlDoc(dumped), value)
})

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { tokenize } from '../../src/lib/shellwords.ts'

test('splits plain words', () => {
  assert.deepEqual(tokenize('java -jar server.jar'), ['java', '-jar', 'server.jar'])
})

test('respects double quotes', () => {
  assert.deepEqual(tokenize('node "my server.js" --name "Fun Server"'), ['node', 'my server.js', '--name', 'Fun Server'])
})

test('respects single quotes', () => {
  assert.deepEqual(tokenize("echo 'hello world'"), ['echo', 'hello world'])
})

test('handles escaped spaces and quotes', () => {
  assert.deepEqual(tokenize('run a\\ b'), ['run', 'a b'])
  assert.deepEqual(tokenize('say \\"quoted\\"'), ['say', '"quoted"'])
})

test('empty and whitespace-only input', () => {
  assert.deepEqual(tokenize(''), [])
  assert.deepEqual(tokenize('   '), [])
})

test('mixed quoting inside a token', () => {
  assert.deepEqual(tokenize('--flag="some value"'), ['--flag=some value'])
})

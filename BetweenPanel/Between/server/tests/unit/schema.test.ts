import { test } from 'node:test'
import assert from 'node:assert/strict'
import { validateBlueprint } from '../../src/blueprints/schema.ts'

const VALID = {
  id: 'test-game',
  name: 'Test Game',
  category: 'custom',
  description: 'A test blueprint used by unit tests.',
  platforms: ['linux', 'win32'],
  install: [{ type: 'download', url: 'https://example.com/server.jar', target: 'server.jar' }],
  startCommand: 'java -jar server.jar --port {{SERVER_PORT}}',
  stop: { type: 'command', command: 'stop', timeoutS: 30 },
  variables: [
    { key: 'SERVER_PORT', label: 'Port', type: 'number', default: 25565, min: 1024, max: 65535, isPort: true },
  ],
  ports: [{ name: 'game', variable: 'SERVER_PORT', protocol: 'tcp' }],
  query: { type: 'none' },
}

test('valid blueprint passes', () => {
  assert.deepEqual(validateBlueprint(VALID), [])
})

test('missing required fields are reported', () => {
  const problems = validateBlueprint({})
  assert.ok(problems.length >= 4)
  assert.ok(problems.some((p) => p.includes('id')))
  assert.ok(problems.some((p) => p.includes('name')))
})

test('bad id format rejected', () => {
  const problems = validateBlueprint({ ...VALID, id: 'Bad ID!' })
  assert.ok(problems.some((p) => p.includes('id')))
})

test('unknown platform rejected', () => {
  const problems = validateBlueprint({ ...VALID, platforms: ['amiga'] })
  assert.ok(problems.some((p) => p.toLowerCase().includes('platform')))
})

test('port variable must exist', () => {
  const problems = validateBlueprint({ ...VALID, ports: [{ name: 'game', variable: 'MISSING_VAR', protocol: 'tcp' }] })
  assert.ok(problems.some((p) => p.includes('MISSING_VAR')))
})

test('variable key format enforced', () => {
  const problems = validateBlueprint({
    ...VALID,
    variables: [{ key: 'lower_case', label: 'x', type: 'string', default: '' }],
  })
  assert.ok(problems.some((p) => p.includes('key')))
})

test('enum variables need options', () => {
  const problems = validateBlueprint({
    ...VALID,
    variables: [{ key: 'MODE', label: 'Mode', type: 'enum', default: 'a' }],
  })
  assert.ok(problems.some((p) => p.toLowerCase().includes('option')))
})

test('steamcmd install step needs appId', () => {
  const problems = validateBlueprint({
    ...VALID,
    install: [{ type: 'steamcmd' }],
  })
  assert.ok(problems.some((p) => p.toLowerCase().includes('appid')))
})

test('download step accepts template variables in url', () => {
  const problems = validateBlueprint({
    ...VALID,
    variables: [
      ...VALID.variables,
      { key: 'RESOLVED_URL', label: 'Download URL', type: 'string', default: 'https://example.com/x.zip' },
    ],
    install: [{ type: 'download', url: '{{RESOLVED_URL}}', target: 'server.jar' }],
  })
  assert.deepEqual(problems, [])
})

test('stop command type requires command string', () => {
  const problems = validateBlueprint({ ...VALID, stop: { type: 'command' } })
  assert.ok(problems.some((p) => p.toLowerCase().includes('stop')))
})

test('docker-script step: valid step passes', () => {
  const problems = validateBlueprint({
    ...VALID,
    install: [{ type: 'docker-script', image: 'ghcr.io/pterodactyl/installers:alpine', script: '#!/bin/ash\necho hi', entrypoint: 'ash' }],
  })
  assert.deepEqual(problems, [])
})

test('docker-script step: entrypoint is optional', () => {
  const problems = validateBlueprint({
    ...VALID,
    install: [{ type: 'docker-script', image: 'debian:bookworm-slim', script: 'echo hi' }],
  })
  assert.deepEqual(problems, [])
})

test('docker-script step: invalid image rejected', () => {
  for (const image of ['not valid!!', '', 42, undefined]) {
    const problems = validateBlueprint({ ...VALID, install: [{ type: 'docker-script', image, script: 'echo hi' }] })
    assert.ok(problems.some((p) => p.includes('image')), `image ${JSON.stringify(image)} should be rejected`)
  }
})

test('docker-script step: script must be a non-empty string capped at 64 KiB', () => {
  for (const script of ['', 42, undefined, 'x'.repeat(64 * 1024 + 1)]) {
    const problems = validateBlueprint({ ...VALID, install: [{ type: 'docker-script', image: 'alpine:3', script }] })
    assert.ok(problems.some((p) => p.includes('script')), 'bad script should be rejected')
  }
})

test('docker-script step: bad entrypoint rejected', () => {
  for (const entrypoint of ['', 'x'.repeat(101), 42]) {
    const problems = validateBlueprint({
      ...VALID,
      install: [{ type: 'docker-script', image: 'alpine:3', script: 'echo hi', entrypoint }],
    })
    assert.ok(problems.some((p) => p.includes('entrypoint')), 'bad entrypoint should be rejected')
  }
})

test('docker-script step: script content is not scanned for template variables', () => {
  const problems = validateBlueprint({
    ...VALID,
    install: [{ type: 'docker-script', image: 'alpine:3', script: 'echo {{NOT_A_BLUEPRINT_VAR}} ${SHELL_VAR}' }],
  })
  assert.deepEqual(problems, [])
})

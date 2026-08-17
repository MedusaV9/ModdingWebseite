/**
 * Game Library catalog + SSRF helper unit tests. Everything here is
 * network-free: the catalog is validated against the real builtin blueprint
 * registry, assertPublicHttpUrl is pure/synchronous, and fetchPublicJson is
 * exercised against a throwaway local http server via its test-only
 * allowPrivateHosts hook.
 */
import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import { catalogEntries, catalogBlueprintId, getCatalogEntry } from '../../src/catalog/catalog.ts'
import { assertPublicHttpUrl, fetchPublicJson, isPrivateAddress } from '../../src/lib/nettrust.ts'
import { BlueprintRegistry } from '../../src/blueprints/registry.ts'
import { validateBlueprint } from '../../src/blueprints/schema.ts'

// ---------------------------------------------------------------------------
// Catalog integrity
// ---------------------------------------------------------------------------
const registry = new BlueprintRegistry()

test('catalog has a healthy curated size', () => {
  assert.ok(catalogEntries.length >= 30, `expected >= 30 entries, got ${catalogEntries.length}`)
  assert.ok(catalogEntries.length <= 80, `expected <= 80 entries, got ${catalogEntries.length}`)
})

test('every builtin catalog entry references a real builtin blueprint id', () => {
  for (const entry of catalogEntries) {
    if (entry.source.type !== 'builtin') continue
    assert.ok(
      registry.isBuiltin(entry.source.blueprintId),
      `catalog entry ${entry.id} references missing builtin blueprint ${entry.source.blueprintId}`,
    )
  }
})

test('catalog entries have valid shape, unique ids and known categories', () => {
  // Categories must be valid blueprint categories: the egg-url add path copies
  // entry.category onto the converted blueprint, which validateBlueprint checks.
  const categories = new Set(['minecraft', 'steam', 'sandbox', 'survival', 'shooter', 'simulation', 'voice', 'custom', 'other'])
  const ids = new Set<string>()
  for (const entry of catalogEntries) {
    assert.match(entry.id, /^[a-z0-9][a-z0-9-]{1,63}$/, `entry id ${entry.id}`)
    assert.ok(!ids.has(entry.id), `duplicate catalog id ${entry.id}`)
    ids.add(entry.id)
    assert.ok(entry.name.trim().length > 0, `${entry.id}: empty name`)
    assert.ok(entry.description.trim().length > 0, `${entry.id}: empty description`)
    assert.ok(categories.has(entry.category), `${entry.id}: unknown category ${entry.category}`)
    assert.ok(entry.source.type === 'builtin' || entry.source.type === 'egg-url', `${entry.id}: bad source type`)
  }
})

test('egg-url entries use public https URLs and map to non-colliding blueprint ids', () => {
  for (const entry of catalogEntries) {
    if (entry.source.type !== 'egg-url') continue
    const url = assertPublicHttpUrl(entry.source.url)
    assert.equal(url.protocol, 'https:', `${entry.id}: egg URL should be https`)
    const bpId = catalogBlueprintId(entry)
    assert.equal(bpId, `catalog-${entry.id}`)
    assert.ok(!registry.isBuiltin(bpId), `${entry.id}: derived blueprint id collides with a builtin`)
    // The derived id must survive blueprint validation (probe with a stub).
    const problems = validateBlueprint({
      id: bpId,
      name: entry.name,
      category: entry.category,
      description: entry.description,
      platforms: ['linux'],
      install: [],
      startCommand: 'run',
      stop: { type: 'signal', signal: 'SIGTERM' },
      variables: [],
    })
    assert.deepEqual(problems, [], `${entry.id}: ${problems.join('; ')}`)
  }
})

test('catalog spans multiple categories and both source types', () => {
  const categories = new Set(catalogEntries.map((e) => e.category))
  assert.ok(categories.size >= 5, `expected >= 5 categories, got ${[...categories].join(', ')}`)
  assert.ok(catalogEntries.some((e) => e.source.type === 'builtin'), 'no builtin entries')
  assert.ok(catalogEntries.some((e) => e.source.type === 'egg-url'), 'no egg-url entries')
  assert.equal(getCatalogEntry('does-not-exist'), undefined)
})

// ---------------------------------------------------------------------------
// assertPublicHttpUrl — scheme / port / host hardening (no network)
// ---------------------------------------------------------------------------
test('assertPublicHttpUrl accepts normal public http(s) URLs', () => {
  assert.ok(assertPublicHttpUrl('https://raw.githubusercontent.com/pelican-eggs/eggs/master/egg-paper.json'))
  assert.ok(assertPublicHttpUrl('http://example.com/egg.json'))
  assert.ok(assertPublicHttpUrl('https://example.com:443/egg.json'))
  assert.ok(assertPublicHttpUrl('http://example.com:80/egg.json'))
})

test('assertPublicHttpUrl rejects non-http(s) schemes', () => {
  assert.throws(() => assertPublicHttpUrl('file:///etc/passwd'), /only http/)
  assert.throws(() => assertPublicHttpUrl('ftp://example.com/x'), /only http/)
  assert.throws(() => assertPublicHttpUrl('gopher://example.com/x'), /only http/)
  assert.throws(() => assertPublicHttpUrl('javascript:alert(1)'), /only http|not a valid URL/)
  assert.throws(() => assertPublicHttpUrl('not a url'), /not a valid URL/)
})

test('assertPublicHttpUrl rejects loopback, private and reserved hosts', () => {
  assert.throws(() => assertPublicHttpUrl('http://localhost/x'), /local hostname/)
  assert.throws(() => assertPublicHttpUrl('http://foo.localhost/x'), /local hostname/)
  assert.throws(() => assertPublicHttpUrl('http://nas.local/x'), /local hostname/)
  assert.throws(() => assertPublicHttpUrl('http://127.0.0.1/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://127.8.9.10/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://10.1.2.3/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://172.16.0.1/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://192.168.1.1/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://169.254.169.254/meta'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://100.100.1.1/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://0.0.0.0/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://[::1]/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://[::]/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://[fc00::1]/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://[fe80::1]/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://[::ffff:127.0.0.1]/x'), /private or loopback/)
  assert.throws(() => assertPublicHttpUrl('http://intranet/x'), /fully qualified/)
})

test('assertPublicHttpUrl rejects non-standard ports and embedded credentials', () => {
  assert.throws(() => assertPublicHttpUrl('http://example.com:8080/x'), /non-standard port/)
  assert.throws(() => assertPublicHttpUrl('https://example.com:6379/x'), /non-standard port/)
  assert.throws(() => assertPublicHttpUrl('http://user:pass@example.com/x'), /credentials/)
})

test('isPrivateAddress classifies resolved addresses', () => {
  assert.equal(isPrivateAddress('140.82.121.3'), false) // github.com
  assert.equal(isPrivateAddress('185.199.108.133'), false) // raw.githubusercontent.com
  assert.equal(isPrivateAddress('127.0.0.1'), true)
  assert.equal(isPrivateAddress('10.0.0.5'), true)
  assert.equal(isPrivateAddress('169.254.169.254'), true)
  assert.equal(isPrivateAddress('::1'), true)
  assert.equal(isPrivateAddress('fd12::1'), true)
  assert.equal(isPrivateAddress('2606:50c0:8000::153'), false)
  assert.equal(isPrivateAddress('bogus'), true) // unknown shapes are not trusted
})

// ---------------------------------------------------------------------------
// fetchPublicJson — happy path + caps against a local server (test-only
// allowPrivateHosts hook; the guard itself blocks loopback, tested last)
// ---------------------------------------------------------------------------
const MINI_EGG = { name: 'Mini Egg', startup: './run {{SERVER_PORT}}', variables: [] }

const server = http.createServer((req, res) => {
  if (req.url === '/egg.json') {
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify(MINI_EGG))
  } else if (req.url === '/redirect') {
    res.statusCode = 302
    res.setHeader('location', '/egg.json')
    res.end()
  } else if (req.url === '/huge') {
    // No content-length: exercises the streaming byte cap.
    res.setHeader('content-type', 'application/json')
    res.write('[')
    res.write('1,'.repeat(64 * 1024))
    res.end('1]')
  } else if (req.url === '/not-json') {
    res.end('<html>nope</html>')
  } else if (req.url === '/slow') {
    setTimeout(() => res.end('{}'), 5000)
  } else {
    res.statusCode = 404
    res.end('nope')
  }
})
await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
const port = (server.address() as { port: number }).port
const local = (p: string) => `http://127.0.0.1:${port}${p}`

after(() => server.close())

test('fetchPublicJson fetches and parses JSON (allowPrivateHosts hook)', async () => {
  const egg = await fetchPublicJson(local('/egg.json'), { allowPrivateHosts: true })
  assert.deepEqual(egg, MINI_EGG)
})

test('fetchPublicJson follows redirects and surfaces HTTP errors', async () => {
  const egg = await fetchPublicJson(local('/redirect'), { allowPrivateHosts: true })
  assert.deepEqual(egg, MINI_EGG)
  await assert.rejects(fetchPublicJson(local('/missing'), { allowPrivateHosts: true }), /HTTP 404/)
})

test('fetchPublicJson enforces the size cap and JSON parsing', async () => {
  await assert.rejects(fetchPublicJson(local('/huge'), { allowPrivateHosts: true, maxBytes: 4096 }), /too large/)
  await assert.rejects(fetchPublicJson(local('/not-json'), { allowPrivateHosts: true }), /not valid JSON/)
})

test('fetchPublicJson enforces the hard timeout', async () => {
  await assert.rejects(fetchPublicJson(local('/slow'), { allowPrivateHosts: true, timeoutMs: 250 }), /timed out/)
})

test('fetchPublicJson blocks loopback URLs without the test hook (SSRF guard)', async () => {
  // Without allowPrivateHosts the same local server is refused before any
  // request is made — real public URLs (e.g. raw.githubusercontent.com) pass.
  await assert.rejects(fetchPublicJson(local('/egg.json')), /non-standard port|private or loopback/)
  await assert.rejects(fetchPublicJson('http://127.0.0.1/egg.json'), /private or loopback/)
})

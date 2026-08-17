import { test } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import crypto from 'node:crypto'
import { apiBase, getVersions, pickPrimaryFile, searchProjects, type ModrinthVersion } from '../../src/lib/modrinth.ts'
import { downloadFile } from '../../src/lib/download.ts'

// ---------------------------------------------------------------------------
// Local mock server speaking Modrinth-shaped JSON
// ---------------------------------------------------------------------------
const SEARCH_BODY = {
  hits: [
    {
      project_id: 'AAAA1111',
      project_type: 'mod',
      slug: 'worldedit',
      title: 'WorldEdit',
      description: 'In-game map editor',
      downloads: 12345,
      icon_url: 'https://cdn.example/icon.png',
      categories: ['paper', 'management'],
    },
    {
      project_id: 'BBBB2222',
      project_type: 'mod',
      slug: 'no-icon',
      title: 'NoIcon',
      description: 'no icon here',
      downloads: 7,
      icon_url: null,
    },
  ],
  offset: 0,
  limit: 20,
  total_hits: 2,
}

const FAKE_JAR = Buffer.from('PK\u0003\u0004 fake jar payload for download tests', 'latin1')

const VERSIONS_BODY = [
  {
    id: 'ver-new',
    project_id: 'AAAA1111',
    name: 'WorldEdit 7.3.10',
    version_number: '7.3.10',
    game_versions: ['1.21', '1.21.1'],
    loaders: ['bukkit', 'paper'],
    date_published: '2025-01-02T00:00:00Z',
    files: [
      {
        url: 'UNSET/cdn/other.txt',
        filename: 'other.txt',
        primary: false,
        size: 3,
        hashes: { sha512: 'ff', sha1: 'ee' },
      },
      {
        url: 'UNSET/cdn/worldedit-7.3.10.jar',
        filename: 'worldedit-7.3.10.jar',
        primary: true,
        size: FAKE_JAR.length,
        hashes: {
          sha512: crypto.createHash('sha512').update(FAKE_JAR).digest('hex'),
          sha1: crypto.createHash('sha1').update(FAKE_JAR).digest('hex'),
        },
      },
    ],
  },
  {
    id: 'ver-old',
    project_id: 'AAAA1111',
    name: 'WorldEdit 7.3.9',
    version_number: '7.3.9',
    game_versions: ['1.21'],
    loaders: ['paper'],
    date_published: '2024-06-01T00:00:00Z',
    files: [{ url: 'UNSET/cdn/worldedit-7.3.9.jar', filename: 'worldedit-7.3.9.jar', primary: false, size: 5, hashes: {} }],
  },
]

interface Mock {
  base: string
  requests: URL[]
  close: () => Promise<void>
}

/** Serves canned Modrinth JSON + a fake .jar; special query values trigger error paths. */
function startMock(): Promise<Mock> {
  const requests: URL[] = []
  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost')
    requests.push(url)
    if (url.searchParams.get('query') === 'boom' || url.pathname === '/project/boom/version') {
      res.writeHead(500).end('internal error')
      return
    }
    if (url.searchParams.get('query') === 'badjson') {
      res.writeHead(200, { 'content-type': 'application/json' }).end('{not json')
      return
    }
    if (url.pathname === '/search') {
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(SEARCH_BODY))
      return
    }
    if (/^\/project\/[^/]+\/version$/.test(url.pathname)) {
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(VERSIONS_BODY))
      return
    }
    if (url.pathname === '/cdn/worldedit-7.3.10.jar') {
      res.writeHead(200, { 'content-type': 'application/java-archive' }).end(FAKE_JAR)
      return
    }
    res.writeHead(404).end('not found')
  })
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address() as { port: number }
      resolve({
        base: `http://127.0.0.1:${port}`,
        requests,
        close: () => new Promise((done) => server.close(() => done())),
      })
    })
  })
}

async function withMock(fn: (mock: Mock) => Promise<void>): Promise<void> {
  const mock = await startMock()
  const prevBase = process.env.MODRINTH_API_BASE
  process.env.MODRINTH_API_BASE = mock.base
  try {
    await fn(mock)
  } finally {
    if (prevBase === undefined) delete process.env.MODRINTH_API_BASE
    else process.env.MODRINTH_API_BASE = prevBase
    await mock.close()
  }
}

// ---------------------------------------------------------------------------
// apiBase
// ---------------------------------------------------------------------------
test('apiBase reads the env override lazily at call time', () => {
  const prev = process.env.MODRINTH_API_BASE
  try {
    delete process.env.MODRINTH_API_BASE
    assert.equal(apiBase(), 'https://api.modrinth.com/v2')
    process.env.MODRINTH_API_BASE = 'http://127.0.0.1:9999'
    assert.equal(apiBase(), 'http://127.0.0.1:9999')
  } finally {
    if (prev === undefined) delete process.env.MODRINTH_API_BASE
    else process.env.MODRINTH_API_BASE = prev
  }
})

// ---------------------------------------------------------------------------
// searchProjects
// ---------------------------------------------------------------------------
test('searchProjects maps hits to the lean shape', async () => {
  await withMock(async () => {
    const hits = await searchProjects({ query: 'worldedit', loader: 'paper' })
    assert.deepEqual(hits, [
      {
        projectId: 'AAAA1111',
        slug: 'worldedit',
        title: 'WorldEdit',
        description: 'In-game map editor',
        downloads: 12345,
        iconUrl: 'https://cdn.example/icon.png',
        projectType: 'mod',
      },
      {
        projectId: 'BBBB2222',
        slug: 'no-icon',
        title: 'NoIcon',
        description: 'no icon here',
        downloads: 7,
        iconUrl: null,
        projectType: 'mod',
      },
    ])
  })
})

test('searchProjects sends the loader facet, query and default limit', async () => {
  await withMock(async (mock) => {
    await searchProjects({ query: 'worldedit', loader: 'paper' })
    const url = mock.requests[0]
    assert.equal(url.pathname, '/search')
    assert.equal(url.searchParams.get('query'), 'worldedit')
    assert.equal(url.searchParams.get('facets'), '[["categories:paper"]]')
    assert.equal(url.searchParams.get('limit'), '20')
  })
})

test('searchProjects adds the versions facet when mcVersion is given and caps limit at 50', async () => {
  await withMock(async (mock) => {
    await searchProjects({ query: 'sodium', loader: 'fabric', mcVersion: '1.21.1', limit: 999 })
    const url = mock.requests[0]
    assert.equal(url.searchParams.get('facets'), '[["categories:fabric"],["versions:1.21.1"]]')
    assert.equal(url.searchParams.get('limit'), '50')
  })
})

test('searchProjects throws a descriptive error on HTTP 500', async () => {
  await withMock(async () => {
    await assert.rejects(searchProjects({ query: 'boom', loader: 'paper' }), /modrinth search failed: HTTP 500/)
  })
})

test('searchProjects throws on invalid JSON', async () => {
  await withMock(async () => {
    await assert.rejects(searchProjects({ query: 'badjson', loader: 'paper' }), /modrinth search failed: invalid JSON/)
  })
})

test('searchProjects throws when the API is unreachable', async () => {
  const prev = process.env.MODRINTH_API_BASE
  process.env.MODRINTH_API_BASE = 'http://127.0.0.1:1' // nothing listens here
  try {
    await assert.rejects(searchProjects({ query: 'x', loader: 'paper' }), /modrinth search failed:/)
  } finally {
    if (prev === undefined) delete process.env.MODRINTH_API_BASE
    else process.env.MODRINTH_API_BASE = prev
  }
})

// ---------------------------------------------------------------------------
// getVersions
// ---------------------------------------------------------------------------
test('getVersions sends loaders + game_versions params and maps the lean shape', async () => {
  await withMock(async (mock) => {
    const versions = await getVersions('AAAA1111', { loader: 'paper', mcVersion: '1.21.1' })
    const url = mock.requests[0]
    assert.equal(url.pathname, '/project/AAAA1111/version')
    assert.equal(url.searchParams.get('loaders'), '["paper"]')
    assert.equal(url.searchParams.get('game_versions'), '["1.21.1"]')

    assert.equal(versions.length, 2)
    const [newest, oldest] = versions
    assert.equal(newest.id, 'ver-new')
    assert.equal(newest.versionNumber, '7.3.10')
    assert.deepEqual(newest.gameVersions, ['1.21', '1.21.1'])
    assert.deepEqual(newest.loaders, ['bukkit', 'paper'])
    assert.equal(newest.datePublished, '2025-01-02T00:00:00Z')
    assert.equal(newest.files.length, 2)
    assert.equal(newest.files[1].filename, 'worldedit-7.3.10.jar')
    assert.equal(newest.files[1].primary, true)
    assert.equal(newest.files[1].size, FAKE_JAR.length)
    assert.match(newest.files[1].sha512 ?? '', /^[0-9a-f]{128}$/)
    assert.match(newest.files[1].sha1 ?? '', /^[0-9a-f]{40}$/)
    // empty hashes object → both hash fields undefined
    assert.equal(oldest.files[0].sha512, undefined)
    assert.equal(oldest.files[0].sha1, undefined)
  })
})

test('getVersions omits game_versions when no mcVersion is given', async () => {
  await withMock(async (mock) => {
    await getVersions('AAAA1111', { loader: 'velocity' })
    const url = mock.requests[0]
    assert.equal(url.searchParams.get('loaders'), '["velocity"]')
    assert.equal(url.searchParams.has('game_versions'), false)
  })
})

test('getVersions throws a descriptive error on HTTP 500', async () => {
  await withMock(async () => {
    await assert.rejects(getVersions('boom', { loader: 'paper' }), /modrinth versions failed: HTTP 500/)
  })
})

// ---------------------------------------------------------------------------
// pickPrimaryFile
// ---------------------------------------------------------------------------
function fakeVersion(files: ModrinthVersion['files']): ModrinthVersion {
  return { id: 'v', name: 'v', versionNumber: '1', gameVersions: [], loaders: [], datePublished: '', files }
}

test('pickPrimaryFile prefers the primary file', () => {
  const a = { url: 'u/a.jar', filename: 'a.jar', primary: false, size: 1 }
  const b = { url: 'u/b.jar', filename: 'b.jar', primary: true, size: 2 }
  assert.equal(pickPrimaryFile(fakeVersion([a, b])), b)
})

test('pickPrimaryFile falls back to the first file when none is primary', () => {
  const a = { url: 'u/a.jar', filename: 'a.jar', primary: false, size: 1 }
  const b = { url: 'u/b.jar', filename: 'b.jar', primary: false, size: 2 }
  assert.equal(pickPrimaryFile(fakeVersion([a, b])), a)
})

test('pickPrimaryFile returns null for an empty file list', () => {
  assert.equal(pickPrimaryFile(fakeVersion([])), null)
})

// ---------------------------------------------------------------------------
// download + sha512 verification (the install path uses downloadFile)
// ---------------------------------------------------------------------------
test('downloadFile verifies a Modrinth sha512 hash', async () => {
  await withMock(async (mock) => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'modrinth-test-'))
    try {
      const dest = path.join(tmp, 'worldedit.jar')
      const sha512 = crypto.createHash('sha512').update(FAKE_JAR).digest('hex')
      const { bytes } = await downloadFile(`${mock.base}/cdn/worldedit-7.3.10.jar`, dest, { sha512 })
      assert.equal(bytes, FAKE_JAR.length)
      assert.deepEqual(fs.readFileSync(dest), FAKE_JAR)
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true })
    }
  })
})

test('downloadFile rejects on sha512 mismatch and leaves no file behind', async () => {
  await withMock(async (mock) => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'modrinth-test-'))
    try {
      const dest = path.join(tmp, 'worldedit.jar')
      await assert.rejects(
        downloadFile(`${mock.base}/cdn/worldedit-7.3.10.jar`, dest, { sha512: 'a'.repeat(128) }),
        /checksum mismatch/,
      )
      assert.equal(fs.existsSync(dest), false)
      assert.equal(fs.existsSync(`${dest}.part`), false)
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true })
    }
  })
})

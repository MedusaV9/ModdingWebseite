import { createApp } from './app.ts'
import { PANEL_VERSION } from './config.ts'

const app = createApp()

const BANNER = String.raw`
  ____       _
 | __ )  ___| |___      _____  ___ _ __
 |  _ \ / _ \ __\ \ /\ / / _ \/ _ \ '_ \
 | |_) |  __/ |_ \ V  V /  __/  __/ | | |
 |____/ \___|\__| \_/\_/ \___|\___|_| |_|
`

app
  .start()
  .then(({ port }) => {
    console.log(BANNER)
    if (app.ctx.config.mode === 'node') {
      console.log(`  Between v${PANEL_VERSION} — node agent "${app.ctx.config.nodeName}"`)
      console.log(`  Agent:    http://localhost:${port} (token auth)`)
      console.log(`  Data dir: ${app.ctx.config.dataDir}`)
      console.log(`  Platform: ${process.platform} (${process.arch})`)
      console.log('\n  Register this node in your panel under Admin → Nodes.\n')
      return
    }
    console.log(`  Between v${PANEL_VERSION} — game server management panel`)
    console.log(`  Panel:    http://localhost:${port}`)
    console.log(`  Data dir: ${app.ctx.config.dataDir}`)
    console.log(`  Platform: ${process.platform} (${process.arch})`)
    if (app.ctx.auth.setupRequired()) {
      console.log('\n  First run: open the panel in your browser to create the admin account.')
    }
    console.log('')
  })
  .catch((err) => {
    console.error('Failed to start Between:', err)
    process.exit(1)
  })

let shuttingDown = false
async function shutdown(signal: string) {
  if (shuttingDown) return
  shuttingDown = true
  console.log(`\n[${signal}] shutting down — stopping game servers gracefully...`)
  await app.stop()
  process.exit(0)
}

process.on('SIGINT', () => void shutdown('SIGINT'))
process.on('SIGTERM', () => void shutdown('SIGTERM'))

// Last-resort safety nets: a rejected promise in a background timer must not
// take the panel (and every managed game server) down with it.
process.on('unhandledRejection', (reason) => {
  console.error('[panel] unhandled promise rejection:', reason)
})
process.on('uncaughtException', (err) => {
  console.error('[panel] uncaught exception — flushing data and exiting:', err)
  try {
    app.ctx.store.flushAll()
  } catch {
    /* best effort */
  }
  process.exit(1)
})

/**
 * Manual smoke test: resolve current download URLs for the direct-download
 * server software (PaperMC Fill v3, Mojang piston-meta, Fabric meta).
 * Run: npx tsx scripts/test-resolvers.ts
 */
import { resolvePaper, resolveVanilla, resolveFabric } from '../src/install/resolvers.ts'

const paper = await resolvePaper('paper', 'latest')
console.log('paper latest  :', paper.label, '| sha256', paper.sha256?.slice(0, 12) ?? '(none)')
const pinned = await resolvePaper('paper', '1.21.8')
console.log('paper pinned  :', pinned.label)
const velocity = await resolvePaper('velocity', 'latest')
console.log('velocity      :', velocity.label)
const vanilla = await resolveVanilla('latest')
console.log('vanilla       :', vanilla.label)
const fabric = await resolveFabric('latest')
console.log('fabric        :', fabric.label)
console.log('all resolvers OK')

import { useCallback, useEffect, useMemo, useRef, useState, type DragEvent } from 'react'
import {
  Archive, CheckCircle2, ChevronRight, Copy as CopyIcon, Download, File as FileIcon, FileArchive,
  FileImage, FilePen, Folder, FolderInput, FolderPlus, Home, Loader2, Pencil, Plus, Trash2,
  Upload as UploadIcon, UploadCloud, X, XCircle,
} from 'lucide-react'
import { api, ApiError, uploadFile } from '../../api/client.ts'
import type { FileEntry } from '../../api/types.ts'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Button, Card, Checkbox, cx, EmptyState, Field, IconButton, Input, Spinner, TextArea } from '../../components/ui.tsx'
import { Modal, ConfirmModal } from '../../components/Modal.tsx'
import { ProgressBar } from '../../components/Sparkline.tsx'
import { formatBytes, formatDateTime } from '../../lib/format.ts'

const ARCHIVE_RE = /\.(zip|tar\.gz|tgz|tar)$/i

/** Image preview: extensions we render (svg strictly via <img>, never inlined). */
const IMAGE_MIME: Record<string, string> = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  gif: 'image/gif',
  webp: 'image/webp',
  svg: 'image/svg+xml',
}
/** Matches the backend's editor cap — anything larger is a download, not a preview. */
const PREVIEW_MAX = 5 * 1024 * 1024

function imageMime(name: string): string | null {
  const dot = name.lastIndexOf('.')
  if (dot <= 0) return null
  return IMAGE_MIME[name.slice(dot + 1).toLowerCase()] ?? null
}

function joinPath(dir: string, name: string): string {
  return dir ? `${dir}/${name}` : name
}

/** Tailwind `lg` breakpoint (64rem) — picks side panel vs bottom sheet for the detail view. */
function useIsLg(): boolean {
  const [isLg, setIsLg] = useState(() => window.matchMedia('(min-width: 64rem)').matches)
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 64rem)')
    const onChange = () => setIsLg(mq.matches)
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])
  return isLg
}

// --- Drag & drop upload queue -------------------------------------------------

/** Two parallel PUTs keep small-file batches fast without hammering the panel. */
const UPLOAD_CONCURRENCY = 2

interface UploadItem {
  id: number
  /** Display name incl. any folder-relative subpath ("plugins/foo.jar"). */
  label: string
  /** Directory (relative to the server root) this file uploads into. */
  destDir: string
  file: File
  pct: number
  status: 'queued' | 'uploading' | 'done' | 'error'
  error?: string
}

interface DroppedFile {
  file: File
  /** Subpath relative to the drop target dir ('' for top-level files). */
  rel: string
}

/**
 * Recursively walk a FileSystemEntry from a folder drop. The backend upload
 * route accepts subdirectories in its `path` query param (mkdir -p semantics),
 * so folder drops upload each contained file with its relative subpath.
 */
async function walkEntry(entry: FileSystemEntry, rel: string, out: DroppedFile[]): Promise<void> {
  if (entry.isFile) {
    const file = await new Promise<File>((resolve, reject) => (entry as FileSystemFileEntry).file(resolve, reject))
    out.push({ file, rel })
  } else if (entry.isDirectory) {
    const reader = (entry as FileSystemDirectoryEntry).createReader()
    const sub = rel ? `${rel}/${entry.name}` : entry.name
    // readEntries returns batches (Chrome caps them at 100) — loop until empty.
    for (;;) {
      const batch = await new Promise<FileSystemEntry[]>((resolve, reject) => reader.readEntries(resolve, reject))
      if (batch.length === 0) break
      for (const child of batch) await walkEntry(child, sub, out)
    }
  }
}

/**
 * Flatten a drop's DataTransfer into files with folder-relative subpaths.
 * webkitGetAsEntry() must be read synchronously (before the first await) —
 * the item list is neutered once the drop handler yields to the event loop.
 */
async function collectDropped(dt: DataTransfer): Promise<DroppedFile[]> {
  const entries: FileSystemEntry[] = []
  const plain: File[] = []
  for (const item of Array.from(dt.items ?? [])) {
    if (item.kind !== 'file') continue
    const entry = typeof item.webkitGetAsEntry === 'function' ? item.webkitGetAsEntry() : null
    if (entry) entries.push(entry)
    else {
      const file = item.getAsFile()
      if (file) plain.push(file)
    }
  }
  // Older engines without DataTransferItem support: fall back to the flat list.
  if (entries.length === 0 && plain.length === 0) plain.push(...Array.from(dt.files))
  const out: DroppedFile[] = plain.map((file) => ({ file, rel: '' }))
  for (const entry of entries) await walkEntry(entry, '', out)
  return out
}

// --- Copy-to / Move-to directory picker ----------------------------------------

function DirPickerModal({
  open,
  title,
  serverId,
  startDir,
  busy,
  onClose,
  onSelect,
}: {
  open: boolean
  title: string
  serverId: string
  startDir: string
  busy: boolean
  onClose: () => void
  onSelect: (dir: string) => void
}) {
  const t = useT()
  const [pickDir, setPickDir] = useState(startDir)
  const [dirs, setDirs] = useState<FileEntry[] | null>(null)
  const seq = useRef(0)

  useEffect(() => {
    if (open) setPickDir(startDir)
  }, [open, startDir])

  useEffect(() => {
    if (!open) return
    const s = ++seq.current
    setDirs(null)
    api
      .get<{ entries: FileEntry[] }>(`/api/servers/${serverId}/files?path=${encodeURIComponent(pickDir)}`)
      .then((res) => {
        if (s === seq.current) setDirs(res.entries.filter((e) => e.isDir))
      })
      .catch(() => {
        if (s === seq.current) setDirs([])
      })
  }, [open, pickDir, serverId])

  const crumbs = pickDir ? pickDir.split('/') : []
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>{t('common.cancel')}</Button>
          <Button variant="primary" loading={busy} onClick={() => onSelect(pickDir)}>
            {t('files.selectHere')}
          </Button>
        </>
      }
    >
      <div className="glass-subtle mb-3 flex items-center gap-1 overflow-x-auto rounded-full px-3.5 py-2 text-[0.8125rem] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        <button
          onClick={() => setPickDir('')}
          className="pressable flex items-center gap-1.5 whitespace-nowrap rounded-full text-muted hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
        >
          <Home size={13} />
          {t('files.root')}
        </button>
        {crumbs.map((part, i) => (
          <span key={i} className="flex items-center gap-1">
            <ChevronRight size={12} className="shrink-0 text-muted/50" />
            <button
              onClick={() => setPickDir(crumbs.slice(0, i + 1).join('/'))}
              className="pressable whitespace-nowrap rounded-full hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            >
              {part}
            </button>
          </span>
        ))}
      </div>
      <div className="max-h-64 space-y-1 overflow-y-auto">
        {dirs === null && <Spinner />}
        {dirs?.length === 0 && <p className="px-1 py-2 text-xs text-muted">{t('files.noSubfolders')}</p>}
        {dirs?.map((d) => (
          <button
            key={d.name}
            onClick={() => setPickDir(joinPath(pickDir, d.name))}
            className="pressable flex w-full items-center gap-2 rounded-xl px-2.5 py-2 text-left text-[0.8125rem] hover:bg-elevated/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
          >
            <Folder size={15} className="shrink-0 text-accent/80" />
            <span className="min-w-0 flex-1 break-all">{d.name}</span>
            <ChevronRight size={13} className="shrink-0 text-muted/50" />
          </button>
        ))}
      </div>
    </Modal>
  )
}

// --- Detail panel (AMP-style) ---------------------------------------------------

type PreviewState = 'none' | 'loading' | 'ready' | 'toolarge' | 'error'

function FileDetail({
  entry,
  dir,
  preview,
  mayWrite,
  remote,
  busy,
  onDownload,
  onRename,
  onCopy,
  onMove,
  onExtract,
  onDelete,
}: {
  entry: FileEntry
  dir: string
  preview: { url: string | null; state: PreviewState }
  mayWrite: boolean
  remote: boolean
  busy: boolean
  onDownload: () => void
  onRename: () => void
  onCopy: () => void
  onMove: () => void
  onExtract: () => void
  onDelete: () => void
}) {
  const t = useT()
  const isArchive = !entry.isDir && ARCHIVE_RE.test(entry.name)
  const isImage = !entry.isDir && imageMime(entry.name) !== null
  const typeLabel = entry.isDir
    ? t('files.typeFolder')
    : isArchive
      ? t('files.typeArchive')
      : isImage
        ? t('files.typeImage')
        : t('files.typeFile')
  return (
    <div className="space-y-4">
      <div className="flex items-start gap-2.5">
        {entry.isDir ? (
          <Folder size={20} className="mt-0.5 shrink-0 text-accent/80" />
        ) : isArchive ? (
          <FileArchive size={20} className="mt-0.5 shrink-0 text-warn/80" />
        ) : isImage ? (
          <FileImage size={20} className="mt-0.5 shrink-0 text-accent/80" />
        ) : (
          <FileIcon size={20} className="mt-0.5 shrink-0 text-muted" />
        )}
        <div className="min-w-0">
          <p className="break-all text-sm font-semibold">{entry.name}</p>
          <p className="mt-0.5 text-xs text-muted">{typeLabel}</p>
        </div>
      </div>

      {isImage && (
        <div className="glass-subtle overflow-hidden rounded-xl">
          {preview.state === 'loading' && (
            <div className="flex h-32 items-center justify-center">
              <Spinner />
            </div>
          )}
          {preview.state === 'ready' && preview.url && (
            /* Object URL from the authed download fetch; svg stays inside an
               <img> so embedded scripts can never run in the page context. */
            <img src={preview.url} alt={entry.name} className="max-h-56 w-full object-contain" />
          )}
          {preview.state === 'toolarge' && <p className="px-3 py-2.5 text-xs text-muted">{t('files.previewTooLarge')}</p>}
          {preview.state === 'error' && <p className="px-3 py-2.5 text-xs text-warn">{t('files.previewFailed')}</p>}
        </div>
      )}

      <dl className="space-y-2.5">
        <div>
          <dt className="microlabel">{t('files.size')}</dt>
          <dd className="tabular mt-0.5 font-mono text-xs">{entry.isDir ? '—' : formatBytes(entry.size)}</dd>
        </div>
        <div>
          <dt className="microlabel">{t('files.modified')}</dt>
          <dd className="tabular mt-0.5 font-mono text-xs">{formatDateTime(entry.mtimeMs)}</dd>
        </div>
        <div>
          <dt className="microlabel">{t('files.path')}</dt>
          <dd className="mt-0.5 break-all font-mono text-xs text-muted">/{joinPath(dir, entry.name)}</dd>
        </div>
      </dl>

      <div className="flex flex-wrap gap-1.5">
        <Button size="sm" variant="secondary" onClick={onDownload}>
          <Download size={13} />
          {t('common.download')}
        </Button>
        {mayWrite && !remote && (
          <>
            <Button size="sm" variant="secondary" onClick={onRename}>
              <Pencil size={13} />
              {t('common.rename')}
            </Button>
            <Button size="sm" variant="secondary" onClick={onCopy}>
              <CopyIcon size={13} />
              {t('files.copyTo')}
            </Button>
            <Button size="sm" variant="secondary" onClick={onMove}>
              <FolderInput size={13} />
              {t('files.moveTo')}
            </Button>
            {isArchive && (
              <Button size="sm" variant="secondary" loading={busy} onClick={onExtract}>
                <Archive size={13} />
                {t('files.unzip')}
              </Button>
            )}
          </>
        )}
        {mayWrite && (
          <Button size="sm" variant="danger" onClick={onDelete}>
            <Trash2 size={13} />
            {t('common.delete')}
          </Button>
        )}
      </div>
    </div>
  )
}

export function FilesTab() {
  const { server, can } = useServer()
  const t = useT()
  const toast = useToast()
  const mayWrite = can('server.files.write')
  // Rename/zip/extract are gateway-blocked for remote servers this round —
  // hidden rather than left to 400. Everything else streams transparently.
  const remote = server.nodeId != null
  const [dir, setDir] = useState('')
  const [entries, setEntries] = useState<FileEntry[] | null>(null)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [busy, setBusy] = useState(false)
  // Latest-wins guards: a slow response for a previous directory/file must not
  // overwrite state after the user navigated elsewhere (silent corruption).
  const loadSeq = useRef(0)
  const editorSeq = useRef(0)

  // Modals
  const [editorPath, setEditorPath] = useState<string | null>(null)
  const [editorContent, setEditorContent] = useState('')
  const [editorOriginal, setEditorOriginal] = useState('')
  const [editorMeta, setEditorMeta] = useState<{ binary: boolean; truncated: boolean } | null>(null)
  const [editorSaving, setEditorSaving] = useState(false)
  const [newFileOpen, setNewFileOpen] = useState(false)
  const [newFolderOpen, setNewFolderOpen] = useState(false)
  const [renameFrom, setRenameFrom] = useState<string | null>(null)
  const [nameInput, setNameInput] = useState('')
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [zipOpen, setZipOpen] = useState(false)
  const [transfer, setTransfer] = useState<{ mode: 'copy' | 'move'; name: string } | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)

  // Detail side panel (≥lg) / bottom sheet (<lg)
  const isLg = useIsLg()
  const [detail, setDetail] = useState<{ entry: FileEntry; dir: string } | null>(null)
  const [preview, setPreview] = useState<{ url: string | null; state: PreviewState }>({ url: null, state: 'none' })

  // Upload queue: source of truth lives in a ref (mutated by concurrent XHR
  // callbacks), mirrored into state for rendering after every mutation.
  const [uploads, setUploads] = useState<UploadItem[]>([])
  const uploadsRef = useRef<UploadItem[]>([])
  const activeUploads = useRef(0)
  const uploadIdSeq = useRef(0)
  const dismissTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [dragActive, setDragActive] = useState(false)
  const dragDepth = useRef(0)

  const load = useCallback(
    async (path = dir) => {
      const seq = ++loadSeq.current
      try {
        const res = await api.get<{ entries: FileEntry[] }>(`/api/servers/${server.id}/files?path=${encodeURIComponent(path)}`)
        if (seq !== loadSeq.current) return // a newer navigation won
        setEntries(res.entries)
        setSelected(new Set())
      } catch (err) {
        if (seq === loadSeq.current) toast('error', (err as Error).message)
      }
    },
    [server.id, dir, toast],
  )

  useEffect(() => {
    setEntries(null)
    void load(dir)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dir, server.id])

  // The queue's end-of-batch refresh must reload whatever directory is CURRENT
  // when the last upload finishes (the user may navigate mid-upload), not the
  // one captured when the batch started.
  const loadRef = useRef(load)
  useEffect(() => {
    loadRef.current = load
  })

  useEffect(
    () => () => {
      if (dismissTimer.current) clearTimeout(dismissTimer.current)
    },
    [],
  )

  const crumbs = useMemo(() => (dir ? dir.split('/') : []), [dir])

  // Keep the detail entry in sync with reloads: refresh its metadata after a
  // mutation, close the panel when the entry vanished or the user navigated.
  useEffect(() => {
    setDetail((prev) => {
      if (!prev) return prev
      if (prev.dir !== dir) return null
      if (!entries) return prev
      const fresh = entries.find((e) => e.name === prev.entry.name && e.isDir === prev.entry.isDir)
      return fresh ? { entry: fresh, dir } : null
    })
  }, [entries, dir])

  // Image preview: fetch bytes through the authed download route (works for
  // remote-node servers too — it stream-proxies), wrap them in a Blob with
  // the extension's MIME type and hand an object URL to <img>. The URL is
  // revoked on close/switch; files above PREVIEW_MAX are never fetched.
  const previewPath = detail && !detail.entry.isDir ? joinPath(detail.dir, detail.entry.name) : null
  const previewSize = detail?.entry.size ?? 0
  useEffect(() => {
    const mime = previewPath ? imageMime(previewPath) : null
    if (!previewPath || !mime) {
      setPreview({ url: null, state: 'none' })
      return
    }
    if (previewSize > PREVIEW_MAX) {
      setPreview({ url: null, state: 'toolarge' })
      return
    }
    let cancelled = false
    let url: string | null = null
    setPreview({ url: null, state: 'loading' })
    fetch(`/api/servers/${server.id}/files/download?path=${encodeURIComponent(previewPath)}`, { credentials: 'same-origin' })
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.arrayBuffer()
      })
      .then((buf) => {
        if (cancelled) return
        url = URL.createObjectURL(new Blob([buf], { type: mime }))
        setPreview({ url, state: 'ready' })
      })
      .catch(() => {
        if (!cancelled) setPreview({ url: null, state: 'error' })
      })
    return () => {
      cancelled = true
      if (url) URL.revokeObjectURL(url)
    }
  }, [previewPath, previewSize, server.id])

  // Esc closes the desktop side panel — unless a modal is open on top of it
  // (the modal's own Esc handling wins, closing both at once would be jarring).
  const detailOpen = detail !== null
  const anyModalOpen =
    editorPath !== null || newFileOpen || newFolderOpen || renameFrom !== null || deleteOpen || zipOpen || transfer !== null
  useEffect(() => {
    if (!detailOpen || !isLg || anyModalOpen) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setDetail(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [detailOpen, isLg, anyModalOpen])

  const toggle = (name: string) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(name)) next.delete(name)
      else next.add(name)
      return next
    })
  }

  const run = async (fn: () => Promise<unknown>, reload = true) => {
    setBusy(true)
    try {
      await fn()
      if (reload) await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  const openEditor = async (name: string) => {
    const path = joinPath(dir, name)
    const seq = ++editorSeq.current
    setEditorPath(path)
    setEditorContent('')
    setEditorOriginal('')
    setEditorMeta(null)
    try {
      const res = await api.get<{ content: string; binary: boolean; truncated: boolean }>(
        `/api/servers/${server.id}/files/content?path=${encodeURIComponent(path)}`,
      )
      // Bail if another file was opened (or this one closed) meanwhile —
      // otherwise stale content could be shown and then saved into the new path.
      if (seq !== editorSeq.current) return
      setEditorContent(res.content)
      setEditorOriginal(res.content)
      setEditorMeta({ binary: res.binary, truncated: res.truncated })
    } catch (err) {
      if (seq !== editorSeq.current) return
      toast('error', (err as Error).message)
      setEditorPath(null)
    }
  }

  const saveEditor = async () => {
    if (!editorPath) return
    setEditorSaving(true)
    try {
      await api.put(`/api/servers/${server.id}/files/content`, { path: editorPath, content: editorContent })
      toast('success', t('common.saved'))
      setEditorPath(null)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setEditorSaving(false)
    }
  }

  const syncUploads = () => setUploads([...uploadsRef.current])

  const clearUploads = () => {
    if (dismissTimer.current) {
      clearTimeout(dismissTimer.current)
      dismissTimer.current = null
    }
    uploadsRef.current = []
    setUploads([])
  }

  const pumpUploads = useCallback(() => {
    while (activeUploads.current < UPLOAD_CONCURRENCY) {
      // Never upload two files to the same target concurrently (interleaved
      // writes would corrupt the file) — that duplicate stays queued.
      const busyTargets = new Set(
        uploadsRef.current.filter((u) => u.status === 'uploading').map((u) => joinPath(u.destDir, u.file.name)),
      )
      const next = uploadsRef.current.find(
        (u) => u.status === 'queued' && !busyTargets.has(joinPath(u.destDir, u.file.name)),
      )
      if (!next) break
      next.status = 'uploading'
      activeUploads.current++
      syncUploads()
      uploadFile(
        `/api/servers/${server.id}/files/upload?path=${encodeURIComponent(next.destDir)}&name=${encodeURIComponent(next.file.name)}`,
        next.file,
        (pct) => {
          next.pct = pct
          syncUploads()
        },
      )
        .then(() => {
          next.status = 'done'
          next.pct = 100
        })
        .catch((err) => {
          next.status = 'error'
          next.error = err instanceof Error ? err.message : String(err)
        })
        .finally(() => {
          activeUploads.current--
          syncUploads()
          if (uploadsRef.current.some((u) => u.status === 'queued')) {
            pumpUploads()
          } else if (activeUploads.current === 0) {
            // Batch drained: refresh the listing once. All-success batches
            // auto-dismiss shortly after; errors stay until dismissed.
            void loadRef.current()
            if (uploadsRef.current.every((u) => u.status === 'done')) {
              dismissTimer.current = setTimeout(() => {
                dismissTimer.current = null
                uploadsRef.current = []
                setUploads([])
              }, 1600)
            }
          }
        })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [server.id])

  const enqueueUploads = (list: DroppedFile[]) => {
    if (list.length === 0) return
    if (dismissTimer.current) {
      clearTimeout(dismissTimer.current)
      dismissTimer.current = null
    }
    for (const { file, rel } of list) {
      uploadsRef.current.push({
        id: ++uploadIdSeq.current,
        label: rel ? `${rel}/${file.name}` : file.name,
        destDir: rel ? joinPath(dir, rel) : dir,
        file,
        pct: 0,
        status: 'queued',
      })
    }
    syncUploads()
    pumpUploads()
  }

  const onUpload = (files: FileList | null) => {
    if (!files || files.length === 0) return
    enqueueUploads(Array.from(files).map((file) => ({ file, rel: '' })))
  }

  const hasFilesDrag = (e: DragEvent) => Array.from(e.dataTransfer.types).includes('Files')

  const onDragEnter = (e: DragEvent) => {
    if (!hasFilesDrag(e)) return
    e.preventDefault()
    dragDepth.current++
    setDragActive(true)
  }

  const onDragOver = (e: DragEvent) => {
    if (!hasFilesDrag(e)) return
    e.preventDefault()
    e.dataTransfer.dropEffect = 'copy'
  }

  const onDragLeave = (e: DragEvent) => {
    if (!hasFilesDrag(e)) return
    // Counter instead of a plain flag: entering a child fires enter-before-
    // leave on the parent, which would otherwise flicker the overlay off.
    dragDepth.current = Math.max(0, dragDepth.current - 1)
    if (dragDepth.current === 0) setDragActive(false)
  }

  const onDrop = (e: DragEvent) => {
    if (!hasFilesDrag(e)) return
    e.preventDefault()
    dragDepth.current = 0
    setDragActive(false)
    void collectDropped(e.dataTransfer).then(enqueueUploads)
  }

  const download = (name: string) => {
    const url = `/api/servers/${server.id}/files/download?path=${encodeURIComponent(joinPath(dir, name))}`
    const a = document.createElement('a')
    a.href = url
    a.download = name
    a.click()
  }

  const extractEntry = (name: string) =>
    run(async () => {
      const res = await api.post<{ files: number }>(`/api/servers/${server.id}/files/extract`, { path: joinPath(dir, name) })
      toast('success', t('files.extractedCount', { count: res.files }))
    })

  const submitTransfer = (toDir: string) => {
    if (!transfer) return
    const { mode, name } = transfer
    void run(async () => {
      const res = await api.post<{ name: string }>(`/api/servers/${server.id}/files/${mode}`, {
        path: joinPath(dir, name),
        toDir,
      })
      toast('success', t(mode === 'copy' ? 'files.copiedAs' : 'files.movedAs', { name: res.name }))
      setTransfer(null)
    })
  }

  // Detail-panel actions re-use the row-action modals; below lg the sheet
  // closes first so the follow-up modal doesn't stack on top of it.
  const fromDetail = (fn: () => void) => () => {
    if (!isLg) setDetail(null)
    fn()
  }

  const defaultArchiveName = () => {
    const d = new Date()
    const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`
    return `archive-${ymd}.zip`
  }

  const uploadBusy = uploads.some((u) => u.status === 'queued' || u.status === 'uploading')
  const uploadsDone = uploads.filter((u) => u.status === 'done').length
  const uploadErrors = uploads.filter((u) => u.status === 'error').length

  return (
    <div
      className="relative space-y-3"
      onDragEnter={mayWrite ? onDragEnter : undefined}
      onDragOver={mayWrite ? onDragOver : undefined}
      onDragLeave={mayWrite ? onDragLeave : undefined}
      onDrop={mayWrite ? onDrop : undefined}
    >
      {/* Drop overlay — write permission only; pointer-events-none so child
          enter/leave events keep flowing to the container underneath. */}
      {mayWrite && dragActive && (
        <div className="fade-in pointer-events-none absolute inset-0 z-20" aria-hidden>
          <div className="glass-strong flex h-full w-full flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed border-accent/60">
            <UploadCloud size={34} className="text-accent" />
            <p className="px-6 text-center text-sm font-medium">{t('files.dropHere', { path: `/${dir}` })}</p>
          </div>
        </div>
      )}

      {/* Toolbar */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="glass-subtle flex min-w-0 flex-1 items-center gap-1 overflow-x-auto rounded-full px-4 py-2.5 text-[0.8125rem] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          <button
            onClick={() => setDir('')}
            className="pressable flex items-center gap-1.5 whitespace-nowrap rounded-full text-muted hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
          >
            <Home size={13} />
            {t('files.root')}
          </button>
          {crumbs.map((part, i) => (
            <span key={i} className="flex items-center gap-1">
              <ChevronRight size={12} className="shrink-0 text-muted/50" />
              <button
                onClick={() => setDir(crumbs.slice(0, i + 1).join('/'))}
                className="pressable whitespace-nowrap rounded-full hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
              >
                {part}
              </button>
            </span>
          ))}
        </div>
        <div className="flex items-center gap-1.5">
          {selected.size > 0 && (
            <>
              <span className="text-xs text-muted">{t('files.selected', { count: selected.size })}</span>
              {mayWrite && !remote && (
                <Button size="sm" variant="secondary" onClick={() => { setNameInput(defaultArchiveName()); setZipOpen(true) }}>
                  <Archive size={13} />
                  {t('files.createArchive')}
                </Button>
              )}
              {mayWrite && (
                <Button size="sm" variant="danger" onClick={() => setDeleteOpen(true)}>
                  <Trash2 size={13} />
                  {t('common.delete')}
                </Button>
              )}
              <IconButton size="sm" label={t('common.cancel')} onClick={() => setSelected(new Set())}>
                <X size={13} />
              </IconButton>
            </>
          )}
          {mayWrite && (
            <>
              <Button size="sm" variant="secondary" onClick={() => { setNameInput(''); setNewFileOpen(true) }}>
                <Plus size={13} />
                {t('files.newFile')}
              </Button>
              <Button size="sm" variant="secondary" onClick={() => { setNameInput(''); setNewFolderOpen(true) }}>
                <FolderPlus size={13} />
                {t('files.newFolder')}
              </Button>
              <Button size="sm" variant="primary" onClick={() => fileInput.current?.click()}>
                {uploadBusy ? <Loader2 size={13} className="animate-spin" /> : <UploadIcon size={13} />}
                {t('files.uploadBtn')}
              </Button>
              <input
                ref={fileInput}
                type="file"
                multiple
                hidden
                onChange={(e) => {
                  onUpload(e.target.files)
                  e.target.value = '' // allow re-selecting the same file
                }}
              />
            </>
          )}
        </div>
      </div>

      {/* Upload progress strip */}
      {uploads.length > 0 && (
        <Card className="fade-in-up p-3.5">
          <div className="flex items-center justify-between gap-2">
            <span className="microlabel">
              {uploadBusy
                ? t('files.uploading', { done: uploadsDone, total: uploads.length })
                : uploadErrors > 0
                  ? t('files.uploadFailed', { count: uploadErrors })
                  : t('files.uploadDone')}
            </span>
            {!uploadBusy && (
              <IconButton size="sm" label={t('common.close')} onClick={clearUploads}>
                <X size={13} />
              </IconButton>
            )}
          </div>
          <ul className="mt-2 max-h-44 space-y-1.5 overflow-y-auto">
            {uploads.map((u) => (
              <li key={u.id} className="flex items-center gap-2 text-[0.8125rem]">
                {u.status === 'done' && <CheckCircle2 size={14} className="shrink-0 text-success" />}
                {u.status === 'error' && <XCircle size={14} className="shrink-0 text-danger" />}
                {u.status === 'uploading' && <Loader2 size={14} className="shrink-0 animate-spin text-accent" />}
                {u.status === 'queued' && <FileIcon size={14} className="shrink-0 text-muted/60" />}
                <span className="min-w-0 flex-1 truncate">{u.label}</span>
                {u.status === 'uploading' && (
                  <>
                    <div className="w-24 shrink-0 sm:w-36">
                      <ProgressBar pct={u.pct} colorClass="bg-[linear-gradient(100deg,var(--t-accent),var(--t-accent2))]" />
                    </div>
                    <span className="tabular w-9 shrink-0 text-right font-mono text-xs text-muted">{u.pct}%</span>
                  </>
                )}
                {u.status === 'queued' && <span className="shrink-0 text-xs text-muted/70">{t('files.queued')}</span>}
                {u.status === 'error' && <span className="max-w-[45%] shrink-0 truncate text-xs text-danger">{u.error}</span>}
                {u.status === 'done' && <span className="tabular shrink-0 font-mono text-xs text-muted">{formatBytes(u.file.size)}</span>}
              </li>
            ))}
          </ul>
        </Card>
      )}

      {/* Table + detail side panel (grid split ≥lg, like ConsoleTab's players column) */}
      <div className={cx(detailOpen && 'lg:grid lg:grid-cols-[minmax(0,1fr)_300px] lg:items-start lg:gap-3')}>
        <Card className="overflow-hidden">
          {!entries && <Spinner />}
          {entries && entries.length === 0 && <EmptyState icon={<Folder size={36} />} title={t('files.emptyDir')} />}
          {entries && entries.length > 0 && (
            <div className="table-scroll">
              <table className="w-full min-w-[34rem] text-[0.8125rem]">
                <thead>
                  <tr className="microlabel border-b border-line/70 text-left">
                    <th className="w-8 px-3 py-2" />
                    <th className="px-2 py-2">{t('files.name')}</th>
                    <th className="w-24 px-2 py-2">{t('files.size')}</th>
                    <th className="hidden w-40 px-2 py-2 sm:table-cell">{t('files.modified')}</th>
                    <th className="w-32 px-2 py-2" />
                  </tr>
                </thead>
                <tbody>
                  {entries.map((entry) => {
                    const isArchive = !entry.isDir && ARCHIVE_RE.test(entry.name)
                    // Row actions: hover-revealed on desktop pointers, but ALWAYS
                    // visible below lg (touch devices have no hover to reveal them).
                    const actionCls =
                      'pressable rounded-lg p-1.5 text-muted hover:bg-elevated/70 hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40'
                    const active = detail?.entry.name === entry.name && detail?.entry.isDir === entry.isDir
                    return (
                      <tr
                        key={entry.name}
                        onClick={() => setDetail({ entry, dir })}
                        className={cx(
                          'group cursor-pointer border-b border-line/50 last:border-0',
                          active ? 'bg-accent/10' : 'hover:bg-elevated/40',
                        )}
                      >
                        <td className="px-3 py-2" onClick={(e) => e.stopPropagation()}>
                          <Checkbox checked={selected.has(entry.name)} onChange={() => toggle(entry.name)} aria-label={entry.name} />
                        </td>
                        <td className="px-2 py-2">
                          <button
                            onClick={(e) => {
                              e.stopPropagation()
                              if (entry.isDir) setDir(joinPath(dir, entry.name))
                              else void openEditor(entry.name)
                            }}
                            className="flex items-center gap-2 text-left hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
                          >
                            {entry.isDir ? (
                              <Folder size={15} className="shrink-0 text-accent/80" />
                            ) : isArchive ? (
                              <FileArchive size={15} className="shrink-0 text-warn/80" />
                            ) : imageMime(entry.name) ? (
                              <FileImage size={15} className="shrink-0 text-accent/80" />
                            ) : (
                              <FileIcon size={15} className="shrink-0 text-muted" />
                            )}
                            <span className="break-all">{entry.name}</span>
                          </button>
                        </td>
                        <td className="tabular whitespace-nowrap px-2 py-2 font-mono text-xs text-muted">{entry.isDir ? '—' : formatBytes(entry.size)}</td>
                        <td className="tabular hidden whitespace-nowrap px-2 py-2 font-mono text-xs text-muted sm:table-cell">{formatDateTime(entry.mtimeMs)}</td>
                        <td className="px-2 py-2" onClick={(e) => e.stopPropagation()}>
                          <div className="flex items-center justify-end gap-0.5 opacity-100 transition-opacity lg:opacity-0 lg:group-hover:opacity-100">
                            {!entry.isDir && (
                              <button title={t('files.edit')} aria-label={t('files.edit')} onClick={() => void openEditor(entry.name)} className={actionCls}>
                                <FilePen size={13} />
                              </button>
                            )}
                            {isArchive && mayWrite && !remote && (
                              <button
                                title={t('files.unzip')}
                                aria-label={t('files.unzip')}
                                disabled={busy}
                                onClick={() => void extractEntry(entry.name)}
                                className={`${actionCls} disabled:opacity-40`}
                              >
                                <Archive size={13} />
                              </button>
                            )}
                            {mayWrite && !remote && (
                              <>
                                <button
                                  title={t('common.rename')}
                                  aria-label={t('common.rename')}
                                  onClick={() => { setRenameFrom(entry.name); setNameInput(entry.name) }}
                                  className={actionCls}
                                >
                                  <Pencil size={13} />
                                </button>
                                <button
                                  title={t('files.copyTo')}
                                  aria-label={t('files.copyTo')}
                                  onClick={() => setTransfer({ mode: 'copy', name: entry.name })}
                                  className={actionCls}
                                >
                                  <CopyIcon size={13} />
                                </button>
                                <button
                                  title={t('files.moveTo')}
                                  aria-label={t('files.moveTo')}
                                  onClick={() => setTransfer({ mode: 'move', name: entry.name })}
                                  className={actionCls}
                                >
                                  <FolderInput size={13} />
                                </button>
                              </>
                            )}
                            <button title={t('common.download')} aria-label={t('common.download')} onClick={() => download(entry.name)} className={actionCls}>
                              <Download size={13} />
                            </button>
                            {mayWrite && (
                              <button
                                title={t('common.delete')}
                                aria-label={t('common.delete')}
                                onClick={() => { setSelected(new Set([entry.name])); setDeleteOpen(true) }}
                                className="pressable rounded-lg p-1.5 text-muted hover:bg-danger/20 hover:text-danger focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
                              >
                                <Trash2 size={13} />
                              </button>
                            )}
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Card>

        {/* Detail side panel (desktop) */}
        {detail && isLg && (
          <Card className="fade-in-up p-4">
            <div className="mb-3 flex items-center justify-between">
              <span className="microlabel">{t('files.details')}</span>
              <IconButton size="sm" label={t('common.close')} onClick={() => setDetail(null)}>
                <X size={13} />
              </IconButton>
            </div>
            <FileDetail
              entry={detail.entry}
              dir={detail.dir}
              preview={preview}
              mayWrite={mayWrite}
              remote={remote}
              busy={busy}
              onDownload={() => download(detail.entry.name)}
              onRename={() => { setRenameFrom(detail.entry.name); setNameInput(detail.entry.name) }}
              onCopy={() => setTransfer({ mode: 'copy', name: detail.entry.name })}
              onMove={() => setTransfer({ mode: 'move', name: detail.entry.name })}
              onExtract={() => void extractEntry(detail.entry.name)}
              onDelete={() => { setSelected(new Set([detail.entry.name])); setDeleteOpen(true) }}
            />
          </Card>
        )}
      </div>

      {/* Detail bottom sheet (below lg) */}
      <Modal open={detailOpen && !isLg} onClose={() => setDetail(null)} title={t('files.details')}>
        {detail && (
          <FileDetail
            entry={detail.entry}
            dir={detail.dir}
            preview={preview}
            mayWrite={mayWrite}
            remote={remote}
            busy={busy}
            onDownload={fromDetail(() => download(detail.entry.name))}
            onRename={fromDetail(() => { setRenameFrom(detail.entry.name); setNameInput(detail.entry.name) })}
            onCopy={fromDetail(() => setTransfer({ mode: 'copy', name: detail.entry.name }))}
            onMove={fromDetail(() => setTransfer({ mode: 'move', name: detail.entry.name }))}
            onExtract={fromDetail(() => void extractEntry(detail.entry.name))}
            onDelete={fromDetail(() => { setSelected(new Set([detail.entry.name])); setDeleteOpen(true) })}
          />
        )}
      </Modal>

      {/* Editor modal */}
      <Modal
        open={editorPath !== null}
        onClose={() => setEditorPath(null)}
        title={<span className="font-mono text-sm">{editorPath}</span>}
        wide
        dirty={editorContent !== editorOriginal}
        footer={
          <>
            <Button variant="ghost" onClick={() => setEditorPath(null)}>{t('common.cancel')}</Button>
            {mayWrite && (
              <Button variant="primary" onClick={() => void saveEditor()} loading={editorSaving} disabled={editorMeta?.binary}>
                {t('common.save')}
              </Button>
            )}
          </>
        }
      >
        {editorMeta === null && <Spinner />}
        {editorMeta?.binary && <p className="text-sm text-warn">{t('files.binary')}</p>}
        {editorMeta && !editorMeta.binary && (
          <>
            {editorMeta.truncated && <p className="mb-2 text-xs text-warn">{t('files.tooLarge')}</p>}
            <TextArea
              value={editorContent}
              onChange={(e) => setEditorContent(e.target.value)}
              spellCheck={false}
              className="min-h-[50vh] font-mono text-xs leading-relaxed"
            />
          </>
        )}
      </Modal>

      {/* New file */}
      <Modal
        open={newFileOpen}
        onClose={() => setNewFileOpen(false)}
        title={t('files.newFile')}
        footer={
          <Button
            variant="primary"
            disabled={!nameInput.trim()}
            loading={busy}
            onClick={() =>
              void run(async () => {
                await api.put(`/api/servers/${server.id}/files/content`, { path: joinPath(dir, nameInput.trim()), content: '' })
                setNewFileOpen(false)
              })
            }
          >
            {t('common.create')}
          </Button>
        }
      >
        <Field label={t('files.fileName')}>
          <Input value={nameInput} onChange={(e) => setNameInput(e.target.value)} autoFocus placeholder="e.g. server.properties" />
        </Field>
      </Modal>

      {/* New folder */}
      <Modal
        open={newFolderOpen}
        onClose={() => setNewFolderOpen(false)}
        title={t('files.newFolder')}
        footer={
          <Button
            variant="primary"
            disabled={!nameInput.trim()}
            loading={busy}
            onClick={() =>
              void run(async () => {
                await api.post(`/api/servers/${server.id}/files/mkdir`, { path: joinPath(dir, nameInput.trim()) })
                setNewFolderOpen(false)
              })
            }
          >
            {t('common.create')}
          </Button>
        }
      >
        <Field label={t('files.folderName')}>
          <Input value={nameInput} onChange={(e) => setNameInput(e.target.value)} autoFocus placeholder="e.g. plugins" />
        </Field>
      </Modal>

      {/* Rename */}
      <Modal
        open={renameFrom !== null}
        onClose={() => setRenameFrom(null)}
        title={`${t('common.rename')}: ${renameFrom ?? ''}`}
        footer={
          <Button
            variant="primary"
            disabled={!nameInput.trim() || nameInput === renameFrom}
            loading={busy}
            onClick={() =>
              void run(async () => {
                const newName = nameInput.trim()
                await api.post(`/api/servers/${server.id}/files/rename`, {
                  path: joinPath(dir, renameFrom!),
                  newName,
                })
                // Keep the detail panel on the renamed entry across the reload.
                setDetail((prev) =>
                  prev && prev.dir === dir && prev.entry.name === renameFrom
                    ? { dir, entry: { ...prev.entry, name: newName } }
                    : prev,
                )
                setRenameFrom(null)
              })
            }
          >
            {t('common.rename')}
          </Button>
        }
      >
        <Field label={t('files.renameTo')}>
          <Input value={nameInput} onChange={(e) => setNameInput(e.target.value)} autoFocus />
        </Field>
      </Modal>

      {/* Create archive from selection */}
      <Modal
        open={zipOpen}
        onClose={() => setZipOpen(false)}
        title={t('files.createArchive')}
        footer={
          <Button
            variant="primary"
            disabled={!nameInput.trim()}
            loading={busy}
            onClick={() =>
              void run(async () => {
                await api.post(`/api/servers/${server.id}/files/zip`, {
                  paths: [...selected].map((n) => joinPath(dir, n)),
                  archiveName: nameInput.trim(),
                })
                setZipOpen(false)
              })
            }
          >
            {t('files.createArchive')}
          </Button>
        }
      >
        <Field label={t('files.zipName')}>
          <Input value={nameInput} onChange={(e) => setNameInput(e.target.value)} autoFocus />
        </Field>
      </Modal>

      {/* Copy-to / Move-to directory picker */}
      <DirPickerModal
        open={transfer !== null}
        title={
          transfer ? t(transfer.mode === 'copy' ? 'files.pickerCopyTitle' : 'files.pickerMoveTitle', { name: transfer.name }) : ''
        }
        serverId={server.id}
        startDir={dir}
        busy={busy}
        onClose={() => setTransfer(null)}
        onSelect={submitTransfer}
      />

      {/* Delete confirm */}
      <ConfirmModal
        open={deleteOpen}
        onClose={() => setDeleteOpen(false)}
        onConfirm={() =>
          void run(async () => {
            await api.post(`/api/servers/${server.id}/files/delete`, { paths: [...selected].map((n) => joinPath(dir, n)) })
            setDeleteOpen(false)
          })
        }
        message={t('files.deleteConfirm', { count: selected.size })}
        danger
        loading={busy}
        confirmLabel={t('common.delete')}
      />
    </div>
  )
}

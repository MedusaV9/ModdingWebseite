import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Copy, Info } from 'lucide-react'
import { api, ApiError } from '../../api/client.ts'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Button, Field, Input, Toggle } from '../../components/ui.tsx'
import { Modal } from '../../components/Modal.tsx'
import { useServer } from './ServerDetail.tsx'

/**
 * Clone dialog for the server detail header. Mount-on-open so every opening
 * starts from fresh defaults (name, copy toggle, source port values).
 */
export function CloneModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  if (!open) return null
  return <CloneForm onClose={onClose} />
}

function CloneForm({ onClose }: { onClose: () => void }) {
  const t = useT()
  const toast = useToast()
  const navigate = useNavigate()
  const { server } = useServer()
  const portVars = useMemo(() => (server.blueprint?.variables ?? []).filter((v) => v.isPort), [server.blueprint])
  const [name, setName] = useState(() => `${server.name} (copy)`.slice(0, 60))
  const [copyFiles, setCopyFiles] = useState(true)
  const [ports, setPorts] = useState<Record<string, string>>(() => {
    const init: Record<string, string> = {}
    for (const v of (server.blueprint?.variables ?? []).filter((p) => p.isPort))
      init[v.key] = String(server.variables[v.key] ?? v.default)
    return init
  })
  const [busy, setBusy] = useState(false)

  const submit = async () => {
    setBusy(true)
    try {
      const variables: Record<string, number> = {}
      for (const [key, value] of Object.entries(ports)) {
        const n = Number(value)
        if (value !== '' && Number.isFinite(n)) variables[key] = n
      }
      const res = await api.post<{ server: { id: string } }>(`/api/servers/${server.id}/clone`, {
        name,
        copyFiles,
        variables,
      })
      toast('success', t('clone.success'))
      onClose()
      navigate(`/servers/${res.server.id}`)
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
      setBusy(false)
    }
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={t('clone.title')}
      footer={
        // Full-width primary below sm: — a lone small button leaves the
        // bottom-sheet footer row mostly empty (sheet-footer convention).
        <Button variant="primary" className="w-full sm:w-auto" onClick={() => void submit()} loading={busy} disabled={!name.trim()}>
          <Copy size={14} />
          {t('clone.action')}
        </Button>
      }
    >
      <div className="space-y-4">
        <Field label={t('clone.name')}>
          <Input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} autoFocus />
        </Field>
        <div className="space-y-1.5">
          <Toggle checked={copyFiles} onChange={setCopyFiles} label={t('clone.copyFiles')} />
          <p className="text-xs leading-snug text-muted/80">{t('clone.copyFilesHint')}</p>
        </div>
        {portVars.length > 0 && (
          <div className="space-y-3">
            {/* Info message (accent tint, same recipe as ConsoleTab's install
                banners) — must not read like a disabled input between fields. */}
            <p className="glass-subtle flex items-start gap-2 rounded-xl border-accent/30 bg-accent/10 px-3.5 py-2.5 text-xs leading-relaxed text-accent">
              <Info size={14} aria-hidden className="mt-0.5 shrink-0" />
              <span>{t('clone.portsHint')}</span>
            </p>
            <div className="grid gap-4 sm:grid-cols-2">
              {portVars.map((v) => (
                <Field key={v.key} label={v.label}>
                  <Input
                    type="number"
                    value={ports[v.key] ?? ''}
                    min={v.min}
                    max={v.max}
                    onChange={(e) => setPorts((prev) => ({ ...prev, [v.key]: e.target.value }))}
                  />
                </Field>
              ))}
            </div>
          </div>
        )}
      </div>
    </Modal>
  )
}

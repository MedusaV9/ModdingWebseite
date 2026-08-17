/**
 * Runtime selection (host process vs docker container) + docker settings
 * fields — shared between the create wizard and the server settings tab.
 */
import { useState } from 'react'
import { Check, Container, Cpu } from 'lucide-react'
import type { Blueprint, ServerDockerSettings, ServerRuntime } from '../api/types.ts'
import { useT } from '../i18n/index.tsx'
import { Field, Input, Select, cx } from './ui.tsx'

export interface DockerFormValues {
  image: string
  memoryMb: string
  cpus: string
  networkMode: 'bridge' | 'host'
}

export function emptyDockerForm(settings?: ServerDockerSettings | null): DockerFormValues {
  return {
    image: settings?.image ?? '',
    memoryMb: settings?.memoryMb ? String(settings.memoryMb) : '',
    cpus: settings?.cpus ? String(settings.cpus) : '',
    networkMode: settings?.networkMode === 'host' ? 'host' : 'bridge',
  }
}

/** Convert form values into the API payload shape. */
export function dockerFormToPayload(form: DockerFormValues): ServerDockerSettings {
  return {
    image: form.image.trim() || null,
    memoryMb: form.memoryMb.trim() ? Number(form.memoryMb) : null,
    cpus: form.cpus.trim() ? Number(form.cpus) : null,
    networkMode: form.networkMode,
  }
}

const CUSTOM = '__custom__'

export function RuntimePicker({
  runtime,
  onRuntimeChange,
  dockerAvailable,
  dockerVersion,
  disabled,
  disabledHint,
}: {
  runtime: ServerRuntime
  onRuntimeChange: (r: ServerRuntime) => void
  dockerAvailable: boolean
  dockerVersion?: string | null
  disabled?: boolean
  disabledHint?: string
}) {
  const t = useT()
  const options: { id: ServerRuntime; icon: React.ReactNode; label: string; hint: string; enabled: boolean }[] = [
    { id: 'process', icon: <Cpu size={18} />, label: t('runtime.process'), hint: t('runtime.processHint'), enabled: true },
    {
      id: 'docker',
      icon: <Container size={18} />,
      label: t('runtime.docker'),
      hint: dockerAvailable
        ? t('runtime.dockerHint') + (dockerVersion ? ` · Docker ${dockerVersion}` : '')
        : t('runtime.dockerUnavailable'),
      enabled: dockerAvailable,
    },
  ]
  return (
    <div>
      <div className="grid gap-2 sm:grid-cols-2">
        {options.map((opt) => {
          const active = runtime === opt.id
          const clickable = opt.enabled && !disabled
          return (
            <button
              key={opt.id}
              type="button"
              onClick={() => clickable && onRuntimeChange(opt.id)}
              disabled={!clickable}
              aria-pressed={active}
              className={cx(
                'glass-subtle pressable relative flex items-start gap-3 rounded-xl p-3 pr-9 text-left',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                active && 'border-accent/60 bg-accent/10 ring-1 ring-accent/30',
                clickable && !active && 'hover:border-accent/40',
                !opt.enabled && 'opacity-45 saturate-50',
              )}
            >
              <span className={cx('mt-0.5 shrink-0 rounded-lg p-1.5', active ? 'bg-accent/20 text-accent' : 'bg-elevated/70 text-muted')}>
                {opt.icon}
              </span>
              <span className="min-w-0">
                <span className="block text-sm font-semibold">{opt.label}</span>
                <span className="mt-0.5 block text-[0.6875rem] leading-snug text-muted">{opt.hint}</span>
              </span>
              {active && (
                <span aria-hidden className="scale-in absolute right-2.5 top-2.5 rounded-full bg-accent p-0.5 text-onaccent">
                  <Check size={11} strokeWidth={3} />
                </span>
              )}
            </button>
          )
        })}
      </div>
      {disabled && disabledHint && <p className="mt-2 text-xs text-warn">{disabledHint}</p>}
    </div>
  )
}

export function DockerSettingsFields({
  blueprint,
  values,
  onChange,
}: {
  blueprint: Blueprint | null
  values: DockerFormValues
  onChange: (v: DockerFormValues) => void
}) {
  const t = useT()
  const curated = blueprint?.docker?.images ?? []
  const defaultImage = blueprint?.docker?.image ?? null
  const knownImages = [...new Set([...(defaultImage ? [defaultImage] : []), ...curated.map((i) => i.image)])]
  const isUnknownImage = values.image !== '' && !knownImages.includes(values.image)
  // Blueprints without a default image always need a free-text image.
  const [customMode, setCustomMode] = useState(isUnknownImage || !defaultImage)
  const showInput = customMode || isUnknownImage
  const selectValue = showInput ? CUSTOM : values.image

  return (
    <div className="grid gap-4 sm:grid-cols-2">
      <div className="sm:col-span-2">
        <Field label={t('runtime.image')} hint={!defaultImage && values.image.trim() === '' ? t('runtime.noImage') : undefined}>
          <div className="grid gap-2 sm:grid-cols-2">
            <Select
              value={selectValue}
              onChange={(e) => {
                const v = e.target.value
                if (v === CUSTOM) {
                  setCustomMode(true)
                } else {
                  setCustomMode(false)
                  onChange({ ...values, image: v })
                }
              }}
            >
              {defaultImage && (
                <option value="">
                  {defaultImage} {t('runtime.imageDefaultSuffix')}
                </option>
              )}
              {curated.map((entry) => (
                <option key={entry.image} value={entry.image}>
                  {entry.label} — {entry.image}
                </option>
              ))}
              <option value={CUSTOM}>{t('runtime.imageCustom')}</option>
            </Select>
            {showInput && (
              <Input
                value={values.image}
                onChange={(e) => onChange({ ...values, image: e.target.value })}
                placeholder={t('runtime.imageCustomPh')}
                spellCheck={false}
              />
            )}
          </div>
        </Field>
      </div>
      <Field label={t('runtime.memory')} hint={t('runtime.memoryHint')}>
        <Input
          type="number"
          min={128}
          value={values.memoryMb}
          onChange={(e) => onChange({ ...values, memoryMb: e.target.value })}
          placeholder="∞"
        />
      </Field>
      <Field label={t('runtime.cpus')} hint={t('runtime.cpusHint')}>
        <Input
          type="number"
          min={0.1}
          step={0.5}
          value={values.cpus}
          onChange={(e) => onChange({ ...values, cpus: e.target.value })}
          placeholder="∞"
        />
      </Field>
      <Field label={t('runtime.network')}>
        <Select value={values.networkMode} onChange={(e) => onChange({ ...values, networkMode: e.target.value as 'bridge' | 'host' })}>
          <option value="bridge">{t('runtime.networkBridge')}</option>
          <option value="host">{t('runtime.networkHost')}</option>
        </Select>
      </Field>
    </div>
  )
}

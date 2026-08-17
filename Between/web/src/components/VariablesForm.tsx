import { useMemo, useState } from 'react'
import type { Blueprint, BlueprintVariable } from '../api/types.ts'
import { cx, Field, Input, Select, Toggle } from './ui.tsx'
import { useT } from '../i18n/index.tsx'
import { ChevronDown } from 'lucide-react'

export type VarValues = Record<string, string | number | boolean>

export function defaultsFor(blueprint: Blueprint): VarValues {
  const out: VarValues = {}
  for (const v of blueprint.variables) out[v.key] = v.default
  return out
}

function VariableInput({
  variable,
  value,
  onChange,
}: {
  variable: BlueprintVariable
  value: string | number | boolean
  onChange: (v: string | number | boolean) => void
}) {
  switch (variable.type) {
    case 'boolean':
      return <Toggle checked={Boolean(value)} onChange={onChange} label={value ? 'on' : 'off'} />
    case 'number':
      return (
        <Input
          type="number"
          value={String(value)}
          min={variable.min}
          max={variable.max}
          onChange={(e) => onChange(e.target.value === '' ? '' : Number(e.target.value))}
        />
      )
    case 'enum':
      return (
        <Select value={String(value)} onChange={(e) => onChange(e.target.value)}>
          {variable.options?.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </Select>
      )
    case 'password':
      return <Input type="password" value={String(value)} onChange={(e) => onChange(e.target.value)} autoComplete="new-password" />
    default:
      return <Input value={String(value)} onChange={(e) => onChange(e.target.value)} />
  }
}

export function VariablesForm({
  blueprint,
  values,
  onChange,
}: {
  blueprint: Blueprint
  values: VarValues
  onChange: (values: VarValues) => void
}) {
  const t = useT()
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [basic, advanced] = useMemo(() => {
    const b: BlueprintVariable[] = []
    const a: BlueprintVariable[] = []
    for (const v of blueprint.variables) (v.advanced ? a : b).push(v)
    return [b, a]
  }, [blueprint])

  const set = (key: string, v: string | number | boolean) => onChange({ ...values, [key]: v })

  const renderVar = (v: BlueprintVariable) => (
    <Field
      key={v.key}
      label={
        <span className="normal-case tracking-normal">
          {v.label}
          {v.isPort && <span className="ml-1.5 rounded-full bg-accent/15 px-1.5 py-px text-[0.625rem] font-semibold text-accent">PORT</span>}
          {v.required && <span className="ml-1 text-danger">*</span>}
        </span>
      }
      hint={v.description}
    >
      <VariableInput variable={v} value={values[v.key] ?? v.default} onChange={(val) => set(v.key, val)} />
    </Field>
  )

  return (
    <div className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">{basic.map(renderVar)}</div>
      {advanced.length > 0 && (
        <div>
          <button
            type="button"
            onClick={() => setShowAdvanced((s) => !s)}
            aria-expanded={showAdvanced}
            className="pressable flex items-center gap-1.5 rounded-lg px-1 py-0.5 text-xs font-semibold uppercase tracking-wide text-muted hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
          >
            <ChevronDown size={14} className={cx('transition-transform duration-300 ease-out', !showAdvanced && '-rotate-90')} />
            {t('common.advanced')} ({advanced.length})
          </button>
          {/* Smooth expand via the grid-rows 0fr→1fr trick; `invisible` keeps
              collapsed fields out of the tab order (visibility transitions
              discretely, so the collapse still animates before hiding). */}
          <div
            aria-hidden={!showAdvanced}
            className={cx(
              'grid transition-[grid-template-rows,visibility] duration-300 ease-out',
              showAdvanced ? 'visible grid-rows-[1fr]' : 'invisible grid-rows-[0fr]',
            )}
          >
            <div className="min-h-0 overflow-hidden">
              <div className="grid gap-4 pt-3 sm:grid-cols-2">{advanced.map(renderVar)}</div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export class ApiError extends Error {
  status: number
  data?: Record<string, unknown>

  constructor(status: number, message: string, data?: Record<string, unknown>) {
    super(message)
    this.status = status
    this.data = data
  }
}

type Json = Record<string, unknown> | unknown[] | string | number | boolean | null

const listeners = new Set<() => void>()
export function onUnauthorized(fn: () => void): () => void {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

async function request<T>(method: string, path: string, body?: Json, opts: { emit401?: boolean } = {}): Promise<T> {
  const res = await fetch(path, {
    method,
    credentials: 'same-origin',
    headers: body !== undefined ? { 'content-type': 'application/json' } : undefined,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  let data: Record<string, unknown> = {}
  const text = await res.text()
  if (text) {
    try {
      data = JSON.parse(text) as Record<string, unknown>
    } catch {
      data = { error: text.slice(0, 300) }
    }
  }
  if (!res.ok) {
    if (res.status === 401 && opts.emit401 !== false) for (const fn of listeners) fn()
    throw new ApiError(res.status, String(data.error ?? `HTTP ${res.status}`), data)
  }
  return data as T
}

export const api = {
  get: <T>(path: string, opts?: { emit401?: boolean }) => request<T>('GET', path, undefined, opts),
  post: <T>(path: string, body?: Json, opts?: { emit401?: boolean }) => request<T>('POST', path, body, opts),
  put: <T>(path: string, body?: Json) => request<T>('PUT', path, body),
  patch: <T>(path: string, body?: Json) => request<T>('PATCH', path, body),
  del: <T>(path: string, body?: Json) => request<T>('DELETE', path, body),
}

/** Streaming upload with progress (XHR because fetch upload progress is not portable). */
export function uploadFile(
  url: string,
  file: File,
  onProgress?: (pct: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.open('PUT', url)
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress(Math.round((e.loaded / e.total) * 100))
    }
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve()
      else {
        try {
          reject(new ApiError(xhr.status, String(JSON.parse(xhr.responseText).error ?? `HTTP ${xhr.status}`)))
        } catch {
          reject(new ApiError(xhr.status, `HTTP ${xhr.status}`))
        }
      }
    }
    xhr.onerror = () => reject(new ApiError(0, 'network error during upload'))
    xhr.send(file)
  })
}

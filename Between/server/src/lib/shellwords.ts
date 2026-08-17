/**
 * Tokenize a command line string into argv, respecting single/double quotes
 * and backslash escapes. Used to spawn game servers without a shell (safer,
 * and identical behavior on Linux and Windows).
 */
export function tokenize(command: string): string[] {
  const args: string[] = []
  let current = ''
  let inSingle = false
  let inDouble = false
  let hasToken = false

  for (let i = 0; i < command.length; i++) {
    const ch = command[i]
    if (inSingle) {
      if (ch === "'") inSingle = false
      else current += ch
      continue
    }
    if (inDouble) {
      if (ch === '"') inDouble = false
      else if (ch === '\\' && (command[i + 1] === '"' || command[i + 1] === '\\')) {
        current += command[++i]
      } else current += ch
      continue
    }
    if (ch === "'") {
      inSingle = true
      hasToken = true
    } else if (ch === '"') {
      inDouble = true
      hasToken = true
    } else if (ch === '\\' && i + 1 < command.length) {
      current += command[++i]
      hasToken = true
    } else if (/\s/.test(ch)) {
      if (hasToken || current.length > 0) {
        args.push(current)
        current = ''
        hasToken = false
      }
    } else {
      current += ch
      hasToken = true
    }
  }
  if (hasToken || current.length > 0) args.push(current)
  return args
}

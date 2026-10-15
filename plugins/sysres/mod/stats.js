// Pure parsers, formatters and layout for the band; no mods API calls.

const WARN = 70
const ALERT = 90
const SIZE = /^\s*(\d+(?:\.\d+)?)\s*([kKmM]?)\s*$/

// Busy and total jiffies from the aggregate `cpu` line of /proc/stat; iowait counts as idle.
export function cpuTimes(procStat) {
  const fields = procStat.split('\n')[0].trim().split(/\s+/).slice(1, 9).map(Number)
  const total = fields.reduce((a, b) => a + b, 0)
  return { busy: total - fields[3] - fields[4], total }
}

export function cpuPercent(prev, cur) {
  const total = cur.total - prev.total
  if (!(total > 0)) return 0
  return Math.min(100, Math.max(0, Math.round(((cur.busy - prev.busy) / total) * 100)))
}

// Bytes in use as `free` counts them (total less available), or null when the kernel lacks them.
export function memory(meminfo) {
  const kb = {}
  for (const line of meminfo.split('\n')) {
    const m = /^(\w+):\s+(\d+)/.exec(line)
    if (m) kb[m[1]] = Number(m[2]) * 1024
  }
  if (kb.MemTotal === undefined || kb.MemAvailable === undefined) return null
  return {
    used: kb.MemTotal - kb.MemAvailable,
    total: kb.MemTotal,
    swapUsed: (kb.SwapTotal ?? 0) - (kb.SwapFree ?? 0),
    swapTotal: kb.SwapTotal ?? 0,
  }
}

// `df -B1 --output=source,size,used,avail,target` rows after the header. The target comes last
// so a mount path with spaces stays whole; one row per source device, so btrfs subvolumes
// mounted from the same device count once.
export function disks(dfOut) {
  const seen = new Set()
  const rows = []
  for (const line of dfOut.trim().split('\n').slice(1)) {
    const [source, size, used, avail, ...target] = line.trim().split(/\s+/)
    const d = { source, target: target.join(' '), size: Number(size), used: Number(used), avail: Number(avail) }
    if (!(d.size > 0) || Number.isNaN(d.used + d.avail) || seen.has(source)) continue
    seen.add(source)
    rows.push(d)
  }
  return rows
}

// Use% as df prints it: used over what non-root users can reach, rounded up.
export function diskPercent(d) {
  const reach = d.used + d.avail
  return reach > 0 ? Math.ceil((d.used / reach) * 100) : 0
}

// Tokens from 500000, "500000", "500k" or "1M"; a bare 100-1000 means thousands (as /autocompact takes it).
export function parseSize(value) {
  if (typeof value === 'boolean' || value === null || value === undefined) return null
  const m = SIZE.exec(String(value))
  if (!m) return null
  let n = Number(m[1])
  const suffix = m[2].toLowerCase()
  if (suffix === 'k' || (!suffix && n >= 100 && n <= 1000)) n *= 1000
  else if (suffix === 'm') n *= 1_000_000
  return n > 0 ? Math.floor(n) : null
}

// The auto-compact window: the environment's plain count, else the settings value, capped at the model's window.
export function compactWindow(envValue, settingValue, modelWindow) {
  const plain = String(envValue ?? '').trim()
  const env = /^\d+$/.test(plain) && Number(plain) > 0 ? Number(plain) : null
  const window = env ?? parseSize(settingValue)
  if (modelWindow && (window === null || window > modelWindow)) return modelWindow
  return window
}

export function gib(bytes) {
  return (bytes / 2 ** 30).toFixed(1)
}

export function tokens(n) {
  if (n >= 1_000_000) return `${+(n / 1_000_000).toFixed(1)}M`
  return `${Math.round(n / 1000)}k`
}

export function share(used, total) {
  return total > 0 ? Math.round((used / total) * 100) : 0
}

// A theme key for a percentage, or undefined below the warning level.
export function level(percent) {
  return percent >= ALERT ? 'error' : percent >= WARN ? 'warning' : undefined
}

// shortcut: binary GiB figures under a GB label, as Task Manager and the VRAM box print them.
const size = (used, total) => ` ${gib(used)}/${Math.round(total / 2 ** 30)} GB`

// The band as groups shaped LABEL PERCENT [detail], so the eye can run along the percentages:
// parts { text, role }, where `label` and `detail` draw muted and `value` (the percentage) bold in
// the text colour, or in the group's colour once it reaches the warning level. Groups are in
// reading order; `drop` ranks which go first when the row is too narrow (higher drops first).
export function groups(s) {
  const out = []
  const g = (key, label, percent, drop, detail) =>
    out.push({
      key,
      color: level(percent),
      drop,
      parts: [
        { text: `${label} `, role: 'label' },
        { text: `${percent}%`, role: 'value' },
        ...(detail ? [{ text: detail, role: 'detail' }] : []),
      ],
    })
  g('cpu', 'CPU', s.cpu, 0)
  if (s.mem) g('ram', 'RAM', share(s.mem.used, s.mem.total), 1, size(s.mem.used, s.mem.total))
  if (s.gpu) {
    g('gpu', 'GPU', s.gpu.busy, 2)
    g('vram', 'VRAM', share(s.gpu.vramUsed, s.gpu.vramTotal), 3, size(s.gpu.vramUsed, s.gpu.vramTotal))
  }
  return out
}

// "claude-opus-5-5[1m]" or "opus" as /model shows it, to "Opus 5.5" or "Opus"; anything else as given.
export function modelName(model) {
  const id = String(model ?? '').replace(/\[.*\]$/, '')
  // version parts are one or two digits, so a date suffix (claude-sonnet-4-20250514) is not read as one
  const m = /(opus|sonnet|haiku|fable)(?:-(\d{1,2})(?![\d])(?:-(\d{1,2})(?![\d]))?)?/i.exec(id)
  if (!m) return id
  const family = m[1][0].toUpperCase() + m[1].slice(1).toLowerCase()
  return m[2] ? `${family} ${m[2]}${m[3] ? `.${m[3]}` : ''}` : family
}

export function contextGroup(ctx) {
  if (!ctx) return null
  const name = [ctx.model && modelName(ctx.model), ctx.effort].filter(Boolean).join(' ')
  const model = name ? [{ text: `${name.toUpperCase()}${SEPARATOR}`, role: 'label' }] : []
  if (ctx.tokens === undefined || !(ctx.window > 0)) {
    return { key: 'ctx', color: undefined, drop: -1, parts: [...model, { text: 'CTX ', role: 'label' }, { text: '—', role: 'label' }] }
  }
  const p = share(ctx.tokens, ctx.window)
  return {
    key: 'ctx',
    color: level(p),
    drop: -1,
    parts: [
      ...model,
      { text: 'CTX ', role: 'label' },
      { text: `${p}%`, role: 'value' },
      { text: ` ${tokens(ctx.tokens)}/${tokens(ctx.window)}`, role: 'detail' },
    ],
  }
}

export const SEPARATOR = '   '
const GAP = 4 // least space between the resources and the context figure

export function width(group) {
  return group.parts.reduce((n, p) => n + p.text.length, 0)
}

// Drops the lowest-ranked resource groups until the row fits `columns`; the context figure stays.
export function fit(left, right, columns) {
  const kept = [...left]
  const total = () =>
    kept.reduce((n, g) => n + width(g), 0) +
    Math.max(0, kept.length - 1) * SEPARATOR.length +
    (right ? GAP + width(right) : 0)
  while (kept.length > 1 && total() > columns) {
    const worst = kept.reduce((a, b) => (b.drop > a.drop ? b : a))
    kept.splice(kept.indexOf(worst), 1)
  }
  return kept
}

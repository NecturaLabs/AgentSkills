import {
  SEPARATOR,
  compactWindow,
  contextGroup,
  cpuPercent,
  cpuTimes,
  diskPercent,
  disks,
  fit,
  gib,
  groups,
  memory,
  share,
} from './stats.js'

const TICK_MS = 2000
const SETTINGS_EVERY = 15 // ticks between settings reads

let gpu = null // { dir, vramTotal } of the amdgpu device with the most VRAM, found once per load
let prevCpu = null
let sample = null // the latest { cpu, mem, gpu, ctx }, drawn in the band
let drawn = '' // the sample last drawn, so an unchanged one asks for no redraw
let settingWindow = null
let effortSettings = {} // effortLevel, and modelSettings.<model>.effortLevel per model
let effort = null // what the main loop's last request was sent with
let envWindow
let ticks = 0

// shortcut: amdgpu sysfs only; NVIDIA or Intel GPUs show no GPU segment until they get a reader.
async function findGpu($) {
  let best = null
  let cards = []
  try {
    cards = await $.fs.list('/sys/class/drm')
  } catch {
    return null
  }
  for (const card of cards) {
    if (!/^card\d+$/.test(card.name)) continue
    const dir = `/sys/class/drm/${card.name}/device`
    try {
      const vramTotal = Number(await $.fs.read(`${dir}/mem_info_vram_total`))
      if (vramTotal > (best?.vramTotal ?? 0)) best = { dir, vramTotal }
    } catch {
      // not an amdgpu device
    }
  }
  return best
}

async function readGpu($) {
  if (!gpu) return null
  try {
    return {
      busy: Number(await $.fs.read(`${gpu.dir}/gpu_busy_percent`)),
      vramUsed: Number(await $.fs.read(`${gpu.dir}/mem_info_vram_used`)),
      vramTotal: gpu.vramTotal,
    }
  } catch {
    return null
  }
}

async function gpuTemp($) {
  try {
    const hwmon = (await $.fs.list(`${gpu.dir}/hwmon`))[0]
    return Math.round(Number(await $.fs.read(`${gpu.dir}/hwmon/${hwmon.name}/temp1_input`)) / 1000)
  } catch {
    return null
  }
}

async function readSettings($) {
  try {
    const settings = await $.settings.read()
    settingWindow = settings.autoCompactWindow
    effortSettings = { level: settings.effortLevel, perModel: settings.modelSettings ?? {} }
    envWindow = await $.env.get('CLAUDE_CODE_AUTO_COMPACT_WINDOW')
  } catch {
    // keep the last values
  }
}

async function readContext($) {
  try {
    const { context } = await $.session.usage()
    let model = null
    try {
      model = await $.session.model()
    } catch {
      // the figure still shows without the model
    }
    return { model, tokens: context.tokens, window: compactWindow(envWindow, settingWindow, context.window) }
  } catch {
    return null
  }
}

async function tick($) {
  if (ticks++ % SETTINGS_EVERY === 0) await readSettings($)
  const cur = cpuTimes(await $.fs.read('/proc/stat'))
  const cpu = prevCpu ? cpuPercent(prevCpu, cur) : null
  prevCpu = cur
  if (cpu === null) return
  let mem = null
  try {
    mem = memory(await $.fs.read('/proc/meminfo'))
  } catch {
    // the band shows the rest
  }
  const next = { cpu, mem, gpu: await readGpu($), ctx: await readContext($) }
  sample = next
  const key = JSON.stringify(next)
  if (key !== drawn) {
    drawn = key
    $.ui.invalidate('ui.render')
  }
}

async function safeTick($) {
  try {
    await tick($)
  } catch {
    // /proc unreadable: the band stays as last drawn
  }
}

async function report($) {
  const lines = []
  let cpu = sample?.cpu
  if (cpu === undefined) {
    const before = cpuTimes(await $.fs.read('/proc/stat'))
    await $.clock.sleep(250)
    cpu = cpuPercent(before, cpuTimes(await $.fs.read('/proc/stat')))
  }
  let load = ''
  try {
    load = ` · load ${(await $.fs.read('/proc/loadavg')).split(' ').slice(0, 3).join(' ')}`
  } catch {
    // no load average on this kernel
  }
  lines.push(`CPU   ${cpu}%${load}`)
  let mem = null
  try {
    mem = memory(await $.fs.read('/proc/meminfo'))
  } catch {
    // no meminfo; the RAM line is left out
  }
  if (mem) {
    lines.push(
      `RAM   ${gib(mem.used)} / ${gib(mem.total)} GB (${share(mem.used, mem.total)}%)` +
        (mem.swapTotal > 0 ? ` · swap ${gib(mem.swapUsed)} / ${gib(mem.swapTotal)} GB` : ''),
    )
  }
  const g = await readGpu($)
  if (g) {
    const temp = await gpuTemp($)
    lines.push(
      `GPU   ${g.busy}% · VRAM ${gib(g.vramUsed)} / ${gib(g.vramTotal)} GB` + (temp !== null ? ` · ${temp}°C` : ''),
    )
  }
  try {
    const out = await $.process.run(['df', '-B1', '--output=source,size,used,avail,target', '-x', 'tmpfs', '-x', 'devtmpfs', '-x', 'efivarfs', '-x', 'overlay'], {
      timeoutMs: 5000,
    })
    if (out.exitCode !== 0) throw new Error(out.stderr)
    for (const d of disks(out.stdout)) {
      lines.push(`Disk  ${d.target} ${gib(d.used)} / ${gib(d.size)} GB (${diskPercent(d)}%)`)
    }
  } catch {
    lines.push('Disk  df failed')
  }
  return lines.join('\n')
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    try {
      await $.command.register({ name: 'sysres', description: 'Show CPU, memory, GPU and disk use', immediate: true })
    } catch {
      // registration refused; the band still works without /sysres
    }
    gpu = await findGpu($)
    // Nothing draws outside a person's session, so -p runs and the SDK sample nothing.
    if (e.isInteractive) {
      safeTick($)
      $.clock.every(TICK_MS, () => safeTick($))
    }
    return next(e)
  })

  // Observe only: note the main loop's effort and pass the request on unchanged.
  on('turn.step', async function* ($, e, next) {
    if (!e.agentId && e.effort !== undefined && e.effort !== effort) {
      effort = e.effort
      $.ui.invalidate('ui.render')
    }
    return yield* next(e)
  })

  on('command.run', { command: 'sysres' }, async ($) => ({ text: await report($) }))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!sample || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const id = String(sample.ctx?.model ?? '').replace(/\[.*\]$/, '')
    const configured = effortSettings.perModel?.[id]?.effortLevel ?? effortSettings.level
    const right = sample.ctx && contextGroup({ ...sample.ctx, effort: effort ?? configured })
    const left = fit(groups(sample), right, e.props.bodyColumns)
    const part = (g, p, i) =>
      p.role === 'value'
        ? Text({ key: `${g.key}-${i}`, bold: true, color: g.color ?? 'text', children: [p.text] })
        : Text({ key: `${g.key}-${i}`, color: 'inactive', children: [p.text] })
    const draw = (g) => Box({ key: g.key, flexDirection: 'row', flexShrink: 0, children: g.parts.map((p, i) => part(g, p, i)) })
    const row = []
    left.forEach((g, i) => {
      if (i > 0) row.push(Text({ children: [SEPARATOR] }))
      row.push(draw(g))
    })
    const ours = Box({
      flexDirection: 'row',
      justifyContent: 'space-between',
      width: e.props.bodyColumns,
      children: [Box({ flexDirection: 'row', children: row }), ...(right ? [draw(right)] : [])],
    })
    const theirs = await next(e)
    return theirs ? Box({ flexDirection: 'column', children: [ours, theirs] }) : ours
  })
}

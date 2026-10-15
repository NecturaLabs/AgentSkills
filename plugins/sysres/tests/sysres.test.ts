import { expect, mock, test } from 'claude-code/testing'
import { modelName, compactWindow, cpuPercent, cpuTimes, diskPercent, disks, fit, groups, contextGroup, level, memory, parseSize } from '../mod/stats.js'

const GiB = 2 ** 30
const GPU = '/sys/class/drm/card1/device'

// cpu busy 25 of 100 jiffies between the two samples
const CPU = ['cpu  100 0 100 700 100 0 0 0 0 0\n', 'cpu  120 0 105 770 105 0 0 0 0 0\n']

const DF_ALL =
  'Filesystem 1B-blocks Used Avail Mounted on\n' +
  `/dev/mapper/root ${100 * GiB} ${33 * GiB} ${67 * GiB} /\n` +
  `/dev/mapper/root ${100 * GiB} ${33 * GiB} ${67 * GiB} /home\n` +
  `/dev/sdb2 ${10 * GiB} ${5 * GiB} ${5 * GiB} /work\n`

// `own` names stubs the test registers itself.
type Machine = { gpu?: boolean; hwmon?: boolean; df?: 'ok' | 'fail' | 'throw'; cpu?: string[]; own?: string[]; env?: string; tokens?: number; settings?: object }

// A machine with an integrated card0 (2 GiB) and a discrete card1 (20 GiB), as /proc and /sys show it.
function stub(onReal: any, m: Machine = {}) {
  const on = (name: string, fn: any) => (m.own?.includes(name) ? undefined : onReal(name, fn))
  const cpu = m.cpu ?? CPU
  let statReads = 0
  const files: Record<string, () => string> = {
    '/proc/stat': () => cpu[Math.min(statReads++, cpu.length - 1)],
    '/proc/meminfo': () =>
      `MemTotal: ${64 * 1024 * 1024} kB\nMemFree: 1 kB\nMemAvailable: ${48 * 1024 * 1024} kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n`,
    '/proc/loadavg': () => '1.50 0.75 0.25 2/900 1234\n',
  }
  const dirs: Record<string, string[]> = { '/sys/class/drm': ['card0', 'card0-DP-1', 'renderD128', 'version'] }
  if (m.gpu !== false) {
    dirs['/sys/class/drm'].push('card1')
    files['/sys/class/drm/card0/device/mem_info_vram_total'] = () => String(2 * GiB)
    files[`${GPU}/mem_info_vram_total`] = () => String(20 * GiB)
    files[`${GPU}/mem_info_vram_used`] = () => String(19 * GiB)
    files[`${GPU}/gpu_busy_percent`] = () => '75\n'
    if (m.hwmon !== false) {
      dirs[`${GPU}/hwmon`] = ['hwmon2']
      files[`${GPU}/hwmon/hwmon2/temp1_input`] = () => '45000\n'
    }
  }
  on('fs.read', ($: any, e: any) => (files[e.path] ? { value: files[e.path]() } : { deny: `ENOENT ${e.path}` }))
  on('fs.list', ($: any, e: any) =>
    dirs[e.path] ? { value: dirs[e.path].map((name) => ({ name, kind: 'directory', size: 0, isLink: true })) } : { deny: 'ENOENT' },
  )
  on('process.run', ($: any, e: any) => {
    if (m.df === 'throw') return { deny: 'df is not installed' }
    if (m.df === 'fail') return { value: { exitCode: 1, stdout: '', stderr: 'df: error' } }
    return { value: { exitCode: 0, stdout: DF_ALL, stderr: '' } }
  })
  const tokens = 'tokens' in m ? m.tokens : 400_000
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens, window: 1_000_000 }, rateLimits: [] } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('settings.read', () => ({ value: m.settings ?? { autoCompactWindow: 500000, effortLevel: 'high' } }))
  on('env.get', () => ({ value: m.env }))
  on('command.register', () => ({ value: undefined }))
  on('session.start', () => ({ cwd: '/work/project' }))
  // What Claude Code itself draws in the band
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['drawn by Claude Code'] }))
}

const band = (bodyColumns = 160, hasSurvey = false) =>
  ({
    plugin: 'sysres',
    component: 'AbovePrompt',
    surface: 'terminal',
    viewport: { columns: bodyColumns, rows: 40 },
    props: { hasSurvey, isWorking: false, maxRows: 10, bodyColumns, scroll: { offset: 0, bodyRows: 10 }, view: {} },
  }) as const

const START = { surface: 'terminal', isInteractive: true, cwd: '/work/project' } as const

async function started($: any, on: any, m: Machine = {}) {
  stub(on, m)
  const clock = mock.clock(on)
  await $.session.start(START)
  await clock.advance(2000)
  return clock
}

test('cpu share counts iowait as idle and stays within 0-100', () => {
  expect(cpuPercent(cpuTimes(CPU[0]), cpuTimes(CPU[1]))).toBe(25)
  expect(cpuPercent(cpuTimes(CPU[0]), cpuTimes(CPU[0]))).toBe(0)
  // a counter that went backwards
  expect(cpuPercent(cpuTimes(CPU[1]), cpuTimes('cpu  0 0 0 2000 0 0 0 0\n'))).toBe(0)
})

test('memory needs MemTotal and MemAvailable', () => {
  expect(memory('MemTotal: 10 kB\n')).toBeNull()
  expect(memory('MemTotal: 10 kB\nMemAvailable: 4 kB\n')).toEqual({ used: 6144, total: 10240, swapUsed: 0, swapTotal: 0 })
})

test('df rows: one per device, mount paths with spaces kept, Use% as df rounds it', () => {
  expect(disks(DF_ALL).map((d) => d.target)).toEqual(['/', '/work'])
  const usb = disks('h\n/dev/sdc1 1000 500 400 /run/media/u/My Passport\n')[0]
  expect(usb.target).toBe('/run/media/u/My Passport')
  // 500 of the 900 reachable bytes is 55.6%, which df prints as 56%
  expect(diskPercent(usb)).toBe(56)
})

test('compact window: environment, then settings, capped at the model window', () => {
  expect(parseSize('500k')).toBe(500000)
  expect(parseSize('1M')).toBe(1000000)
  expect(parseSize(400)).toBe(400000)
  expect(compactWindow(undefined, 500000, 1_000_000)).toBe(500000)
  expect(compactWindow('200000', 500000, 1_000_000)).toBe(200000)
  expect(compactWindow('200k', 500000, 1_000_000)).toBe(500000)
  expect(compactWindow(undefined, 2_000_000, 1_000_000)).toBe(1_000_000)
  expect(compactWindow(undefined, undefined, 1_000_000)).toBe(1_000_000)
})

test('model ids read as /model names them', () => {
  expect(modelName('claude-opus-5-5[1m]')).toBe('Opus 5.5')
  expect(modelName('claude-haiku-5-5')).toBe('Haiku 5.5')
  expect(modelName('sonnet')).toBe('Sonnet')
  expect(modelName('gpt-x')).toBe('gpt-x')
  expect(modelName('claude-sonnet-4-20250514')).toBe('Sonnet 4')
})

test('warning from 70%, error from 90%', () => {
  expect(level(69)).toBeUndefined()
  expect(level(70)).toBe('warning')
  expect(level(90)).toBe('error')
})

test('a narrow row drops VRAM, then GPU, and keeps CPU and the context figure', () => {
  const s = { cpu: 5, mem: { used: GiB, total: 2 * GiB }, gpu: { busy: 1, vramUsed: GiB, vramTotal: 2 * GiB } }
  const right = contextGroup({ tokens: 1000, window: 500000 })
  expect(fit(groups(s), right, 200).map((g) => g.key)).toEqual(['cpu', 'ram', 'gpu', 'vram'])
  expect(fit(groups(s), right, 60).map((g) => g.key)).toEqual(['cpu', 'ram', 'gpu'])
  expect(fit(groups(s), right, 5).map((g) => g.key)).toEqual(['cpu'])
})

test('the band stays empty until a second CPU sample, then shows every resource and the context figure', async ($, on) => {
  stub(on)
  const clock = mock.clock(on)
  await $.session.start(START)

  let ui = await $.ui.mount(band())
  expect(await ui.find({ type: 'Text', text: '25%' })).toBeUndefined()
  await ui.unmount()

  await clock.advance(2000)
  ui = await $.ui.mount(band())
  expect(await ui.find({ type: 'Text', text: '25%' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' 16.0/64 GB' })).toBeDefined()
  // 95% of VRAM is in the error colour
  expect((await ui.find({ type: 'Text', text: '75%' }))?.props.color).toBe('warning')
  expect((await ui.find({ type: 'Text', text: '95%' }))?.props.color).toBe('error')
  // 400k of the 500k auto-compact window from the settings, not of the 1M model window
  expect((await ui.find({ type: 'Text', text: '80%' }))?.props.color).toBe('warning')
  expect(await ui.find({ type: 'Text', text: ' 400k/500k' })).toBeDefined()
  // before any request, the effort setting
  expect(await ui.find({ type: 'Text', text: 'OPUS 5.5 HIGH   ' })).toBeDefined()
  // what Claude Code and later mods draw in the band stays
  expect(await ui.find({ type: 'Text', text: 'drawn by Claude Code' })).toBeDefined()
  await ui.unmount()
})

test("the effort the main loop last sent replaces the setting and redraws; a subagent's does not; the request passes unchanged", async ($, on) => {
  // Claude Code's own answer to a request, beneath the mod: it records what reached it
  const reached: any[] = []
  on('turn.step', async function* ($: any, e: any) {
    reached.push(e)
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }
  })
  await started($, on)
  const ui = await $.ui.mount(band())
  expect(await ui.find({ type: 'Text', text: 'OPUS 5.5 HIGH   ' })).toBeDefined()
  const main = { turnId: 't1', index: 0, model: 'claude-opus-5-5', effort: 'xhigh', messageCount: 1 }
  const sub = { turnId: 't2', index: 0, model: 'claude-sonnet-5-5', effort: 'low', messageCount: 1, agentId: 'a1' }
  // a request streams: drain each one as Claude Code would
  for await (const _ of $.turn.step(main));
  for await (const _ of $.turn.step(sub));
  // the drawing already on screen picks up the new effort
  expect(await ui.find({ type: 'Text', text: 'OPUS 5.5 XHIGH   ' })).toBeDefined()
  await ui.unmount()
  expect(reached).toHaveLength(2)
  expect(reached[0]).toMatchObject(main)
  expect(reached[1]).toMatchObject(sub)
})

test('before any request, the per-model effort setting beats the global one', async ($, on) => {
  await started($, on, {
    settings: { autoCompactWindow: 500000, effortLevel: 'high', modelSettings: { 'claude-opus-5-5': { effortLevel: 'medium' } } },
  })
  const ui = await $.ui.mount(band())
  expect(await ui.find({ type: 'Text', text: 'OPUS 5.5 MEDIUM   ' })).toBeDefined()
  await ui.unmount()
})

test('the window follows the environment variable', async ($, on) => {
  await started($, on, { env: ' 800000 ' })
  const ui = await $.ui.mount(band())
  expect(await ui.find({ type: 'Text', text: ' 400k/800k' })).toBeDefined()
  await ui.unmount()
})

test('CTX shows a dash before the first response', async ($, on) => {
  await started($, on, { tokens: undefined })
  const ui = await $.ui.mount(band())
  expect(await ui.find({ type: 'Text', text: '—' })).toBeDefined()
  await ui.unmount()
})

test('the band yields to a survey', async ($, on) => {
  await started($, on)
  const ui = await $.ui.mount(band(160, true))
  expect(await ui.find({ type: 'Text', text: '25%' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'drawn by Claude Code' })).toBeDefined()
  await ui.unmount()
})

test('without a GPU the band still shows CPU and memory', async ($, on) => {
  await started($, on, { gpu: false })
  const ui = await $.ui.mount(band())
  expect(await ui.find({ type: 'Text', text: '25%' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' 16.0/64 GB' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'GPU ' })).toBeUndefined()
  await ui.unmount()
})

test('an unreadable /proc/stat leaves the band empty and /sysres still registered', async ($, on) => {
  stub(on, { own: ['fs.read', 'command.register'] })
  on('fs.read', ($: any, e: any) => (e.path === '/proc/stat' ? { deny: 'EACCES' } : { value: '' }))
  const registered: string[] = []
  on('command.register', ($: any, e: any) => {
    registered.push(e.name)
    return { value: undefined }
  })
  const clock = mock.clock(on)
  await $.session.start(START)
  await clock.advance(4000)
  expect(registered).toEqual(['sysres'])
  const ui = await $.ui.mount(band())
  expect(await ui.find({ type: 'Text', text: 'drawn by Claude Code' })).toBeDefined()
  await ui.unmount()
})

test('a -p run starts no timer', async ($, on) => {
  stub(on, { own: ['fs.read'] })
  let reads = 0
  on('fs.read', ($: any, e: any) => {
    if (e.path === '/proc/stat') reads++
    return { value: CPU[0] }
  })
  const clock = mock.clock(on)
  await $.session.start({ ...START, isInteractive: false, surface: null })
  await clock.advance(10_000)
  expect(reads).toBe(0)
})

test('/sysres reports CPU before the first tick, load, swap-less memory, GPU temperature and each device once', async ($, on) => {
  // The session-start tick reads the first sample, /sysres the next two
  stub(on, { cpu: [CPU[0], CPU[0], CPU[1]] })
  const clock = mock.clock(on)
  await $.session.start(START)
  const pending = $.command.run({ command: 'sysres', args: '' })
  await clock.advance(250)
  const answer = await pending
  expect(answer.text).toBe(
    [
      'CPU   25% · load 1.50 0.75 0.25',
      'RAM   16.0 / 64.0 GB (25%)',
      'GPU   75% · VRAM 19.0 / 20.0 GB · 45°C',
      'Disk  / 33.0 / 100.0 GB (33%)',
      'Disk  /work 5.0 / 10.0 GB (50%)',
    ].join('\n'),
  )
})

test('/sysres keeps the GPU line without hwmon and says when df fails', async ($, on) => {
  const clock = await started($, on, { hwmon: false, df: 'fail' })
  const answer = await $.command.run({ command: 'sysres', args: '' })
  expect(answer.text).toContain('GPU   75% · VRAM 19.0 / 20.0 GB\n')
  expect(answer.text).toContain('Disk  df failed')
  void clock
})

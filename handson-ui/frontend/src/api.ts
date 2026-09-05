import type { AgentContext, AgentEvent } from './types'

// code-server の /proxy/3000/ 配下で開くので、パスは現在地からの相対で組む
const base = location.pathname.endsWith('/') ? location.pathname : `${location.pathname}/`

export async function fetchContext(): Promise<AgentContext> {
  const res = await fetch(`${base}api/context`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

/** SSE を読んで、届いたイベントを 1 つずつ返す。 */
export async function* askAgent(prompt: string, signal?: AbortSignal): AsyncGenerator<AgentEvent> {
  const res = await fetch(`${base}api/ask`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt }),
    signal,
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  if (!res.body) throw new Error('レスポンスが空です')

  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break

    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''

    for (const line of lines) {
      if (!line.startsWith('data:')) continue
      const payload = line.slice(5).trim()
      if (!payload) continue
      try {
        yield JSON.parse(payload) as AgentEvent
      } catch {
        // 途中で切れた行は捨てる
      }
    }
  }
}

import type { AgentContext, AgentEvent, AskTarget, RuntimeInfo } from './types'

// code-server の /proxy/3000/ 配下で開くので、パスは現在地からの相対で組む
const base = location.pathname.endsWith('/') ? location.pathname : `${location.pathname}/`

/** handson-agent/ のコードを読み込めなかったとき（受講者の書き間違い）に投げる。
 *  サーバーは落ちずに 503 と理由（どのファイルの何行目か）を返すので、画面の上に目立つ形で出す。 */
export class AgentLoadError extends Error {}

export async function fetchContext(): Promise<AgentContext> {
  const res = await fetch(`${base}api/context`)
  if (res.status === 503) {
    const body = await res.json().catch(() => null)
    if (typeof body?.detail === 'string') throw new AgentLoadError(body.detail)
  }
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

/** Runtime にデプロイ済みかどうかを取得する。取得自体に失敗しても投げずに未デプロイ扱いにする。 */
export async function fetchRuntime(): Promise<RuntimeInfo> {
  const res = await fetch(`${base}api/runtime`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

/** SSE を読んで、届いたイベントを 1 つずつ返す。target で手元と Runtime のどちらで動かすか選ぶ。 */
export async function* askAgent(
  prompt: string,
  target: AskTarget,
  signal?: AbortSignal,
): AsyncGenerator<AgentEvent> {
  const res = await fetch(`${base}api/ask`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt, target }),
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

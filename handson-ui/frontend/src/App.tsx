import { useCallback, useEffect, useRef, useState } from 'react'
import { askAgent, fetchContext, fetchRuntime } from './api'
import { ContextPanel } from './components/ContextPanel'
import { Timeline } from './components/Timeline'
import type { AgentContext, AskTarget, RuntimeInfo, Step } from './types'

const EXAMPLES = [
  'ノートPCで今借りられるものある？',
  'PC-001って誰が借りてるの？',
  'モニター借りたいんだけど',
]

let sequence = 0
const nextId = () => `s${sequence++}`

export function App() {
  const [context, setContext] = useState<AgentContext | null>(null)
  const [contextError, setContextError] = useState<string | null>(null)
  const [runtime, setRuntime] = useState<RuntimeInfo | null>(null)
  const [target, setTarget] = useState<AskTarget>('local')
  const [steps, setSteps] = useState<Step[]>([])
  const [prompt, setPrompt] = useState('')
  const [busy, setBusy] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    fetchContext()
      .then(setContext)
      .catch((e: unknown) => setContextError(String(e)))
  }, [])

  useEffect(() => {
    // 未デプロイの受講者には切り替え自体を出さないので、失敗時は「未デプロイ」として扱う
    fetchRuntime()
      .then(setRuntime)
      .catch(() => setRuntime({ available: false, name: '', arn: null, region: '' }))
  }, [])

  const ask = useCallback(async (question: string) => {
    setBusy(true)
    setPrompt('')

    // 待機カードは 1 枚だけ出し、次の出来事が来たら差し替える
    const waitingId = nextId()
    const answerId = nextId()
    const askTarget = target

    setSteps([
      { kind: 'question', id: nextId(), text: question, target: askTarget },
      { kind: 'waiting', id: waitingId, label: 'モデルが考えています', startedAt: performance.now() },
    ])

    const dropWaiting = (list: Step[]) => list.filter((step) => step.kind !== 'waiting')
    const waiting = (label: string): Step => ({
      kind: 'waiting',
      id: nextId(),
      label,
      startedAt: performance.now(),
    })

    // この質問の中で何周目か。cycle_start はループが 1 周するたびに届く
    let cycleIndex = 0

    try {
      for await (const event of askAgent(question, askTarget)) {
        switch (event.type) {
          case 'cycle_start':
            cycleIndex += 1
            setSteps((list) => [
              ...dropWaiting(list),
              { kind: 'cycle', id: nextId(), index: cycleIndex },
              waiting('モデルが考えています'),
            ])
            break

          case 'tool_use':
            setSteps((list) => {
              const rest = dropWaiting(list)
              const existing = rest.find(
                (step) => step.kind === 'tool_use' && step.id === `tool-${event.id}`,
              )
              if (existing) {
                return rest.map((step) =>
                  step.kind === 'tool_use' && step.id === `tool-${event.id}`
                    ? { ...step, input: event.input ?? '', raw: event.raw }
                    : step,
                )
              }
              return [
                ...rest,
                {
                  kind: 'tool_use',
                  id: `tool-${event.id}`,
                  name: event.name,
                  input: event.input ?? '',
                  raw: event.raw,
                },
                waiting('ツールを実行しています'),
              ]
            })
            break

          case 'tool_result':
            setSteps((list) => [
              ...dropWaiting(list),
              { kind: 'tool_result', id: nextId(), results: event.results, raw: event.raw },
              waiting('モデルが結果を読んでいます'),
            ])
            break

          case 'text':
            setSteps((list) => {
              const rest = dropWaiting(list)
              const answer = rest.find((step) => step.kind === 'answer' && step.id === answerId)
              if (answer) {
                return rest.map((step) =>
                  step.kind === 'answer' && step.id === answerId
                    ? { ...step, text: step.text + event.text }
                    : step,
                )
              }
              return [...rest, { kind: 'answer', id: answerId, text: event.text, done: false }]
            })
            break

          case 'done':
            setSteps((list) => {
              const rest = dropWaiting(list).map((step) =>
                step.kind === 'answer' ? { ...step, done: true } : step,
              )
              return event.summary
                ? [...rest, { kind: 'summary', id: nextId(), summary: event.summary }]
                : rest
            })
            break

          case 'error':
            setSteps((list) => [
              ...dropWaiting(list),
              { kind: 'error', id: nextId(), message: event.message },
            ])
            break
        }
      }
    } catch (e: unknown) {
      setSteps((list) => [
        ...dropWaiting(list),
        { kind: 'error', id: nextId(), message: String(e) },
      ])
    } finally {
      setSteps((list) => dropWaiting(list))
      setBusy(false)
      inputRef.current?.focus()
    }
  }, [target])

  return (
    <div className="app">
      <header className="masthead">
        <h1>エージェントの動きを見る</h1>
        <p>質問を投げると、モデルが何を考えて、どのツールを呼んで、何が返ってきたのかが順番に出ます。</p>
      </header>

      <ContextPanel context={context} error={contextError} />

      {runtime?.available && (
        <div className="target-switch" role="radiogroup" aria-label="実行場所">
          <label>
            <input
              type="radio"
              name="target"
              value="local"
              checked={target === 'local'}
              disabled={busy}
              onChange={() => setTarget('local')}
            />
            手元で動かす
          </label>
          <label>
            <input
              type="radio"
              name="target"
              value="runtime"
              checked={target === 'runtime'}
              disabled={busy}
              onChange={() => setTarget('runtime')}
            />
            Runtime で動かす（{runtime.name}）
          </label>
        </div>
      )}

      <form
        className="ask"
        onSubmit={(e) => {
          e.preventDefault()
          const question = prompt.trim()
          if (question && !busy) void ask(question)
        }}
      >
        <input
          ref={inputRef}
          type="text"
          value={prompt}
          placeholder="備品について聞いてみる"
          autoComplete="off"
          onChange={(e) => setPrompt(e.target.value)}
          disabled={busy}
        />
        <button type="submit" disabled={busy || prompt.trim() === ''}>
          送る
        </button>
      </form>

      <div className="examples">
        {EXAMPLES.map((example) => (
          <button key={example} type="button" disabled={busy} onClick={() => void ask(example)}>
            {example}
          </button>
        ))}
      </div>

      <Timeline steps={steps} />
    </div>
  )
}

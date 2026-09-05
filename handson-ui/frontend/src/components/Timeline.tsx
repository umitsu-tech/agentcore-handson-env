import type { Step } from '../types'
import { RawData } from './RawData'
import { Summary } from './Summary'
import { Waiting } from './Waiting'

type Props = {
  steps: Step[]
}

type CycleStep = Extract<Step, { kind: 'cycle' }>
type Group = { cycle: CycleStep; items: Step[] }

// steps を「cycle 見出しより前」「周ごとのグループ」「summary・error（末尾）」に分ける。
// question は先頭グループより前、answer は直前の周のグループの中に入る。
function groupSteps(steps: Step[]) {
  const leading: Step[] = []
  const groups: Group[] = []
  const trailing: Step[] = []
  let current: Group | null = null

  for (const step of steps) {
    if (step.kind === 'cycle') {
      current = { cycle: step, items: [] }
      groups.push(current)
      continue
    }
    if (step.kind === 'summary' || step.kind === 'error') {
      trailing.push(step)
      continue
    }
    if (current) {
      current.items.push(step)
    } else {
      leading.push(step)
    }
  }

  return { leading, groups, trailing }
}

export function Timeline({ steps }: Props) {
  if (steps.length === 0) return null

  const { leading, groups, trailing } = groupSteps(steps)

  return (
    <div className="timeline">
      {leading.map((step) => (
        <div className={`step ${step.kind}`} key={step.id}>
          {renderStep(step)}
        </div>
      ))}

      {groups.map(({ cycle, items }) => (
        // open は初期値としてのみ渡す。React に open の状態を管理させると、
        // 再描画のたびに開いた状態へ戻ってしまいユーザーが畳めなくなるため。
        <details className="cycle" open key={cycle.id}>
          <summary className="cycle-heading">
            <span className="cycle-badge">{cycle.index}周目</span>
            <span className="cycle-text">
              {cycle.index === 1
                ? 'モデルを呼びます（質問とツールの一覧を渡します）'
                : 'ツールの結果を持って、もう一度モデルを呼びます'}
            </span>
          </summary>
          <div className="cycle-body">
            {items.map((step) => (
              <div className={`step ${step.kind} in-cycle`} key={step.id}>
                {renderStep(step)}
              </div>
            ))}
          </div>
        </details>
      ))}

      {trailing.map((step) => (
        <div className={`step ${step.kind}`} key={step.id}>
          {renderStep(step)}
        </div>
      ))}
    </div>
  )
}

function renderStep(step: Step) {
  switch (step.kind) {
    case 'question':
      return (
        <div className="card">
          <div className="label">あなたの質問</div>
          <div className="text">{step.text}</div>
        </div>
      )

    case 'cycle':
      // groups のレンダリングで <summary> として直接扱うため、ここには来ない。
      return null

    case 'waiting':
      return <Waiting label={step.label} startedAt={step.startedAt} />

    case 'tool_use':
      return (
        <div className="card">
          <div className="label">モデルがツールを呼びました</div>
          <div className="tool-name">{step.name}</div>
          {step.input && <div className="args">{step.input}</div>}
          <RawData data={step.raw} />
        </div>
      )

    case 'tool_result':
      return (
        <div className="card">
          <div className="label">ツールが返した結果</div>
          {step.results.map((result, index) => (
            <div className="text" key={result.id ?? index}>
              {result.text}
            </div>
          ))}
          <RawData data={step.raw} />
        </div>
      )

    case 'answer':
      return (
        <div className="card">
          <div className="label">モデルの答え</div>
          <div className={`text ${step.done ? '' : 'caret'}`}>{step.text}</div>
          {step.done && (
            <div className="answer-note">
              ツールを呼ばずに答えたので、ここでループが終わりました
            </div>
          )}
        </div>
      )

    case 'summary':
      return <Summary summary={step.summary} />

    case 'error':
      return (
        <div className="card">
          <div className="label">エラー</div>
          <div className="text">{step.message}</div>
        </div>
      )
  }
}

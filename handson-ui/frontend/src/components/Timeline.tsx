import type { Step } from '../types'
import { RawData } from './RawData'
import { Summary } from './Summary'
import { Waiting } from './Waiting'

type Props = {
  steps: Step[]
}

// 周回の区切り見出しの後に続くステップだけ、少し内側に寄せて表示する
const IN_CYCLE_KINDS = new Set(['tool_use', 'tool_result', 'answer', 'waiting'])

export function Timeline({ steps }: Props) {
  if (steps.length === 0) return null

  let afterCycleStart = false

  return (
    <div className="timeline">
      {steps.map((step) => {
        if (step.kind === 'cycle') afterCycleStart = true
        const inCycle = afterCycleStart && IN_CYCLE_KINDS.has(step.kind)
        return (
          <div className={`step ${step.kind}${inCycle ? ' in-cycle' : ''}`} key={step.id}>
            {renderStep(step)}
          </div>
        )
      })}
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
      return (
        <div className="cycle-heading">
          <span className="cycle-badge">{step.index}周目</span>
          <span className="cycle-text">
            {step.index === 1
              ? 'モデルを呼びます（質問とツールの一覧を渡します）'
              : 'ツールの結果を持って、もう一度モデルを呼びます'}
          </span>
        </div>
      )

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

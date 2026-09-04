import type { Step } from '../types'
import { RawData } from './RawData'
import { Summary } from './Summary'
import { Waiting } from './Waiting'

type Props = {
  steps: Step[]
}

export function Timeline({ steps }: Props) {
  if (steps.length === 0) return null

  return (
    <div className="timeline">
      {steps.map((step) => (
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

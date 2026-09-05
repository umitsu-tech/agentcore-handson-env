import type { Step } from '../types'
import { RawData } from './RawData'
import { Summary } from './Summary'
import { Waiting } from './Waiting'

type Props = {
  steps: Step[]
}

type CycleStep = Extract<Step, { kind: 'cycle' }>
type Group = { cycle: CycleStep; items: Step[] }

// steps を「周ごとのグループ」と「summary・error（末尾）」に分ける。
// 1 周は「モデルへの入力 → モデルの出力」の 1 往復になるように揃える。
// - question（と直後の waiting）は最初の周のグループの中に入る（先頭グループは無くす）。
//   ただし最初の cycle 見出しがまだ届いていない間は leading として先頭にそのまま出す。
// - tool_result（と直後の waiting）は「次の周への入力」なので、次の cycle 見出しが
//   届いた瞬間に新しい周のグループの先頭へ移る。まだ届いていない間は現在の周の末尾のまま。
function groupSteps(steps: Step[]) {
  const leading: Step[] = []
  const groups: Group[] = []
  const trailing: Step[] = []
  let current: Group | null = null

  for (const step of steps) {
    if (step.kind === 'cycle') {
      const previous = current
      current = { cycle: step, items: [] }

      if (previous) {
        // 直前の周の末尾にある tool_result（と、それに続く waiting）は
        // 新しい周への入力なので、新しい周のグループの先頭へ移す。
        const carryFrom = findTrailingToolResultStart(previous.items)
        if (carryFrom !== -1) {
          current.items.push(...previous.items.splice(carryFrom))
        }
      } else if (leading.length > 0) {
        // 最初の周が始まるまでの question（と waiting）は、
        // 先頭グループを持たず最初の周のグループに含める。
        current.items.push(...leading.splice(0))
      }

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

// items の末尾が tool_result とそれに続く waiting だけの並びなら、その tool_result の
// インデックスを返す（無ければ -1）。次の周へ持ち越す範囲の開始位置として使う。
function findTrailingToolResultStart(items: Step[]) {
  let index = items.length - 1
  while (index >= 0 && items[index].kind === 'waiting') {
    index -= 1
  }
  return index >= 0 && items[index].kind === 'tool_result' ? index : -1
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
                : 'ツールの結果を渡して、もう一度モデルを呼びます'}
            </span>
          </summary>
          <div className="cycle-body">
            {items.map((step) => (
              <div className={`step ${step.kind} in-cycle`} key={step.id}>
                {renderStep(step, cycle.index)}
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

function renderStep(step: Step, cycleIndex?: number) {
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
          {cycleIndex !== undefined && cycleIndex >= 2 && (
            <div className="input-note">
              この結果だけでなく、ここまでの質問とツール呼び出しの履歴もまとめてモデルに渡します
            </div>
          )}
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

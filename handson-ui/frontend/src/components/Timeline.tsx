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
// - question はタイムライン先頭（leading）に常に残す。加えて、最初の cycle 見出しが
//   届いた瞬間に、その question を「モデルへの入力」として最初の周のグループにも
//   コピーして表示する（重複表示。React の key 重複を避けるため id には接尾辞を付ける）。
// - question の直後の waiting は、最初の cycle 見出しが届く前は leading に、
//   届いたあとは最初の周のグループへ移す（従来どおり片方にしか出さない）。
// - tool_result は「モデルを呼ぶ→ツールを実行する→結果を受け取る」までを 1 周とするため、
//   直前の周の末尾にそのまま残す。ただし次の周への入力でもあるので、次の cycle 見出しが
//   届いた瞬間に、そのコピーを新しい周のグループの先頭にも入れる（重複表示。id には
//   接尾辞を付けて key の重複を避ける）。直後の waiting は（これまでどおり）新しい周の
//   グループへ移す。
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
        // tool_result は前の周の末尾に残す。コピーだけを新しい周のグループの
        // 先頭（モデルへの入力）に入れ、直後の waiting は新しい周のグループへ移す。
        const carryFrom = findTrailingToolResultStart(previous.items)
        if (carryFrom !== -1) {
          const toolResult = previous.items[carryFrom]
          const waitingSteps = previous.items.splice(carryFrom + 1)
          current.items.push({ ...toolResult, id: `${toolResult.id}-in-next-cycle` }, ...waitingSteps)
        }
      } else if (leading.length > 0) {
        // question はコピーして最初の周のグループにも入れる（leading 側にはそのまま残す）。
        // waiting はこれまでどおり leading から移す。
        const remainingLeading: Step[] = []
        for (const leadingStep of leading) {
          if (leadingStep.kind === 'question') {
            current.items.push({ ...leadingStep, id: `${leadingStep.id}-in-cycle` })
            remainingLeading.push(leadingStep)
          } else {
            current.items.push(leadingStep)
          }
        }
        leading.length = 0
        leading.push(...remainingLeading)
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
// インデックスを返す（無ければ -1）。次の周へコピーを持ち越す起点として使う。
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
            {items.map((step, index) => (
              <div className={`step ${step.kind} in-cycle`} key={step.id}>
                {renderStep(step, cycle.index, index === 0)}
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

function renderStep(step: Step, cycleIndex?: number, isGroupStart?: boolean) {
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
          {isGroupStart && cycleIndex !== undefined && cycleIndex >= 2 && (
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

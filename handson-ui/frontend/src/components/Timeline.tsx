import type { Step } from '../types'
import { renderAnswerText } from '../lib/markdown'
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

  // 最後の周の答えが完了していたら、そのコピーをループの外（trailing の先頭、
  // summary・error より前）にも出す。「モデルの答え」の 2 周目のカードはそのまま残し、
  // これは最終結果として別枠で見せるためのコピー（id には接尾辞を付ける）。
  const lastGroup = groups[groups.length - 1]
  const finalAnswer = lastGroup?.items.find((step) => step.kind === 'answer')
  if (finalAnswer && finalAnswer.kind === 'answer' && finalAnswer.done) {
    trailing.unshift({ ...finalAnswer, id: `${finalAnswer.id}-final` })
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
        // question はループの外（ベースカラー）の質問カードとして出す。
        <div className={`step ${step.kind}${step.kind === 'question' ? ' outside' : ''}`} key={step.id}>
          {renderStep(step, { isOutside: true })}
        </div>
      ))}

      {groups.map(({ cycle, items }, groupIndex) => (
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
            {items.map((step, index) => {
              // 周の末尾に残った tool_result（次の周にコピーが渡った側）は、
              // 次の周が始まった時点でモデル/ツールからの「出力」として橙にする。
              // まだ次の周が始まっていない（＝最後の周の末尾）間は入力色の青のまま。
              const isTrailingResult =
                groupIndex < groups.length - 1 && index === items.length - 1 && step.kind === 'tool_result'
              return (
                <div
                  className={`step ${step.kind} in-cycle${isTrailingResult ? ' as-output' : ''}`}
                  key={step.id}
                >
                  {renderStep(step, {
                    cycleIndex: cycle.index,
                    isGroupStart: index === 0,
                  })}
                </div>
              )
            })}
          </div>
        </details>
      ))}

      {trailing.map((step) => (
        // 最終的な答えのコピー（id 末尾 -final）はループの外（ベースカラー）で出す。
        <div
          className={`step ${step.kind}${step.kind === 'answer' && step.id.endsWith('-final') ? ' outside' : ''}`}
          key={step.id}
        >
          {renderStep(step, { isOutside: true })}
        </div>
      ))}
    </div>
  )
}

// ツールが返した結果（JSON 文字列）をパースできれば、読みやすく整形した文字列を返す。
// パースできなければ null を返し、呼び出し側は元の文字列をそのまま表示する。
function formatIfJson(text: string): string | null {
  try {
    return JSON.stringify(JSON.parse(text), null, 2)
  } catch {
    return null
  }
}

// 各カードのラベルに「何周目の入力／出力か」を補足する小さな注釈を付けるための要素。
// 本文ラベルと同じ色（親の .label の color を継承）で、太さだけ通常に戻す。
function LabelNote({ children }: { children: string }) {
  return <span className="label-note">（{children}）</span>
}

type RenderOptions = {
  cycleIndex?: number
  isGroupStart?: boolean
  isOutside?: boolean
}

function renderStep(step: Step, options: RenderOptions = {}) {
  const { cycleIndex, isGroupStart, isOutside } = options

  switch (step.kind) {
    case 'question':
      return (
        <div className="card">
          <div className="label">
            あなたの質問
            <LabelNote>{isOutside ? 'お題' : 'インプット'}</LabelNote>
          </div>
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
          <div className="label">
            モデルがツールを呼びました
            <LabelNote>モデルの判断</LabelNote>
          </div>
          <div className="tool-name">{step.name}</div>
          {step.input && <div className="args">{step.input}</div>}
          <RawData data={step.raw} />
        </div>
      )

    case 'tool_result': {
      // 周先頭のコピー（次の周への入力として渡ってきた側）は isGroupStart で判定する。
      // それ以外（周末尾に残った実物）は、次の周が始まっているかどうかの as-output の
      // 色切り替えとは独立に「この周で発生した結果そのもの」として出力扱いにする。
      const resultNote = isGroupStart ? 'インプット' : 'アウトプット'
      return (
        <div className="card">
          <div className="label">
            ツールが返した結果
            <LabelNote>{resultNote}</LabelNote>
          </div>
          {step.results.map((result, index) => {
            // ツールは dict / list のデータを返し、Strands がそれを JSON 文字列にして
            // モデルへ渡す。JSON としてパースできればそのまま整形して見せ、
            // できなければ（旧イベントなど）これまでどおり文字列として出す。
            const formatted = formatIfJson(result.text)
            return formatted ? (
              <pre className="args json" key={result.id ?? index}>
                {formatted}
              </pre>
            ) : (
              <div className="text" key={result.id ?? index}>
                {result.text}
              </div>
            )
          })}
          {isGroupStart && cycleIndex !== undefined && cycleIndex >= 2 && (
            <div className="input-note">
              この結果だけでなく、ここまでの質問とツール呼び出しの履歴もまとめてモデルに渡します
            </div>
          )}
          <RawData data={step.raw} />
        </div>
      )
    }

    case 'answer': {
      // isOutside（id 末尾が -final）のものは、ループの外に出す最終結果のコピー。
      // ラベルを変え、周の中でだけ意味を持つ補足行（ループが終わった理由）は出さない。
      return (
        <div className="card">
          <div className="label">
            {isOutside ? (
              '最終的な答え'
            ) : (
              <>
                モデルの答え
                <LabelNote>アウトプット</LabelNote>
              </>
            )}
          </div>
          <div className={`text ${step.done ? '' : 'caret'}`}>{renderAnswerText(step.text)}</div>
          {step.done && !isOutside && (
            <div className="answer-note">
              モデルの返事がツールの要求ではなく答えだったので、ループはここで止まります
            </div>
          )}
        </div>
      )
    }

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

import type { ResultSummary } from '../types'

type Props = {
  summary: ResultSummary
}

/** 1 回のやりとりが終わったところに出す集計。
 *  ツールを呼ぶとループが 2 周になることが数字で見える。 */
export function Summary({ summary }: Props) {
  const usage = summary.usage ?? {}
  const tools = Object.entries(summary.tools ?? {})

  return (
    <div className="card">
      <div className="label">このやりとりの中身</div>
      <div className="metrics">
        {summary.cycles !== undefined && (
          <div className="metric">
            <div className="value">{summary.cycles}</div>
            <div className="name">ループの周回数</div>
          </div>
        )}
        {usage.inputTokens !== undefined && (
          <div className="metric">
            <div className="value">{usage.inputTokens.toLocaleString()}</div>
            <div className="name">入力トークン</div>
          </div>
        )}
        {usage.outputTokens !== undefined && (
          <div className="metric">
            <div className="value">{usage.outputTokens.toLocaleString()}</div>
            <div className="name">出力トークン</div>
          </div>
        )}
      </div>

      {tools.length > 0 && (
        <div className="tool-usage">
          {tools.map(([name, metric]) => (
            <div key={name}>
              <code>{name}</code> を {metric.call_count ?? 0} 回呼びました
              {metric.error_count ? `（うち失敗 ${metric.error_count} 回）` : ''}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

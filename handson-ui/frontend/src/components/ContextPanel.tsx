import type { AgentContext } from '../types'

type Props = {
  context: AgentContext | null
  error: string | null
}

/** モデルに何を渡しているかを見せるパネル。
 *  ツールの説明文は tools.py の docstring がそのまま出る。
 *  「この文章をモデルが読んでツールを選んでいる」ことを目で見てもらうため。 */
export function ContextPanel({ context, error }: Props) {
  return (
    <details className="context">
      <summary>モデルに渡しているもの</summary>
      <div className="context-body">
        {error && <p className="hint">読み込みに失敗しました: {error}</p>}
        {!context && !error && <p className="hint">読み込み中…</p>}

        {context && (
          <>
            <div className="context-row">
              <span className="key">モデル</span>
              <code className="tool-name">{context.model_id}</code>
            </div>

            <h3>システムプロンプト</h3>
            <pre className="block">{context.system_prompt.trim()}</pre>

            <h3>モデルが使えるツール（{context.tools.length}個）</h3>
            {context.tools.map((tool) => (
              <div className="tool-def" key={tool.name}>
                <div className="name">{tool.name}</div>
                <p className="desc">{tool.description}</p>
                <details className="raw">
                  <summary>引数の定義を見る</summary>
                  <pre>{JSON.stringify(tool.input_schema, null, 2)}</pre>
                </details>
              </div>
            ))}

            <p className="hint">
              ツールの説明文は tools.py の docstring がそのまま渡っています。書き換えるとモデルの選び方が変わります。
            </p>
          </>
        )}
      </div>
    </details>
  )
}

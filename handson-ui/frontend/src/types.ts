export type ToolResult = {
  id?: string
  status?: string
  text: string
}

export type ResultSummary = {
  stop_reason?: string
  usage?: { inputTokens?: number; outputTokens?: number; totalTokens?: number }
  cycles?: number
  tools?: Record<string, { call_count?: number; success_count?: number; error_count?: number; total_time?: number }>
}

/** サーバーから SSE で届くイベント。events.py の to_ui_event が作る形。 */
export type AgentEvent =
  | { type: 'loop_start'; raw?: unknown }
  | { type: 'cycle_start'; raw?: unknown }
  | { type: 'tool_use'; id?: string; name: string; input?: string; raw?: unknown }
  | { type: 'tool_result'; results: ToolResult[]; raw?: unknown }
  | { type: 'text'; text: string }
  | { type: 'done'; summary?: ResultSummary }
  | { type: 'error'; message: string }

/** 画面のタイムラインに積むもの。 */
export type Step =
  | { kind: 'question'; id: string; text: string; target: AskTarget }
  | { kind: 'cycle'; id: string; index: number }
  | { kind: 'waiting'; id: string; label: string; startedAt: number }
  | { kind: 'tool_use'; id: string; name: string; input: string; raw?: unknown }
  | { kind: 'tool_result'; id: string; results: ToolResult[]; raw?: unknown }
  | { kind: 'answer'; id: string; text: string; done: boolean }
  | { kind: 'summary'; id: string; summary: ResultSummary }
  | { kind: 'error'; id: string; message: string }

export type ToolDefinition = {
  name: string
  description: string
  input_schema: unknown
}

export type AgentContext = {
  model_id: string
  system_prompt: string
  tools: ToolDefinition[]
}

/** GET /api/runtime のレスポンス。Runtime にデプロイ済みかどうかを画面に伝える。 */
export type RuntimeInfo = {
  available: boolean
  name: string
  arn: string | null
  region: string
  reason?: string
}

export type AskTarget = 'local' | 'runtime'

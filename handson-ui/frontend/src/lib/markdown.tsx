import type { ReactNode } from 'react'
import { Fragment } from 'react'

// モデルの答えを軽く Markdown 風に解釈して表示するための変換。
// 外部ライブラリは使わず、行ごとに「箇条書き / 番号付きリスト / 段落」を
// 判定してブロックに分け、各行内の **強調** だけをインライン処理する。
// ストリーミング中（文章が末尾で途切れている状態）でも壊れず表示できるよう、
// 閉じていない ** や中途半端な行はそのまま素通りさせる。

type Block =
  | { type: 'ul'; items: string[] }
  | { type: 'ol'; items: string[] }
  | { type: 'paragraph'; lines: string[]; heading: boolean }

const BULLET_RE = /^[-*]\s+(.*)$/
const NUMBERED_RE = /^\d+\.\s+(.*)$/
const HEADING_RE = /^#+\s*(.*)$/

function parseBlocks(text: string): Block[] {
  const lines = text.split('\n')
  const blocks: Block[] = []
  let i = 0

  while (i < lines.length) {
    const line = lines[i]

    if (line.trim() === '') {
      i += 1
      continue
    }

    const bulletMatch = BULLET_RE.exec(line)
    if (bulletMatch) {
      const items: string[] = []
      while (i < lines.length) {
        const m = BULLET_RE.exec(lines[i])
        if (!m) break
        items.push(m[1])
        i += 1
      }
      blocks.push({ type: 'ul', items })
      continue
    }

    const numberedMatch = NUMBERED_RE.exec(line)
    if (numberedMatch) {
      const items: string[] = []
      while (i < lines.length) {
        const m = NUMBERED_RE.exec(lines[i])
        if (!m) break
        items.push(m[1])
        i += 1
      }
      blocks.push({ type: 'ol', items })
      continue
    }

    const headingMatch = HEADING_RE.exec(line)
    if (headingMatch) {
      blocks.push({ type: 'paragraph', lines: [headingMatch[1]], heading: true })
      i += 1
      continue
    }

    const paragraphLines: string[] = []
    while (
      i < lines.length &&
      lines[i].trim() !== '' &&
      !BULLET_RE.test(lines[i]) &&
      !NUMBERED_RE.test(lines[i]) &&
      !HEADING_RE.test(lines[i])
    ) {
      paragraphLines.push(lines[i])
      i += 1
    }
    blocks.push({ type: 'paragraph', lines: paragraphLines, heading: false })
  }

  return blocks
}

// "**text**" だけを <strong> に変換する。閉じていない ** はそのまま文字として残す。
// "*text*" の斜体は対象外（要件どおり非対応）。
function renderInline(line: string, keyPrefix: string): ReactNode[] {
  const parts: ReactNode[] = []
  const boldRe = /\*\*(.+?)\*\*/g
  let lastIndex = 0
  let match: RegExpExecArray | null
  let key = 0

  while ((match = boldRe.exec(line)) !== null) {
    if (match.index > lastIndex) {
      parts.push(line.slice(lastIndex, match.index))
    }
    parts.push(<strong key={`${keyPrefix}-b${key}`}>{match[1]}</strong>)
    key += 1
    lastIndex = boldRe.lastIndex
  }
  if (lastIndex < line.length) {
    parts.push(line.slice(lastIndex))
  }

  return parts
}

export function renderAnswerText(text: string): ReactNode {
  const blocks = parseBlocks(text)

  return (
    <>
      {blocks.map((block, blockIndex) => {
        if (block.type === 'ul') {
          return (
            <ul key={`ul-${blockIndex}`}>
              {block.items.map((item, itemIndex) => (
                <li key={`ul-${blockIndex}-${itemIndex}`}>
                  {renderInline(item, `ul-${blockIndex}-${itemIndex}`)}
                </li>
              ))}
            </ul>
          )
        }

        if (block.type === 'ol') {
          return (
            <ol key={`ol-${blockIndex}`}>
              {block.items.map((item, itemIndex) => (
                <li key={`ol-${blockIndex}-${itemIndex}`}>
                  {renderInline(item, `ol-${blockIndex}-${itemIndex}`)}
                </li>
              ))}
            </ol>
          )
        }

        const content = block.lines.map((line, lineIndex) => (
          <Fragment key={`p-${blockIndex}-${lineIndex}`}>
            {lineIndex > 0 && <br />}
            {renderInline(line, `p-${blockIndex}-${lineIndex}`)}
          </Fragment>
        ))

        return block.heading ? (
          <p key={`p-${blockIndex}`}>
            <strong>{content}</strong>
          </p>
        ) : (
          <p key={`p-${blockIndex}`}>{content}</p>
        )
      })}
    </>
  )
}

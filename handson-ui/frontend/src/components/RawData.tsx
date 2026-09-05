type Props = {
  data: unknown
  label?: string
}

/** 元のイベントをそのまま見せる折りたたみ。整形した表示だけだと、
 *  実際に何が渡って何が返ってきたのかが分からないため。 */
export function RawData({ data, label = '生データを見る' }: Props) {
  if (data === undefined || data === null) return null

  return (
    <details className="raw">
      <summary>{label}</summary>
      <pre>{JSON.stringify(data, null, 2)}</pre>
    </details>
  )
}

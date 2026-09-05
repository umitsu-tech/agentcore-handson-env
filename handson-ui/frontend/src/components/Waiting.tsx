import { useEffect, useState } from 'react'

type Props = {
  label: string
  startedAt: number
}

/** 待っている間に出すもの。止まって見えないように、点滅するドットと
 *  経過秒数を出す。 */
export function Waiting({ label, startedAt }: Props) {
  const [elapsed, setElapsed] = useState(0)

  useEffect(() => {
    const timer = setInterval(() => setElapsed(performance.now() - startedAt), 100)
    return () => clearInterval(timer)
  }, [startedAt])

  return (
    <div className="card">
      <div className="label">{label}</div>
      <div className="waiting">
        <span className="dots">
          <i />
          <i />
          <i />
        </span>
        <span className="elapsed">{(elapsed / 1000).toFixed(1)} 秒</span>
      </div>
    </div>
  )
}

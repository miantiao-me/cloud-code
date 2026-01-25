export interface SSEEvent {
  payload?: {
    type?: string
  }
}

export type SSEEventHandler = (event: SSEEvent) => void

export async function processSSEStream(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  onEvent: SSEEventHandler,
) {
  const decoder = new TextDecoder()
  let buffer = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done)
      break

    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''

    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed.startsWith('data: '))
        continue

      try {
        const event = JSON.parse(trimmed.slice(6)) as SSEEvent
        onEvent(event)
      }
      catch {
        // JSON 解析失败时跳过
      }
    }
  }
}

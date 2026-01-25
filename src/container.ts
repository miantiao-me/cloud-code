import { Container } from '@cloudflare/containers'
import { env } from 'cloudflare:workers'
import { processSSEStream } from './sse'

const PORT = 2633

const containerEnv = Object.fromEntries(
  Object.entries(env).filter(([, value]) => typeof value === 'string'),
)

export class AgentContainer extends Container {
  sleepAfter = '10m'
  defaultPort = PORT

  private _watchPromise?: Promise<void>

  envVars = {
    ...containerEnv,
    PORT: PORT.toString(),
  }

  async watchContainer() {
    try {
      const res = await this.containerFetch('http://container/global/event')
      const reader = res.body?.getReader()
      if (reader) {
        await processSSEStream(reader, (event) => {
          const eventType = event.payload?.type

          if (eventType === 'session.updated') {
            this.renewActivityTimeout()
            console.info('Renewed container activity timeout')
          }

          if (eventType !== 'message.part.updated') {
            console.info('SSE event:', JSON.stringify(event.payload))
          }
        })
      }
    }
    catch (error) {
      console.error('SSE connection error:', error)
			console.info(this._watchPromise)
    }
  }

  override async onStart(): Promise<void> {
    // 不 await，让 SSE 监听在后台运行，避免阻塞 blockConcurrencyWhile
    this._watchPromise = this.watchContainer()
  }
}

const SINGLETON_CONTAINER_ID = 'cf-singleton-container'

export async function forwardRequestToContainer(request: Request) {
  const objectId = env.AGENT_CONTAINER.idFromName(SINGLETON_CONTAINER_ID)
  const container = env.AGENT_CONTAINER.get(objectId, {
    locationHint: 'wnam', // 强制美国西部
  })

  return container.fetch(request)
}

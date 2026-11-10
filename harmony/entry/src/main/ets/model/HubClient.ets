/**
 * HubClient — hub 网关的传输层抽象。
 * 当前实现：局域网直连（@ohos.net.webSocket）。
 * 未来：Ziti app-embedded 模式只需实现同样接口，UI 层零改动。
 */
import { webSocket } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';

export interface AgentInfo {
  id: string;
  title: string;
  description: string;
  running: boolean;
}

export interface ChatMessage {
  role: string; // 'user' | 'assistant'
  text: string;
}

export type ConnState = 'offline' | 'connecting' | 'online';

/** 发给 hub 的帧 */
interface WsFrame {
  type: string;
  agent?: string;
  message?: string;
  id?: string;
}

/** 已保存的服务器配置 */
export interface ServerConfig {
  url: string;
  token: string;
}

export class HubClient {
  private ws: webSocket.WebSocket | null = null;
  private url: string = '';
  private token: string = '';
  private seq = 0;
  private pending = new Map<number, (v: string) => void>(); // seq -> resolve
  private connState: ConnState = 'offline';

  onAgents: (agents: AgentInfo[]) => void = () => {};
  onConnected: (agent: string, history: ChatMessage[]) => void = () => {};
  onDelta: (text: string) => void = () => {};
  onToolEvent: (name: string, args: string) => void = () => {};
  onDone: (text: string) => void = () => {};
  onError: (msg: string) => void = () => {};
  onConnState: (s: ConnState) => void = () => {};

  /** 连接 hub。url 形如 ws://192.168.x.x:8787/ws */
  connect(url: string, token: string): void {
    this.disconnect();
    this.url = url;
    this.token = token;
    this.setConnState('connecting');
    const ws = webSocket.createWebSocket();
    this.ws = ws;
    ws.on('message', (_err, value) => this.handleFrame(String(value)));
    ws.on('close', () => this.setConnState('offline'));
    ws.on('error', () => { this.setConnState('offline'); this.onError('连接错误'); });
    ws.connect(url + '?token=' + encodeURIComponent(token), (_err, ret) => {
      if (!ret) { this.onError('connect 失败'); this.setConnState('offline'); return; }
      this.setConnStateStateOnly('online');
      this.send({ type: 'list' } as WsFrame);
    });
  }

  private setConnStateStateOnly(s: ConnState): void {
    this.connState = s;
    this.onConnState(s);
  }

  private setConnState(s: ConnState): void {
    this.connState = s;
    this.onConnState(s);
  }

  disconnect(): void {
    if (this.ws) {
      try { this.ws.off('message'); this.ws.off('close'); this.ws.off('error'); this.ws.close(); } catch (_e) { }
      this.ws = null;
    }
    this.setConnState('offline');
  }

  get state(): ConnState {
    return this.connState;
  }

  private send(frame: WsFrame): void {
    if (this.ws) { this.ws.send(JSON.stringify(frame)); }
  }

  private handleFrame(raw: string): void {
    let m: Record<string, Object> | null = null;
    try { m = JSON.parse(raw); } catch { return; }
    if (m === null) { return; }
    const t = m['type'] as string;
    switch (t) {
      case 'agents':
        this.onAgents(m['agents'] as AgentInfo[]);
        break;
      case 'connected': {
        const hist = (m['history'] as ChatMessage[]) ?? [];
        this.onConnected(m['agent'] as string, hist);
        break;
      }
      case 'pi_event': {
        const ev = m['event'] as Record<string, Object>;
        const evType = ev['type'] as string;
        if (evType === 'message_update') {
          const delta = (ev['assistantMessageEvent'] as Record<string, Object>)['type'] as string;
          if (delta === 'text_delta') {
            this.onDelta((ev['assistantMessageEvent'] as Record<string, Object>)['delta'] as string);
          }
        } else if (evType === 'tool_execution_start') {
          this.onToolEvent(ev['toolName'] as string, JSON.stringify(ev['arguments'] ?? {}));
        }
        break;
      }
      case 'done':
        this.onDone((m['text'] as string) ?? '');
        break;
      case 'error':
        this.onError((m['message'] as string) ?? 'unknown');
        break;
      default:
        break;
    }
  }

  selectAgent(id: string): void {
    this.send({ type: 'connect', agent: id } as WsFrame);
  }

  prompt(message: string): number {
    this.seq += 1;
    this.send({ type: 'prompt', message: message, id: 'c' + this.seq } as WsFrame);
    return this.seq;
  }

  steer(message: string): void {
    this.send({ type: 'steer', message: message } as WsFrame);
  }

  abort(): void {
    this.send({ type: 'abort' } as WsFrame);
  }
}

/**
 * 连接配置持久化（preferences）
 */
export class ConnStore {
  private pf: preferences.Preferences | null = null;

  async init(context: Context): Promise<void> {
    this.pf = await preferences.getPreferences(context, 'hm_agent_store');
  }

  async getServer(): Promise<ServerConfig> {
    if (!this.pf) { return { url: '', token: '' } as ServerConfig; }
    const cfg: ServerConfig = {
      url: await this.pf.get('url', 'ws://127.0.0.1:8787/ws') as string,
      token: await this.pf.get('token', 'change-me') as string
    };
    return cfg;
  }

  async saveServer(url: string, token: string): Promise<void> {
    if (!this.pf) { return; }
    await this.pf.put('url', url);
    await this.pf.put('token', token);
    await this.pf.flush();
  }
}

export function toast(msg: string): void {
  promptAction.showToast({ message: msg, duration: 2000 });
}

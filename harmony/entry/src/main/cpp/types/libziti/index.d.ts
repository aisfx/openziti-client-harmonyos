export const init: () => void;
export const enroll: (jwt: string, key?: string, cert?: string) => { code: number, identity?: string };
export const loadContext: (identityJson: string) => { code: number, handle: number };
export const waitAuth: (handle: number, timeoutMs: number) => number;
export const dial: (handle: number, service: string) => { code: number, socket: number };
export const send: (socket: number, data: string) => number;
export const recv: (socket: number, timeoutMs: number) => string | undefined;
export const close: (socket: number) => number;
export const lastError: () => string;
export const libShutdown: () => void;

export interface EnrollResult { code: number, identity?: string }
export interface LoadCtxResult { code: number, handle: number }
export interface DialResult { code: number, socket: number }

// TUN mode (VpnExtensionAbility)
export const tunnelStart: (tunFd: number, tunIp: string, dnsIp: string, dnsCidr: string,
  identityFile: string, onEvent: (type: string, json: string) => void) => number;
export const tunnelStop: () => number;
export const tunnelSetLogLevel: (level: number) => number;

import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import connection from '@ohos.net.connection';
import Want from '@ohos.app.ability.Want';
import { commonEventManager } from '@kit.BasicServicesKit';
import ziti from 'libziti_ohos.so';

const TAG = 'ZitiVpnExt';
const SVC_EVENT = 'com.example.myapplication.ZITI_SVC';

interface SvcPortRange { low: number, high: number }
interface SvcIntercept { addresses?: string[], portRanges?: SvcPortRange[], protocols?: string[] }
interface SvcEntry { id: string, name: string, config?: object }
interface ServiceEvent { added_services?: SvcEntry[], removed_services?: SvcEntry[] }
interface ResItem { name: string, targets: string[] }

export default class ZitiVpnExtensionAbility extends VpnExtensionAbility {
  private vpnConn?: vpnExtension.VpnConnection;
  private started = false;
  private services: Map<string, SvcEntry> = new Map();

  onCreate(want: Want): void {
    console.info(`${TAG} onCreate: ${JSON.stringify(want.parameters ?? {})}`);
    this.startVpn(want);
  }

  private async startVpn(want: Want): Promise<void> {
    const params = want.parameters ?? {};
    const identityFile = (params.identityFile ?? '') as string;
    const tunIp = (params.tunIp ?? '100.64.0.1') as string;
    const dnsIp = (params.dnsIp ?? '100.64.0.2') as string;
    const dnsCidr = (params.dnsCidr ?? '100.64.0.1/10') as string;

    if (identityFile === '') {
      console.error(`${TAG} missing identityFile param`);
      return;
    }
    if (this.started) {
      console.warn(`${TAG} already started`);
      return;
    }

    try {
      const conn = vpnExtension.createVpnConnection(this.context);
      this.vpnConn = conn;

      const addr: connection.LinkAddress = {
        address: { address: tunIp, family: 1 },
        prefixLength: 10
      };
      const dest: connection.LinkAddress = {
        address: { address: '100.64.0.0', family: 1 },
        prefixLength: 10
      };
      const gw: connection.NetAddress = { address: '0.0.0.0', family: 1 };
      const route: connection.RouteInfo = {
        destination: dest, interface: '', gateway: gw,
        hasGateway: false, isDefaultRoute: false
      };

      const config: vpnExtension.VpnConfig = {
        addresses: [addr],
        routes: [route],
        dnsAddresses: [dnsIp],
        mtu: 1400,
        isIPv4Accepted: true,
        isBlocking: false
      };

      const fd: number = await conn.create(config);
      console.info(`${TAG} TUN fd=${fd}`);

      const rc: number = ziti.tunnelStart(fd, tunIp, dnsIp, dnsCidr, identityFile,
        (type: string, json: string) => {
          console.info(`${TAG} event ${type}: ${json.substring(0, 300)}`);
          if (type === 'service') {
            this.onServiceEvent(json);
          }
        });
      if (rc !== 0) {
        console.error(`${TAG} tunnelStart rc=${rc}`);
        await conn.destroy();
        this.vpnConn = undefined;
        return;
      }
      this.started = true;
      console.info(`${TAG} tunnel started`);
    } catch (e) {
      console.error(`${TAG} error: ${(e as Error).message}`);
    }
  }

  /** 解析 ServiceEvent，维护服务表并广播给主进程显示 */
  private onServiceEvent(json: string): void {
    try {
      const ev = JSON.parse(json) as ServiceEvent;
      const added = ev.added_services ?? [];
      const removed = ev.removed_services ?? [];
      added.forEach((s: SvcEntry) => { this.services.set(s.id, s); });
      removed.forEach((s: SvcEntry) => { this.services.delete(s.id); });

      const list: ResItem[] = [];
      this.services.forEach((s: SvcEntry) => {
        const targets: string[] = [];
        const cfg = s.config as Record<string, SvcIntercept> | undefined;
        const itc = cfg?.['intercept.v1'];
        if (itc && itc.addresses && itc.addresses.length > 0) {
          const ports = (itc.portRanges ?? []).map((p: SvcPortRange) =>
            p.low === p.high ? `${p.low}` : `${p.low}-${p.high}`);
          const portStr = ports.join(',');
          itc.addresses.forEach((a: string) => {
            targets.push(portStr !== '' ? `${a}:${portStr}` : a);
          });
        }
        list.push({ name: s.name, targets });
      });

      const pub: commonEventManager.CommonEventPublishData = { data: JSON.stringify(list) };
      commonEventManager.publish(SVC_EVENT, pub, (err) => {
        if (err) {
          console.error(`${TAG} publish svc failed: ${err.message}`);
        }
      });
    } catch (e) {
      console.error(`${TAG} parse service event failed: ${(e as Error).message}`);
    }
  }

  onDestroy(): void {
    console.info(`${TAG} onDestroy`);
    try {
      ziti.tunnelStop();
    } catch (e) {
      console.error(`${TAG} tunnelStop: ${(e as Error).message}`);
    }
    this.vpnConn?.destroy().catch(() => {
    });
    this.vpnConn = undefined;
    this.started = false;
  }
}

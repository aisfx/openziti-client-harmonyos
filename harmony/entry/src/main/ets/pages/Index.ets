import ziti from 'libziti_ohos.so';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTs';
import { BusinessError } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import Want from '@ohos.app.ability.Want';
import common from '@ohos.app.ability.common';

interface EnrollResult { code: number, identity?: string }
interface LoadCtxResult { code: number, handle: number }
interface DialResult { code: number, socket: number }
interface ResTarget { name: string, targets: string[] }

const IDENTITY_FILE = 'hm-identity.json';
const SVC_EVENT = 'com.example.myapplication.ZITI_SVC';
const MAX_LOG_LINES: number = 500;

// ===== 主题色 =====
const COL_BG: string = '#0B0F16';
const COL_CARD: string = '#141B26';
const COL_CARD_IN: string = '#0E141D';
const COL_BORDER: string = '#223042';
const COL_TEXT1: string = '#E6EDF3';
const COL_TEXT2: string = '#9AA7B8';
const COL_TEXT3: string = '#5B6B80';
const COL_GREEN: string = '#22C55E';
const COL_RED: string = '#EF4444';
const COL_YELLOW: string = '#F59E0B';
const COL_BLUE: string = '#3B82F6';
const COL_TEAL: string = '#06B6D4';
const COL_DIM_RED: string = '#3A1A22';
const COL_DIM_GREEN: string = '#12291B';
const COL_DIM_BLUE: string = '#13203A';
const COL_DIM_TEAL: string = '#0E2B31';
const COL_BAR_BG: string = '#0D1219';

// Tab 索引
const TAB_HOME: number = 0;
const TAB_RES: number = 1;
const TAB_TOOLS: number = 2;
const TAB_LOG: number = 3;

@Entry
@Component
struct Index {
  @State private logLines: string[] = [];
  @State private jwtText: string = '';
  @State private identityName: string = '';
  @State private identityJson: string = '';
  @State private handle: number = 0;
  @State private connected: boolean = false;
  @State private bgOn: boolean = false;
  @State private vpnOn: boolean = false;
  @State private svcInput: string = 'test.aaa.com';
  @State private resources: ResTarget[] = [];
  @State private currentTab: number = TAB_HOME;
  private svcSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  private socket: number = -1;
  private logScroll: Scroller = new Scroller();
  private tabCtrl: TabsController = new TabsController();
  private appCtx: Context | null = null;

  aboutToAppear(): void {
    this.appCtx = this.getUIContext().getHostContext() as Context;
    this.log('ready');
    this.tryAutoLoad();
    this.subscribeServices();
  }

  aboutToDisappear(): void {
    this.unsubscribeServices();
  }

  /** 订阅 VPN 扩展推送的服务列表 */
  private subscribeServices(): void {
    const info: commonEventManager.CommonEventSubscribeInfo = {
      events: [SVC_EVENT]
    };
    commonEventManager.createSubscriber(info).then((sub: commonEventManager.CommonEventSubscriber) => {
      this.svcSubscriber = sub;
      commonEventManager.subscribe(sub, (err, data) => {
        if (err) {
          this.log(`svc subscribe err: ${err.message}`);
          return;
        }
        if (data?.data) {
          try {
            const list = JSON.parse(data.data) as ResTarget[];
            this.resources = list;
            this.log(`resources updated: ${list.length} service(s)`);
          } catch (e) {
            this.log(`svc parse err: ${(e as Error).message}`);
          }
        }
      });
    }).catch((e: BusinessError) => this.log(`subscribe failed: ${e.message}`));
  }

  private unsubscribeServices(): void {
    if (this.svcSubscriber !== null) {
      commonEventManager.unsubscribe(this.svcSubscriber);
      this.svcSubscriber = null;
    }
  }

  /** 点击资源项：用系统浏览器打开（隐式 Want） */
  private openResource(target: string): void {
    const m = target.match(/^([^:]+):(\d+)$/);
    let url = '';
    if (m) {
      url = `http://${m[1]}${m[2] !== '80' ? ':' + m[2] : ''}/`;
    } else {
      url = `http://${target}/`;
    }
    this.log(`open ${url}`);
    const ctx = this.appCtx as common.UIAbilityContext;
    if (ctx === null) { return; }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url,
        type: 'text/html'
      } as Want;
      ctx.startAbility(want).catch((e: BusinessError) => {
        this.log(`open failed: ${e.message}`);
      });
    } catch (e) {
      this.log(`open failed: ${(e as Error).message}`);
    }
  }

  onPageShow(): void {
    this.log('app foreground');
  }

  log(msg: string): void {
    const now = new Date();
    const ts = `${now.getHours()}:${now.getMinutes()}:${now.getSeconds()}`;
    this.logLines.push(`[${ts}] ${msg}`);
    if (this.logLines.length > MAX_LOG_LINES) {
      this.logLines.splice(0, this.logLines.length - MAX_LOG_LINES);
    }
    console.info(`ZITI ${msg}`);
    if (this.currentTab === TAB_LOG) {
      setTimeout(() => {
        this.logScroll.scrollEdge(Edge.Bottom);
      }, 50);
    }
  }

  /** 日志按级别着色 */
  private logColor(line: string): string {
    const l = line.toLowerCase();
    if (l.includes('err') || l.includes('fail') || l.includes('canceled') || l.includes('no response')) {
      return COL_RED;
    }
    if (l.includes('authed') || l.includes('established') || l.includes('saved') ||
      l.includes('started') || l.includes('updated') || l.includes('enrolled')) {
      return COL_GREEN;
    }
    if (l.includes('waiting') || l.includes('disconnect') || l.includes('deleted') || l.includes('stop')) {
      return COL_YELLOW;
    }
    return '#8FA3B8';
  }

  // ==================== UI 组件 ====================

  @Builder
  HeaderBar() {
    Row({ space: 14 }) {
      Text('Z')
        .width(42)
        .height(42)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .backgroundColor(COL_BLUE)
        .borderRadius(13)
      Column({ space: 2 }) {
        Text('OpenZiti Tunnel')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(COL_TEXT1)
        Text('HarmonyOS · Secure Overlay Network')
          .fontSize(11)
          .fontColor(COL_TEXT3)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.vpnOn ? 'VPN ON' : 'OFF')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.vpnOn ? COL_GREEN : COL_TEXT3)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(this.vpnOn ? COL_DIM_GREEN : '#1A2230')
        .borderRadius(12)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  TabItem(icon: string, label: string, idx: number) {
    Column({ space: 3 }) {
      Text(icon)
        .fontSize(20)
        .opacity(this.currentTab === idx ? 1 : 0.45)
      Text(label)
        .fontSize(11)
        .fontWeight(this.currentTab === idx ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === idx ? COL_TEAL : COL_TEXT3)
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
  }

  @Builder
  StatusTile(icon: string, label: string, on: boolean, onColor: string, onBg: string) {
    Column({ space: 6 }) {
      Text(icon).fontSize(20)
      Text(label).fontSize(11).fontColor(COL_TEXT2)
      Text(on ? 'ACTIVE' : 'OFF')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(on ? onColor : COL_TEXT3)
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .backgroundColor(on ? onBg : '#1A2230')
        .borderRadius(9)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .backgroundColor(COL_CARD)
    .borderRadius(16)
    .border({ width: 1, color: COL_BORDER })
  }

  @Builder
  StatusTiles() {
    Row({ space: 10 }) {
      Column() {
        this.StatusTile('🔗', 'Tunnel', this.connected, COL_GREEN, COL_DIM_GREEN)
      }.layoutWeight(1)
      Column() {
        this.StatusTile('🛡️', 'System VPN', this.vpnOn, COL_TEAL, COL_DIM_TEAL)
      }.layoutWeight(1)
      Column() {
        this.StatusTile('⚡', 'Keep-Alive', this.bgOn, COL_YELLOW, '#33270F')
      }.layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  SectionTitle(icon: string, title: string, hint: string) {
    Row({ space: 8 }) {
      Text(icon).fontSize(15)
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COL_TEXT1)
      Blank()
      Text(hint).fontSize(11).fontColor(COL_TEXT3)
    }
    .width('100%')
  }

  @Builder
  CardIdentity() {
    Column({ space: 10 }) {
      this.SectionTitle('🪪', 'Identity', this.identityName !== '' ? '已导入' : '未导入')

      Button('选择身份文件（JWT / identity.json）')
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(COL_BLUE)
        .borderRadius(12)
        .onClick(() => { this.pickFile(); })

      if (this.identityName !== '') {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('已保存身份').fontSize(11).fontColor(COL_TEXT3)
            Text(this.identityName)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(COL_GREEN)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('删除')
            .height(34)
            .fontSize(13)
            .fontColor(COL_RED)
            .backgroundColor(COL_DIM_RED)
            .borderRadius(10)
            .onClick(() => { this.deleteIdentity(); })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(COL_CARD_IN)
        .borderRadius(12)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COL_CARD)
    .borderRadius(16)
    .border({ width: 1, color: COL_BORDER })
  }

  @Builder
  CardVpn() {
    Column({ space: 10 }) {
      this.SectionTitle('🛡️', 'System VPN (TUN)', '浏览器流量走隧道')

      Button(this.vpnOn ? '停止 VPN' : '启动 VPN')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor(this.vpnOn ? COL_RED : COL_TEAL)
        .borderRadius(12)
        .onClick(() => {
          if (this.vpnOn) { this.doVpnStop(); } else { this.doVpnStart(); }
        })

      Text(this.vpnOn ? '100.64.0.0/10 已路由 · DNS 100.64.0.2' : '未运行 · 启动后浏览器即可访问 ziti 服务')
        .fontSize(11)
        .fontColor(this.vpnOn ? COL_TEAL : COL_TEXT3)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COL_CARD)
    .borderRadius(16)
    .border({ width: 1, color: COL_BORDER })
  }

  @Builder
  CardTunnel() {
    Column({ space: 10 }) {
      this.SectionTitle('🔗', 'App Tunnel', '应用内嵌隧道')

      Button(this.connected ? '断开隧道' : '连接隧道')
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(this.connected ? COL_RED : COL_GREEN)
        .borderRadius(12)
        .onClick(() => {
          if (this.connected) { this.doDisconnect(); } else { this.doConnect(); }
        })

      Text(this.connected ? '隧道已建立 · 可进行拨测' : '未连接')
        .fontSize(11)
        .fontColor(this.connected ? COL_GREEN : COL_TEXT3)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COL_CARD)
    .borderRadius(16)
    .border({ width: 1, color: COL_BORDER })
  }

  @Builder
  CardDial() {
    Column({ space: 10 }) {
      this.SectionTitle('📡', 'Dial Test', '需先连接 App Tunnel')

      Row({ space: 8 }) {
        TextInput({ text: this.svcInput, placeholder: 'service name' })
          .layoutWeight(1)
          .height(42)
          .fontSize(13)
          .fontColor(COL_TEXT1)
          .placeholderColor(COL_TEXT3)
          .backgroundColor(COL_CARD_IN)
          .borderRadius(10)
          .onChange((v: string) => { this.svcInput = v; })

        Button('拨测')
          .height(42)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor(COL_BLUE)
          .borderRadius(10)
          .onClick(() => { this.doDialTest(); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('结果输出到「日志」页')
        .fontSize(11)
        .fontColor(COL_TEXT3)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COL_CARD)
    .borderRadius(16)
    .border({ width: 1, color: COL_BORDER })
  }

  // ==================== 各分页 ====================

  @Builder
  PageHome() {
    Scroll() {
      Column({ space: 14 }) {
        this.StatusTiles()
        this.CardIdentity()
        this.CardVpn()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 32 })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .height('100%')
    .width('100%')
    .align(Alignment.TopStart)
  }

  @Builder
  PageResources() {
    Column() {
      // 顶部摘要
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text('可访问资源')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(COL_TEXT1)
          Text(this.vpnOn ? 'VPN 运行中 · 点击地址直接打开' : 'VPN 未启动')
            .fontSize(11)
            .fontColor(this.vpnOn ? COL_TEAL : COL_TEXT3)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(`${this.resources.length}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resources.length > 0 ? COL_TEAL : COL_TEXT3)
          .constraintSize({ minWidth: 52 })
          .textAlign(TextAlign.Center)
          .padding({ top: 6, bottom: 6 })
          .backgroundColor(COL_CARD)
          .borderRadius(14)
          .border({ width: 1, color: COL_BORDER })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      if (this.resources.length === 0) {
        Column({ space: 14 }) {
          Text('🌐').fontSize(52)
          Text(this.vpnOn ? '等待服务列表下发…' : '暂无可访问资源')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(COL_TEXT2)
          Text('启动 System VPN 后，这里会显示\n当前身份可访问的全部 ziti 服务')
            .fontSize(12)
            .fontColor(COL_TEXT3)
            .textAlign(TextAlign.Center)
            .lineHeight(20)
          if (!this.vpnOn) {
            Button('启动 System VPN')
              .height(42)
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor(COL_TEAL)
              .borderRadius(12)
              .onClick(() => { this.doVpnStart(); })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: 80 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.resources, (r: ResTarget) => {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Text('▣')
                    .fontSize(13)
                    .fontColor(COL_TEAL)
                  Text(r.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(COL_TEXT1)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')

                ForEach(r.targets, (t: string) => {
                  Row({ space: 8 }) {
                    Text('➜').fontSize(11).fontColor(COL_TEAL)
                    Text(t)
                      .fontSize(13)
                      .fontColor(COL_TEAL)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .onClick(() => { this.openResource(t); })
                    Text('打开')
                      .fontSize(11)
                      .fontColor(COL_BLUE)
                      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                      .backgroundColor(COL_DIM_BLUE)
                      .borderRadius(9)
                      .onClick(() => { this.openResource(t); })
                  }
                  .width('100%')
                }, (t: string) => t)
              }
              .width('100%')
              .padding(14)
              .backgroundColor(COL_CARD)
              .borderRadius(14)
              .border({ width: 1, color: COL_BORDER })
            }, (r: ResTarget) => r.name)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 32 })
        }
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PageTools() {
    Scroll() {
      Column({ space: 14 }) {
        this.CardTunnel()
        this.CardDial()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 32 })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .height('100%')
    .width('100%')
    .align(Alignment.TopStart)
  }

  @Builder
  PageLog() {
    Column() {
      Row({ space: 8 }) {
        Text('📜 运行日志')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(COL_TEXT1)
        Blank()
        Text(`${this.logLines.length} 条`)
          .fontSize(11)
          .fontColor(COL_TEXT3)
        Text('清空')
          .fontSize(12)
          .fontColor(COL_TEXT2)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor('#1A2230')
          .borderRadius(9)
          .onClick(() => { this.logLines = []; })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      Scroll(this.logScroll) {
        Column() {
          if (this.logLines.length === 0) {
            Text('暂无日志')
              .fontSize(12)
              .fontColor(COL_TEXT3)
              .padding(12)
          } else {
            ForEach(this.logLines, (line: string, idx: number) => {
              Text(line)
                .fontSize(11)
                .fontFamily('monospace')
                .fontColor(this.logColor(line))
                .width('100%')
            }, (line: string, idx: number) => `${idx}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(12)
      }
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .width('100%')
      .margin({ left: 16, right: 16, bottom: 12 })
      .align(Alignment.TopStart)
      .backgroundColor(COL_CARD_IN)
      .borderRadius(14)
      .border({ width: 1, color: COL_BORDER })
    }
    .width('100%')
    .height('100%')
  }

  build(): void {
    Column() {
      // 顶部固定 Header
      Column() {
        this.HeaderBar()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })

      Divider()
        .color(COL_BORDER)
        .strokeWidth(1)
        .width('100%')

      // 主体分页
      Tabs({ barPosition: BarPosition.End, controller: this.tabCtrl }) {
        TabContent() {
          this.PageHome()
        }
        .tabBar(this.TabItem('🏠', '首页', TAB_HOME))

        TabContent() {
          this.PageResources()
        }
        .tabBar(this.TabItem('🌐', '资源', TAB_RES))

        TabContent() {
          this.PageTools()
        }
        .tabBar(this.TabItem('🛠️', '工具', TAB_TOOLS))

        TabContent() {
          this.PageLog()
        }
        .tabBar(this.TabItem('📜', '日志', TAB_LOG))
      }
      .layoutWeight(1)
      .barHeight(64)
      .barBackgroundColor(COL_BAR_BG)
      .onChange((index: number) => {
        this.currentTab = index;
        if (index === TAB_LOG) {
          setTimeout(() => {
            this.logScroll.scrollEdge(Edge.Bottom);
          }, 50);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COL_BG)
  }

  // ==================== 业务逻辑 ====================

  /** 从文件选择器导入身份文件 */
  async pickFile(): Promise<void> {
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['json', 'jwt', 'txt', 'pem'];
      const docPicker = new picker.DocumentViewPicker();
      const uris: string[] = await docPicker.select(opt);
      if (uris.length === 0) { this.log('pick canceled'); return; }
      const uri = uris[0];
      const raw = uri.split('/').pop() ?? uri;
      const name = decodeURIComponent(raw.split('.txt')[0]);
      this.log(`picked: ${name}`);
      const text = this.readFileText(uri);
      if (text === '') { this.log('file is empty'); return; }
      this.jwtText = text.trim();
      this.identityName = name;
      this.log(`loaded ${this.jwtText.length} chars`);
      this.doEnrollOrLoad();
    } catch (e) {
      const err = e as BusinessError;
      this.log(`pick failed: ${err.message}`);
    }
  }

  private readFileText(uriOrPath: string): string {
    const file = fileIo.openSync(uriOrPath, fileIo.OpenMode.READ_ONLY);
    try {
      const st = fileIo.statSync(file.fd);
      const buf = new ArrayBuffer(st.size);
      fileIo.readSync(file.fd, buf);
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
    } finally {
      fileIo.closeSync(file);
    }
  }

  private identityPath(): string {
    return `${this.appCtx?.filesDir ?? ''}/${IDENTITY_FILE}`;
  }

  private saveIdentity(): void {
    if (this.appCtx === null || this.identityJson === '') { return; }
    try {
      const p = this.identityPath();
      const file = fileIo.openSync(p,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, this.identityJson);
      fileIo.closeSync(file);
      this.log('identity saved');
    } catch (e) {
      const err = e as BusinessError;
      this.log(`save failed: ${err.message}`);
    }
  }

  /** 启动时自动恢复：读已存身份 -> loadContext -> 建隧道 */
  tryAutoLoad(): void {
    if (this.appCtx === null) { return; }
    try {
      const p = this.identityPath();
      if (!fileIo.accessSync(p)) { return; }
      const text = this.readFileText(p).trim();
      if (text === '') { return; }
      this.log('found saved identity, connecting...');
      this.jwtText = text;
      this.identityName = IDENTITY_FILE;
      this.doEnrollOrLoad();
      if (this.handle !== 0) { this.doConnect(); }
    } catch (e) {
      const err = e as BusinessError;
      this.log(`auto load failed: ${err.message}`);
    }
  }

  /** 删除已保存的身份文件，清除状态 */
  deleteIdentity(): void {
    if (this.appCtx === null) { return; }
    if (this.connected) { this.doDisconnect(); }
    if (this.vpnOn) { this.doVpnStop(); }
    try {
      const p = this.identityPath();
      if (fileIo.accessSync(p)) {
        fileIo.unlinkSync(p);
        this.log(`identity file deleted: ${IDENTITY_FILE}`);
      } else {
        this.log('no saved identity');
      }
    } catch (e) {
      const err = e as BusinessError;
      this.log(`delete failed: ${err.message}`);
    }
    this.identityJson = '';
    this.jwtText = '';
    this.identityName = '';
    this.handle = 0;
  }

  doEnrollOrLoad(): void {
    if (this.jwtText.trim() === '') { this.log('no identity, pick a file first'); return; }
    ziti.init();
    if (this.jwtText.includes('ztAPI')) {
      const r = ziti.loadContext(this.jwtText) as LoadCtxResult;
      this.log(`loadContext code=${r.code}`);
      if (r.code === 0) {
        this.identityJson = this.jwtText;
        this.handle = r.handle;
        this.log(`loaded, handle=${r.handle}`);
        this.saveIdentity();
      } else {
        this.log(`err: ${ziti.lastError()}`);
      }
    } else {
      this.log('JWT detected, enrolling...');
      const r = ziti.enroll(this.jwtText.trim()) as EnrollResult;
      this.log(`enroll code=${r.code}`);
      if (r.code === 0 && r.identity) {
        this.identityJson = r.identity;
        this.log(`enrolled, identity len=${r.identity.length}`);
        const lr = ziti.loadContext(this.identityJson) as LoadCtxResult;
        if (lr.code === 0) {
          this.handle = lr.handle;
          this.saveIdentity();
        } else {
          this.log(`loadContext failed: ${ziti.lastError()}`);
        }
      } else {
        this.log(`enroll failed: ${ziti.lastError()}`);
      }
    }
  }

  /** 启动系统 VPN(VpnExtensionAbility + TUN)：路由 100.64.0.0/10，浏览器可访问 ziti 服务 */
  async doVpnStart(): Promise<void> {
    if (this.appCtx === null) { this.log('no context'); return; }
    if (this.identityJson === '' && this.jwtText === '') { this.log('import identity first'); return; }
    try {
      const want: Want = {
        bundleName: 'com.example.myapplication',
        abilityName: 'ZitiVpnExtensionAbility',
        parameters: {
          identityFile: this.identityPath(),
          tunIp: '100.64.0.1',
          dnsIp: '100.64.0.2',
          dnsCidr: '100.64.0.1/10'
        }
      };
      await vpnExtension.startVpnExtensionAbility(want);
      this.vpnOn = true;
      this.resources = [];
      this.log('VPN extension started');
      // 跳转到资源页等待服务下发
      this.tabCtrl.changeIndex(TAB_RES);
    } catch (e) {
      const err = e as BusinessError;
      this.log(`vpn start failed: ${err.message} (${err.code})`);
    }
  }

  async doVpnStop(): Promise<void> {
    try {
      const want: Want = {
        bundleName: 'com.example.myapplication',
        abilityName: 'ZitiVpnExtensionAbility'
      };
      await vpnExtension.stopVpnExtensionAbility(want);
      this.vpnOn = false;
      this.resources = [];
      this.log('VPN stopped');
    } catch (e) {
      const err = e as BusinessError;
      this.log(`vpn stop failed: ${err.message}`);
    }
  }

  doConnect(): void {
    if (this.identityJson === '') { this.log('import identity first'); return; }
    if (this.handle === 0) {
      const r = ziti.loadContext(this.identityJson) as LoadCtxResult;
      if (r.code !== 0) { this.log(`loadContext failed: ${ziti.lastError()}`); return; }
      this.handle = r.handle;
    }
    this.log('waiting for auth...');
    const rc: number = ziti.waitAuth(this.handle, 10000);
    if (rc === 0) {
      this.connected = true;
      this.log('AUTHED - tunnel established');
      this.startBackground();
    } else {
      this.log(`auth failed rc=${rc}: ${ziti.lastError()}`);
    }
  }

  /** 断开隧道：关 socket + 停后台保活 */
  doDisconnect(): void {
    if (this.socket >= 0) {
      ziti.close(this.socket);
      this.socket = -1;
    }
    if (this.handle !== 0) {
      ziti.libShutdown();
      this.handle = 0;
    }
    this.connected = false;
    this.log('disconnected');
    this.stopBackground();
  }

  /** 申请 DATA_TRANSFER 长时任务：最小化/锁屏后隧道保持存活 */
  async startBackground(): Promise<void> {
    if (this.bgOn || this.appCtx === null) { return; }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: 'com.example.myapplication',
          abilityName: 'EntryAbility'
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      };
      const want: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(this.appCtx as Context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, want);
      this.bgOn = true;
      this.log('background keepalive ON');
    } catch (e) {
      const err = e as BusinessError;
      this.log(`bg err: ${err.message}`);
    }
  }

  stopBackground(): void {
    if (!this.bgOn || this.appCtx === null) { return; }
    backgroundTaskManager.stopBackgroundRunning(this.appCtx as Context)
      .then(() => { this.bgOn = false; this.log('background keepalive OFF'); })
      .catch((e: BusinessError) => this.log(`bg stop failed: ${e.message}`));
  }

  doDialTest(): void {
    if (!this.connected) { this.log('connect first'); return; }
    this.log(`dialing ${this.svcInput}...`);
    const r = ziti.dial(this.handle, this.svcInput) as DialResult;
    if (r.code !== 0) { this.log(`dial failed: ${r.code} ${ziti.lastError()}`); return; }
    this.socket = r.socket;
    this.log(`socket=${r.socket}, sending...`);
    const sent: number = ziti.send(this.socket, 'hello from harmony tablet');
    this.log(`sent ${sent} bytes, waiting response...`);
    const got: string | undefined = ziti.recv(this.socket, 5000);
    if (got !== undefined) {
      this.log(`recv: ${got}`);
    } else {
      this.log('no response in 5s');
    }
  }

  doClose(): void {
    if (this.socket >= 0) {
      ziti.close(this.socket);
      this.log('socket closed');
      this.socket = -1;
    } else {
      this.log('no socket');
    }
  }
}

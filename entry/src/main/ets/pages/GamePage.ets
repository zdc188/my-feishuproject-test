/**
 * 游戏主页面：承载 Canvas 渲染区、HUD、虚拟摇杆（左下角）、动作按键（右下角）
 * 与状态覆盖层（DES-003/008/009/010）。
 * 触控区域按屏幕百分比 + 安全区避让定位（DES-010）。
 */

import {
  GameEngine, GameStateMachine, GameState, GameEvent,
  MapSystem, MapData, parseMapData, MapLoader,
  ResourceSystem, ResourceLoader, ResourcePriority,
  Player, joystickToAxis
} from 'gamecore';
import { CanvasRenderAdapter } from '../render/CanvasRenderAdapter';

const TICK_MS = 16;
const LOGICAL_W = 1280;
const LOGICAL_H = 720;

class PassthroughChunkLoader implements MapLoader {
  loadChunk(_index: number): Promise<void> {
    // P0 阶段地图 tile 数据整体常驻（本地 JSON 已解析），chunk 资源加载为引用切换
    return Promise.resolve();
  }
  releaseChunk(_index: number): void {
  }
}

class RawfileResourceLoader implements ResourceLoader {
  load(_key: string): Promise<object> {
    // 占位资源阶段：所有资源句柄直接成功（正式资源接入后替换为真实 media 加载）
    return Promise.resolve({ placeholder: true });
  }
}

@Entry
@Component
struct GamePage {
  @State displayState: string = GameState.BOOTING;
  @State loadProgress: number = 0;
  @State screenW: number = LOGICAL_W;
  @State screenH: number = LOGICAL_H;
  private stateMachine: GameStateMachine = new GameStateMachine();
  private engine: GameEngine | null = null;
  private renderCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private loopId: number = -1;
  private lastTime: number = 0;
  private mapData: MapData | null = null;
  private resources: ResourceSystem | null = null;

  aboutToAppear(): void {
    this.stateMachine.onStateChange((_from: GameState, to: GameState) => {
      this.displayState = to;
    });
    this.loadMapAndStart();
  }

  aboutToDisappear(): void {
    this.stopLoop();
  }

  private loadMapAndStart(): void {
    try {
      this.loadMapJson();
    } catch (e) {
      console.error(`[GamePage] map parse failed, use builtin map: ${JSON.stringify(e)}`);
      this.useBuiltinMap();
    }
    if (this.mapData === null) {
      this.useBuiltinMap();
    }
    // 启动页就绪 -> 资源加载中（DES-009：Ability onWindowStageCreate 完成、页面加载完成）
    this.stateMachine.fire(GameEvent.WINDOW_STAGE_READY);
    this.loadCoreResources();
  }

  private loadMapJson(): void {
    const ctx = getContext(this);
    const rm = ctx.resourceManager;
    const bytes = rm.getRawFileContentSync('map_level1.json');
    const text = String.fromCharCode(...bytes);
    this.mapData = parseMapData(JSON.parse(text));
  }

  private useBuiltinMap(): void {
    // 内置兜底地图：一条 16x8 的地面平台（DES-006 兜底精神：地图数据缺失不崩溃）
    const rows: string[] = [];
    for (let r = 0; r < 8; r++) {
      rows.push(r === 7 ? '################' : '................');
    }
    this.mapData = parseMapData({
      tileW: 32, tileH: 32, cols: 16, rows: 8, chunkSize: 16,
      layers: { collision: rows },
      playerSpawn: { x: 64, y: 128 }
    });
  }

  private async loadCoreResources(): Promise<void> {
    this.resources = new ResourceSystem(new RawfileResourceLoader(), 32);
    // P0 核心资源启动阻塞加载（此处为占位清单；进度条走满后进入运行中）
    const coreKeys: string[] = ['atlas/player', 'atlas/tiles', 'ui/hud', 'audio/jump', 'audio/bgm'];
    for (let i = 0; i < coreKeys.length; i++) {
      await this.resources.load(coreKeys[i], i < 3 ? ResourcePriority.CORE : ResourcePriority.AUDIO);
      this.loadProgress = Math.round(((i + 1) / coreKeys.length) * 100);
    }
    this.startEngine();
    // 核心资源加载完成 -> 运行中
    this.stateMachine.fire(GameEvent.CORE_RESOURCE_READY);
  }

  private startEngine(): void {
    if (this.mapData === null) {
      return;
    }
    const map = new MapSystem(this.mapData, new PassthroughChunkLoader(), LOGICAL_W);
    map.updateCamera(this.mapData.playerSpawn.x);
    const player = new Player();
    player.x = this.mapData.playerSpawn.x;
    player.y = this.mapData.playerSpawn.y;
    const engine = new GameEngine(map, player, {
      viewportW: LOGICAL_W, viewportH: LOGICAL_H
    });
    this.engine = engine;
    engine.setRenderer(new CanvasRenderAdapter(this.renderCtx));
    engine.bus.on('trigger', (payload: object) => {
      console.info(`[GamePage] trigger hit: ${JSON.stringify(payload)}`);
    });
    engine.bus.on('enemyHit', (payload: object) => {
      console.info(`[GamePage] enemy hit: ${JSON.stringify(payload)}`);
    });
    engine.map.updateChunks();
    this.lastTime = Date.now();
    this.startLoop();
  }

  private startLoop(): void {
    if (this.loopId >= 0) {
      return;
    }
    this.loopId = setInterval(() => {
      if (this.engine === null) {
        return;
      }
      const now = Date.now();
      const dt = now - this.lastTime;
      this.lastTime = now;
      this.engine.tick(dt);
    }, TICK_MS);
  }

  private stopLoop(): void {
    if (this.loopId >= 0) {
      clearInterval(this.loopId);
      this.loopId = -1;
    }
  }

  private onPause(): void {
    if (this.stateMachine.current() === GameState.RUNNING) {
      this.stateMachine.fire(GameEvent.PAUSE);
      this.stopLoop();
      this.engine?.pause();
    }
  }

  private onResume(): void {
    if (this.stateMachine.current() === GameState.PAUSED) {
      this.stateMachine.fire(GameEvent.RESUME);
      this.engine?.resume();
      this.lastTime = Date.now();
      this.startLoop();
    }
  }

  private onQuit(): void {
    if (this.stateMachine.current() === GameState.PAUSED || this.stateMachine.current() === GameState.RUNNING) {
      this.stateMachine.fire(GameEvent.QUIT);
      this.stopLoop();
    }
  }

  private onRestart(): void {
    if (this.stateMachine.current() === GameState.ENDED) {
      this.stateMachine.reset();
      this.displayState = GameState.BOOTING;
      this.loadProgress = 0;
      this.loadMapAndStart();
    }
  }

  /** 摇杆/按键输入写回（DES-003：输入汇聚到 InputSystem 快照） */
  private onJoystickAxis(axis: number): void {
    this.engine?.input.setMoveAxis(axis);
  }

  private onJumpDown(): void {
    this.engine?.input.setJump(true);
  }

  private onJumpUp(): void {
    this.engine?.input.setJump(false);
  }

  build(): void {
    Stack({ alignContent: Alignment.BottomStart }) {
      // 游戏渲染区（全屏 Canvas，逻辑分辨率 1280x720 按屏幕缩放）
      Canvas(this.renderCtx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          const w = this.renderCtx.width;
          const h = this.renderCtx.height;
          this.screenW = w > 0 ? w : LOGICAL_W;
          this.screenH = h > 0 ? h : LOGICAL_H;
          this.engine?.setViewport(this.screenW, this.screenH);
        })

      // HUD 右上角：暂停按钮
      Row() {
        Blank()
        Button($r('app.string.btn_pause'))
          .fontSize(16)
          .width(72).height(36)
          .onClick(() => this.onPause())
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 12, right: 16 })
      .align(Alignment.Top)

      // 摇杆：屏幕左下角（安全区 + 百分比定位，DES-010）
      JoystickControl({
        size: 140,
        onAxis: (axis: number) => this.onJoystickAxis(axis)
      })
        .position({ x: 24, y: '78%' })

      // 动作按键：右下角
      JumpButton({
        onPressDown: () => this.onJumpDown(),
        onPressUp: () => this.onJumpUp()
      })
        .position({ x: '78%', y: '76%' })

      // 资源加载覆盖层
      if (this.displayState === GameState.BOOTING || this.displayState === GameState.LOADING) {
        Column({ space: 12 }) {
          Text($r('app.string.loading_text'))
            .fontColor(Color.White)
            .fontSize(18)
          Progress({ value: this.loadProgress, total: 100 })
            .width(320)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#CC000000')
      }

      // 暂停浮层
      if (this.displayState === GameState.PAUSED) {
        Column({ space: 16 }) {
          Text('已暂停').fontColor(Color.White).fontSize(22)
          Button($r('app.string.btn_resume')).width(160).onClick(() => this.onResume())
          Button($r('app.string.btn_quit')).width(160).onClick(() => this.onQuit())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#99000000')
      }

      // 结束页
      if (this.displayState === GameState.ENDED) {
        Column({ space: 16 }) {
          Text('游戏结束').fontColor(Color.White).fontSize(22)
          Button($r('app.string.btn_restart')).width(160).onClick(() => this.onRestart())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#CC000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}

/**
 * 虚拟摇杆组件（DES-003）：基于 onTouch 原始多指触摸事件，
 * 只捕获首个落在自身区域内的指针，其余指针（含区域外）一律忽略。
 */
@Component
struct JoystickControl {
  @Prop size: number = 140;
  @State knobX: number = 70;
  @State knobY: number = 70;
  private pointerId: number = -1;
  private centerX: number = 70;
  private centerY: number = 70;
  onAxis: (axis: number) => void = (_a: number) => {};

  private radius(): number {
    return this.size / 2;
  }

  build(): void {
    Stack() {
      Circle({ width: this.size, height: this.size })
        .fillColor('#33666666')
        .stroke('#88FFFFFF')
        .strokeWidth(1)
      Circle({ width: 56, height: 56 })
        .fillColor('#AAFFFFFF')
        .position({ x: this.knobX - 28, y: this.knobY - 28 })
    }
    .width(this.size)
    .height(this.size)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.pointerId === -1) {
          this.pointerId = event.touches[0].id;
          this.updateKnob(event.touches[0].x, event.touches[0].y);
        }
      } else if (event.type === TouchType.Move) {
        if (event.touches[0].id === this.pointerId) {
          this.updateKnob(event.touches[0].x, event.touches[0].y);
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (event.touches[0].id === this.pointerId) {
          this.pointerId = -1;
          this.knobX = this.centerX;
          this.knobY = this.centerY;
          this.onAxis(0);
        }
      }
    })
  }

  private updateKnob(x: number, y: number): void {
    const dx = x - this.centerX;
    const dy = y - this.centerY;
    const r = this.radius();
    const mag = Math.sqrt(dx * dx + dy * dy);
    const clampMag = Math.min(mag, r);
    const nx = mag > 0 ? (dx / mag) * clampMag : 0;
    const ny = mag > 0 ? (dy / mag) * clampMag : 0;
    this.knobX = this.centerX + nx;
    this.knobY = this.centerY + ny;
    // 杆量经死区映射后输出（REQ-003：死区内待机，P2-2 修复）
    this.onAxis(joystickToAxis(dx, dy));
  }
}

/**
 * 动作按键（跳跃）组件：右下角，独立跟踪落在自身边界内的指针。
 */
@Component
struct JumpButton {
  @State pressed: boolean = false;
  private pointerId: number = -1;
  onPressDown: () => void = () => {};
  onPressUp: () => void = () => {};

  build(): void {
    Text($r('app.string.btn_jump'))
      .fontSize(24)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width(110)
      .height(110)
      .borderRadius(55)
      .backgroundColor(this.pressed ? '#882E7D32' : '#552E7D32')
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down && this.pointerId === -1) {
          this.pointerId = event.touches[0].id;
          this.pressed = true;
          this.onPressDown();
        } else if ((event.type === TouchType.Up || event.type === TouchType.Cancel)
          && event.touches[0].id === this.pointerId) {
          this.pointerId = -1;
          this.pressed = false;
          this.onPressUp();
        }
      })
  }
}

/**
 * 游戏引擎核心（DES-002）：固定步长逻辑 + 可变步长渲染（accumulator 模式）。
 *
 * - 逻辑步固定 LOGIC_STEP = 1000/60 ms；单帧最多补 MAX_STEPS=3 个逻辑步，
 *   超出丢弃并清零 accumulator（防死亡螺旋）。
 * - 每个逻辑步严格按序：输入快照 -> 逻辑更新(移动/动画) -> 碰撞 -> 地图滚动。
 * - 渲染在每个 tick 末尾执行一次，按 accumulator/LOGIC_STEP 插值平滑。
 * - 降级策略：帧率下降补步耗尽时逻辑照常执行、渲染帧跳过——核心逻辑优先于渲染，
 *   循环不中断（REQ-002/008 异常边界）。
 */

import { InputSystem } from '../input/InputSystem';
import { Player } from '../player/Player';
import { PlayerSystem } from '../player/PlayerSystem';
import { CollisionSystem, aabbOf } from '../collision/CollisionSystem';
import { MapSystem } from '../map/MapSystem';
import { EventBus } from './EventBus';
import {
  RenderAdapter, RenderContext, DrawSpriteCmd, DrawTileCmd
} from '../render/RenderAdapter';

export const LOGIC_STEP = 1000 / 60;
export const MAX_STEPS = 3;

export interface EngineConfig {
  viewportW: number;
  viewportH: number;
}

/** 帧调度顺序探针（单元测试用：记录每个逻辑步各阶段调用顺序） */
export class LoopOrderProbe {
  calls: string[] = [];
  record(phase: string): void {
    this.calls.push(phase);
  }
}

export class GameEngine {
  readonly bus: EventBus = new EventBus();
  readonly input: InputSystem = new InputSystem();
  readonly player: Player;
  readonly playerSystem: PlayerSystem = new PlayerSystem();
  readonly collision: CollisionSystem;
  readonly map: MapSystem;

  private renderer: RenderAdapter | null = null;
  private accumulator: number = 0;
  private renderCalls: number = 0;
  private logicSteps: number = 0;
  private droppedTime: number = 0;
  private paused: boolean = false;
  private probe: LoopOrderProbe | null = null;
  private viewportW: number;
  private viewportH: number;

  constructor(map: MapSystem, player: Player, config: EngineConfig) {
    this.map = map;
    this.player = player;
    this.collision = new CollisionSystem(map);
    this.viewportW = config.viewportW;
    this.viewportH = config.viewportH;
  }

  setRenderer(renderer: RenderAdapter): void {
    this.renderer = renderer;
  }

  setProbe(probe: LoopOrderProbe | null): void {
    this.probe = probe;
  }

  setViewport(w: number, h: number): void {
    this.viewportW = w;
    this.viewportH = h;
    this.map.setViewport(w);
  }

  /** 暂停/恢复：不销毁引擎对象（DES-009）；恢复调用方应先调用 resumeAt 重置基准避免 dt 突刺 */
  pause(): void {
    this.paused = true;
  }

  resume(): void {
    this.paused = false;
  }

  isPaused(): boolean {
    return this.paused;
  }

  stats(): { logicSteps: number; renderCalls: number; droppedTime: number } {
    return { logicSteps: this.logicSteps, renderCalls: this.renderCalls, droppedTime: this.droppedTime };
  }

  /**
   * 单次 tick：dt 为距上次 tick 的真实毫秒（由外部 setInterval(16) 驱动并计算）。
   * 返回本 tick 执行的逻辑步数。
   */
  tick(dtMs: number): number {
    if (this.paused) {
      return 0;
    }
    // 异常保护：单帧 dt 超大（切后台回来）时截断，避免突刺
    const dt = Math.min(dtMs, 100);
    this.accumulator += dt;
    let steps = 0;
    while (this.accumulator >= LOGIC_STEP && steps < MAX_STEPS) {
      this.step(LOGIC_STEP);
      this.accumulator -= LOGIC_STEP;
      steps += 1;
    }
    if (this.accumulator >= LOGIC_STEP) {
      // 补步耗尽：丢弃超出时间，防死亡螺旋
      this.droppedTime += this.accumulator - LOGIC_STEP;
      this.accumulator = LOGIC_STEP;
    }
    this.render();
    return steps;
  }

  /** 单个固定步长逻辑步（顺序：输入 -> 逻辑 -> 碰撞 -> 地图） */
  step(dtMs: number): void {
    this.logicSteps += 1;
    this.record('input');
    const snap = this.input.snapshot();
    this.record('update');
    this.playerSystem.moveHorizontal(this.player, snap, this.map.mapWidthPx(), dtMs);
    let box = aabbOf(this.player.x, this.player.y, this.player.config.width, this.player.config.height);
    this.record('collision-x');
    const hRes = this.collision.resolveHorizontal(box, this.player.vx);
    if (hRes.blocked) {
      this.player.x = hRes.newX;
      this.player.vx = 0;
    }
    this.record('update-y');
    this.playerSystem.moveVertical(this.player, snap, dtMs);
    box = aabbOf(this.player.x, this.player.y, this.player.config.width, this.player.config.height);
    this.record('collision-y');
    const vRes = this.collision.resolveVertical(box, this.player.vy);
    if (vRes.landed) {
      this.player.y = vRes.newY;
      this.player.vy = 0;
      this.player.onGround = true;
    } else if (vRes.hitCeil) {
      this.player.y = vRes.newY;
      this.player.vy = 0;
    } else if (this.player.vy !== 0) {
      this.player.onGround = false;
    }
    this.record('state');
    this.playerSystem.updateState(this.player, snap);
    this.player.advanceAnim(dtMs);
    this.record('map');
    this.map.updateCamera(this.player.x + this.player.config.width / 2);
    // 触发器/敌人碰撞事件派发（不阻挡移动）
    const box2 = aabbOf(this.player.x, this.player.y, this.player.config.width, this.player.config.height);
    const overlaps = this.collision.scanOverlaps(box2);
    for (let i = 0; i + 1 < overlaps.triggers.length; i += 2) {
      this.bus.emit('trigger', { col: overlaps.triggers[i], row: overlaps.triggers[i + 1] });
    }
    for (let i = 0; i + 1 < overlaps.enemyHits.length; i += 2) {
      this.bus.emit('enemyHit', { col: overlaps.enemyHits[i], row: overlaps.enemyHits[i + 1] });
    }
  }

  private render(): void {
    if (this.renderer === null) {
      return;
    }
    this.renderCalls += 1;
    const ctx: RenderContext = {
      cameraX: this.map.getCameraX(),
      viewportW: this.viewportW,
      viewportH: this.viewportH,
      alpha: Math.max(0, Math.min(1, this.accumulator / LOGIC_STEP))
    };
    const tileCmds: DrawTileCmd[] = this.visibleTileCmds(ctx);
    const spriteCmds: DrawSpriteCmd[] = [{
      x: this.player.x, y: this.player.y,
      width: this.player.config.width, height: this.player.config.height,
      atlasIndex: this.player.currentAtlasFrame(),
      flip: this.player.facing < 0
    }];
    this.renderer.clear(ctx);
    this.renderer.drawTiles(tileCmds, ctx);
    this.renderer.drawSprites(spriteCmds, ctx);
    this.renderer.present(ctx);
  }

  /** 视口裁剪：只生成可见 tile 绘制命令（屏幕外零绘制成本，DES-008） */
  visibleTileCmds(ctx: RenderContext): DrawTileCmd[] {
    const data = this.map.data;
    const cmds: DrawTileCmd[] = [];
    const col0 = Math.max(0, Math.floor(ctx.cameraX / data.tileW));
    const col1 = Math.min(data.cols - 1, Math.floor((ctx.cameraX + ctx.viewportW) / data.tileW));
    for (let col = col0; col <= col1; col++) {
      for (let row = 0; row < data.rows; row++) {
        const t = this.map.getTile(col, row);
        if (t !== 0) { // 非 EMPTY 才绘制
          cmds.push({ col: col, row: row, tileW: data.tileW, tileH: data.tileH, atlasIndex: t });
        }
      }
    }
    return cmds;
  }

  private record(phase: string): void {
    if (this.probe !== null) {
      this.probe.record(phase);
    }
  }
}

/**
 * 游戏状态机（DES-009）：五状态显式枚举 + 迁移表。
 * 纯 ArkTS 逻辑，不依赖任何 ArkUI 渲染 API。
 */

export enum GameState {
  BOOTING = 'BOOTING',       // 启动中
  LOADING = 'LOADING',       // 资源加载中
  RUNNING = 'RUNNING',       // 运行中
  PAUSED = 'PAUSED',         // 暂停
  ENDED = 'ENDED'            // 结束
}

/** 状态迁移触发事件 */
export enum GameEvent {
  WINDOW_STAGE_READY = 'WINDOW_STAGE_READY',   // 启动页就绪（onWindowStageCreate 完成）
  CORE_RESOURCE_READY = 'CORE_RESOURCE_READY', // P0 核心资源加载完成
  PAUSE = 'PAUSE',                             // HUD 暂停按钮
  RESUME = 'RESUME',                           // 暂停浮层"继续"
  QUIT = 'QUIT',                               // 暂停浮层"退出"/系统返回确认
  RESTART = 'RESTART'                          // 结束页"再来一局"
}

/** 迁移表：[当前状态][事件] -> 目标状态 */
export const TRANSITION_TABLE: Map<GameState, Map<GameEvent, GameState>> = new Map([
  [GameState.BOOTING, new Map<GameEvent, GameState>([
    [GameEvent.WINDOW_STAGE_READY, GameState.LOADING]
  ])],
  [GameState.LOADING, new Map<GameEvent, GameState>([
    [GameEvent.CORE_RESOURCE_READY, GameState.RUNNING]
  ])],
  [GameState.RUNNING, new Map<GameEvent, GameState>([
    [GameEvent.PAUSE, GameState.PAUSED],
    [GameEvent.QUIT, GameState.ENDED]
  ])],
  [GameState.PAUSED, new Map<GameEvent, GameState>([
    [GameEvent.RESUME, GameState.RUNNING],
    [GameEvent.QUIT, GameState.ENDED]
  ])],
  [GameState.ENDED, new Map<GameEvent, GameState>([
    [GameEvent.RESTART, GameState.LOADING]
  ])]
]);

export interface TransitionLogEntry {
  from: GameState;
  event: GameEvent;
  to: GameState;
  ok: boolean;
  reason?: string;
}

/**
 * 状态机：非法迁移直接拒绝并记日志，不抛异常、不崩溃（DES-009 异常边界）。
 */
export class GameStateMachine {
  private state: GameState = GameState.BOOTING;
  private logs: TransitionLogEntry[] = [];
  private onStateChangeHandler: ((from: GameState, to: GameState) => void) | null = null;

  current(): GameState {
    return this.state;
  }

  onStateChange(handler: (from: GameState, to: GameState) => void): void {
    this.onStateChangeHandler = handler;
  }

  /**
   * 尝试按事件迁移。合法则迁移并返回 true；非法则拒绝、记日志并返回 false。
   */
  fire(event: GameEvent): boolean {
    const row = TRANSITION_TABLE.get(this.state);
    const target = row !== undefined ? row.get(event) : undefined;
    if (target === undefined) {
      this.logs.push({
        from: this.state, event: event, to: this.state, ok: false,
        reason: `illegal transition: ${this.state} + ${event}`
      });
      return false;
    }
    const from = this.state;
    this.state = target;
    this.logs.push({ from: from, event: event, to: target, ok: true });
    if (this.onStateChangeHandler !== null) {
      this.onStateChangeHandler(from, target);
    }
    return true;
  }

  /** 强制重置（仅用于重新初始化场景，如"再来一局"重置） */
  reset(): void {
    this.state = GameState.BOOTING;
    this.logs = [];
  }

  recentLogs(count: number): TransitionLogEntry[] {
    return this.logs.slice(Math.max(0, this.logs.length - count));
  }
}

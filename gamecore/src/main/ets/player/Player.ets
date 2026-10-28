/**
 * 角色实体与动画（DES-004）：数据实体与需求 8.1 对齐——
 * 位置、方向、状态、动画帧索引。
 */

export enum PlayerAnimState {
  IDLE = 'idle',
  WALK = 'walk',
  JUMP = 'jump'
}

export enum Facing {
  LEFT = -1,
  RIGHT = 1
}

export interface PlayerConfig {
  width: number;
  height: number;
  maxSpeed: number;      // px/s，水平最大速度
  gravity: number;       // px/s^2
  jumpVelocity: number;  // px/s，跳跃初速（向上为负）
}

export const DEFAULT_PLAYER_CONFIG: PlayerConfig = {
  width: 32,
  height: 48,
  maxSpeed: 220,
  gravity: 1500,
  jumpVelocity: 520
};

/** 各状态的精灵图集帧序列与每帧时长（ms），正式资源到位后从 JSON 加载替换 */
export interface AnimClip {
  frames: number[];   // 图集子矩形索引序列
  frameDuration: number;
}

export const DEFAULT_ANIM_CLIPS: Map<PlayerAnimState, AnimClip> = new Map([
  [PlayerAnimState.IDLE, { frames: [0, 1, 2, 3], frameDuration: 180 }],
  [PlayerAnimState.WALK, { frames: [4, 5, 6, 7, 8, 9], frameDuration: 100 }],
  [PlayerAnimState.JUMP, { frames: [10, 11], frameDuration: 140 }]
]);

export class Player {
  // 世界坐标（左上角）
  x: number = 0;
  y: number = 0;
  vx: number = 0;
  vy: number = 0;
  facing: Facing = Facing.RIGHT;
  state: PlayerAnimState = PlayerAnimState.IDLE;
  animFrameIndex: number = 0;  // 当前动画帧（图集子矩形索引）
  animTime: number = 0;        // 当前帧已播放时长 ms
  onGround: boolean = false;
  readonly config: PlayerConfig;

  constructor(config: PlayerConfig = DEFAULT_PLAYER_CONFIG) {
    this.config = config;
  }

  left(): number { return this.x; }
  top(): number { return this.y; }
  right(): number { return this.x + this.config.width; }
  bottom(): number { return this.y + this.config.height; }

  setState(newState: PlayerAnimState): void {
    if (this.state !== newState) {
      this.state = newState;
      this.animFrameIndex = 0;
      this.animTime = 0;
    }
  }

  /** 逻辑步推进动画帧计时并切换帧索引 */
  advanceAnim(dtMs: number, clips: Map<PlayerAnimState, AnimClip> = DEFAULT_ANIM_CLIPS): void {
    const clip = clips.get(this.state);
    if (clip === undefined || clip.frames.length === 0) {
      return;
    }
    this.animTime += dtMs;
    while (this.animTime >= clip.frameDuration) {
      this.animTime -= clip.frameDuration;
      this.animFrameIndex = (this.animFrameIndex + 1) % clip.frames.length;
    }
  }

  /** 当前帧对应的图集子矩形索引 */
  currentAtlasFrame(clips: Map<PlayerAnimState, AnimClip> = DEFAULT_ANIM_CLIPS): number {
    const clip = clips.get(this.state);
    if (clip === undefined || clip.frames.length === 0) {
      return 0;
    }
    return clip.frames[Math.min(this.animFrameIndex, clip.frames.length - 1)];
  }
}

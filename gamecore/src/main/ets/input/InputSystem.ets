/**
 * 触控交互输入汇聚（DES-003）。
 * ArkUI 摇杆/按键组件把原始触摸映射结果写入本单例快照；
 * 逻辑步开始时一次性读取快照，避免逻辑步中途输入变化。
 */

export const JOYSTICK_DEAD_ZONE = 0.1;

export interface InputSnapshot {
  /** 摇杆水平杆量，[-1, 1]，死区内为 0 */
  moveAxis: number;
  /** 跳跃按键本逻辑步是否为"刚按下"（边沿） */
  jumpJustPressed: boolean;
  /** 跳跃按键当前是否持续按住 */
  jumpHeld: boolean;
}

/**
 * 纯函数：摇杆向量 -> 水平杆量。
 * 幅度 < 死区(10%) -> 0（角色待机）；死区外水平分量线性映射移动速度。
 */
export function joystickToAxis(dx: number, dy: number, deadZone: number = JOYSTICK_DEAD_ZONE): number {
  const magnitude = Math.sqrt(dx * dx + dy * dy);
  if (magnitude < deadZone) {
    return 0;
  }
  // 死区外幅度按 [deadZone, 1] 线性归一到 [0, 1]
  const normalized = Math.min(1, (magnitude - deadZone) / (1 - deadZone));
  const horizontalRatio = dx / magnitude;
  return Math.sign(horizontalRatio) * normalized * Math.min(1, Math.abs(horizontalRatio) * 1.0);
}

export class InputSystem {
  private currentAxis: number = 0;
  private jumpHeld: boolean = false;
  private jumpEdgePending: boolean = false;
  private lastSnapshot: InputSnapshot = { moveAxis: 0, jumpJustPressed: false, jumpHeld: false };

  /** 摇杆组件写入杆量（已过死区映射） */
  setMoveAxis(axis: number): void {
    this.currentAxis = Math.max(-1, Math.min(1, axis));
  }

  /** 动作按键写入（true=按下，false=抬起） */
  setJump(down: boolean): void {
    if (down && !this.jumpHeld) {
      this.jumpEdgePending = true;
    }
    this.jumpHeld = down;
  }

  /** 逻辑步开始时读取本步输入快照（边沿消耗型） */
  snapshot(): InputSnapshot {
    const just = this.jumpEdgePending;
    this.jumpEdgePending = false;
    this.lastSnapshot = { moveAxis: this.currentAxis, jumpJustPressed: just, jumpHeld: this.jumpHeld };
    return this.lastSnapshot;
  }

  /** 当前快照（不消耗边沿，供渲染层展示） */
  peek(): InputSnapshot {
    return this.lastSnapshot;
  }

  clear(): void {
    this.currentAxis = 0;
    this.jumpHeld = false;
    this.jumpEdgePending = false;
    this.lastSnapshot = { moveAxis: 0, jumpJustPressed: false, jumpHeld: false };
  }
}

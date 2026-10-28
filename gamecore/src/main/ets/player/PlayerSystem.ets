/**
 * 角色移动系统（DES-004）。
 * 每个逻辑步：vx = 输入方向 × 映射速度；重力；位置积分（先水平后垂直，
 * 垂直/水平的位置修正由 CollisionSystem 完成）。
 * 地图两端边界 clamp 兜底（REQ-003 异常边界）。
 */

import { InputSnapshot } from '../input/InputSystem';
import { Player, PlayerAnimState } from './Player';

export class PlayerSystem {
  /** 水平积分 + 边界 clamp（碰撞修正由 CollisionSystem 在其后调用） */
  moveHorizontal(player: Player, input: InputSnapshot, mapWidth: number, dtMs: number): void {
    const dt = dtMs / 1000;
    player.vx = input.moveAxis * player.config.maxSpeed;
    player.x += player.vx * dt;
    if (input.moveAxis !== 0) {
      player.facing = input.moveAxis > 0 ? 1 : -1; // Facing.RIGHT / LEFT
    }
    // 地图边界 clamp：到达边界即停止（越界侧速度清零）
    if (player.x < 0) {
      player.x = 0;
      player.vx = 0;
    }
    const maxX = mapWidth - player.config.width;
    if (maxX >= 0 && player.x > maxX) {
      player.x = maxX;
      player.vx = 0;
    }
  }

  /** 垂直积分：重力 + 跳跃初速（起跳条件：在地面且本步"刚按下"跳跃；重力先于起跳覆盖，保证初速精确为 -jumpVelocity） */
  moveVertical(player: Player, input: InputSnapshot, dtMs: number): void {
    const dt = dtMs / 1000;
    player.vy += player.config.gravity * dt;
    if (input.jumpJustPressed && player.onGround) {
      player.vy = -player.config.jumpVelocity;
      player.onGround = false;
    }
    // 上升速度上限保护，防极端 dt 穿透
    if (player.vy > 2000) {
      player.vy = 2000;
    }
    player.y += player.vy * dt;
  }

  /** 状态与动画切换（REQ-003）：跳跃优先，其次水平移动，无输入且在地面为待机 */
  updateState(player: Player, input: InputSnapshot): void {
    if (!player.onGround) {
      player.setState(PlayerAnimState.JUMP);
    } else if (input.moveAxis !== 0) {
      player.setState(PlayerAnimState.WALK);
    } else {
      player.setState(PlayerAnimState.IDLE);
    }
  }
}

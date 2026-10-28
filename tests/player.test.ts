/**
 * DES-004 角色/移动/动画：边界 clamp、状态切换、动画帧推进。
 */

import { test, assertEq } from './harness';
import { Player, PlayerAnimState, Facing } from '../src/player/Player';
import { PlayerSystem } from '../src/player/PlayerSystem';
import { InputSnapshot } from '../src/input/InputSystem';

function snap(axis: number, jump = false): InputSnapshot {
  return { moveAxis: axis, jumpJustPressed: jump, jumpHeld: jump };
}

test('水平移动：vx = 输入方向 x 最大速度，并更新朝向', () => {
  const p = new Player();
  const ps = new PlayerSystem();
  ps.moveHorizontal(p, snap(1), 10000, 1000);
  assertEq(p.vx, p.config.maxSpeed, 'speed');
  assertEq(p.facing, Facing.RIGHT, 'facing right');
  assertEq(p.x > 0, true, 'moved');
});

test('地图边界 clamp：左边界 0、右边界 mapW-角色宽，越界侧 vx=0', () => {
  const p = new Player();
  const ps = new PlayerSystem();
  // 左边界
  ps.moveHorizontal(p, snap(-1), 1000, 10000);
  assertEq(p.x, 0, 'clamped at left');
  assertEq(p.vx, 0, 'vx zero at boundary');
  // 右边界（地图宽 200，角色宽 32）
  p.x = 190;
  ps.moveHorizontal(p, snap(1), 200, 10000);
  assertEq(p.x, 200 - 32, 'clamped at right');
  assertEq(p.vx, 0, 'vx zero at right boundary');
});

test('状态切换：无输入+在地面=IDLE，有输入=WALK，空中=JUMP', () => {
  const p = new Player();
  const ps = new PlayerSystem();
  p.onGround = true;
  ps.updateState(p, snap(0));
  assertEq(p.state, PlayerAnimState.IDLE, 'idle');
  ps.updateState(p, snap(-0.5));
  assertEq(p.state, PlayerAnimState.WALK, 'walk');
  p.onGround = false;
  ps.updateState(p, snap(-0.5));
  assertEq(p.state, PlayerAnimState.JUMP, 'jump overrides walk');
});

test('动画帧推进：超过 frameDuration 切换帧并循环', () => {
  const p = new Player();
  p.setState(PlayerAnimState.IDLE);
  p.advanceAnim(180);
  assertEq(p.animFrameIndex, 1, 'next frame');
  p.advanceAnim(180 * 3);
  assertEq(p.animFrameIndex, 0, 'wrapped to first frame');
});

test('跳跃：地面起跳获得向上初速，重力使其回落', () => {
  const p = new Player();
  const ps = new PlayerSystem();
  p.onGround = true;
  ps.moveVertical(p, snap(0, true), 16);
  assertEq(p.vy, -p.config.jumpVelocity, 'jump initial velocity');
  const yTop = p.y;
  ps.moveVertical(p, snap(0, false), 16);
  assertEq(p.y < yTop, true, 'still rising next step');
  for (let i = 0; i < 120; i++) {
    ps.moveVertical(p, snap(0, false), 16);
  }
  assertEq(p.vy > 0, true, 'falling after apex');
});

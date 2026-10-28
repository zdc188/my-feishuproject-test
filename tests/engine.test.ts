/**
 * DES-002 帧调度：顺序、固定步长、补步上限、防死亡螺旋、暂停不执行。
 */

import { test, assertEq } from './harness';
import {
  GameEngine, LoopOrderProbe, LOGIC_STEP, MAX_STEPS
} from '../src/core/GameEngine';
import { buildMapData } from '../src/map/MapData';
import { MapSystem } from '../src/map/MapSystem';
import { Player } from '../src/player/Player';
import { PlayerAnimState } from '../src/player/Player';
import { InputSystem } from '../src/input/InputSystem';

function makeEngine(): { engine: GameEngine; probe: LoopOrderProbe; input: InputSystem } {
  const data = buildMapData(32, 8, (() => {
    const rows: string[] = [];
    for (let r = 0; r < 8; r++) {
      rows.push(r === 7 ? '#'.repeat(32) : '.'.repeat(32));
    }
    return rows;
  })());
  const map = new MapSystem(data, {
    loadChunk: () => Promise.resolve(),
    releaseChunk: () => undefined
  });
  const player = new Player();
  player.x = 0;
  player.y = 96;
  const engine = new GameEngine(map, player, { viewportW: 640, viewportH: 256 });
  const probe = new LoopOrderProbe();
  engine.setProbe(probe);
  return { engine: engine, probe: probe, input: engine.input };
}

test('单个逻辑步内调度顺序为 输入->更新->碰撞X->更新Y->碰撞Y->状态->地图', () => {
  const { engine, probe } = makeEngine();
  engine.tick(LOGIC_STEP);
  const order = probe.calls.slice(0, 7);
  assertEq(order, ['input', 'update', 'collision-x', 'update-y', 'collision-y', 'state', 'map'], 'step order');
});

test('固定步长：不足一个步长不执行逻辑步，累积后执行', () => {
  const { engine } = makeEngine();
  const steps1 = engine.tick(LOGIC_STEP / 2);
  assertEq(steps1, 0, 'half dt no step');
  const steps2 = engine.tick(LOGIC_STEP / 2);
  assertEq(steps2, 1, 'accumulated one step');
});

test('补步上限 MAX_STEPS=3：大 dt 只补 3 步并丢弃超出时间', () => {
  const { engine } = makeEngine();
  const steps = engine.tick(LOGIC_STEP * 10);
  assertEq(steps, MAX_STEPS, 'capped at 3');
  assertEq(engine.stats().droppedTime > 0, true, 'dropped time recorded');
});

test('普通 dt 每帧至多 1 步且循环不中断', () => {
  const { engine } = makeEngine();
  for (let i = 0; i < 120; i++) {
    engine.tick(16);
  }
  assertEq(engine.stats().logicSteps > 100, true, 'loop keeps running');
});

test('暂停后 tick 不执行逻辑步，恢复后继续', () => {
  const { engine } = makeEngine();
  engine.pause();
  assertEq(engine.tick(100), 0, 'paused no steps');
  engine.resume();
  assertEq(engine.tick(LOGIC_STEP), 1, 'resumed');
});

test('跳跃起跳后进入 JUMP 动画，落地回到 IDLE', () => {
  const { engine } = makeEngine();
  // 落到地面
  for (let i = 0; i < 30; i++) {
    engine.tick(LOGIC_STEP);
  }
  assertEq(engine.player.onGround, true, 'landed');
  engine.input.setJump(true);
  engine.tick(LOGIC_STEP);
  assertEq(engine.player.state, PlayerAnimState.JUMP, 'jump state');
  engine.input.setJump(false);
  for (let i = 0; i < 60; i++) {
    engine.tick(LOGIC_STEP);
  }
  assertEq(engine.player.onGround, true, 'landed again');
  assertEq(engine.player.state, PlayerAnimState.IDLE, 'back to idle');
});

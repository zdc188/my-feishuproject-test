/**
 * DES-007 资源管理：LRU 淘汰、优先级卸载、失败兜底、引用计数保护。
 * DES-009 状态机：迁移表合法/非法迁移。
 */

import { test, assertEq } from './harness';
import {
  ResourceSystem, ResourceLoader, ResourcePriority
} from '../src/resource/ResourceSystem';
import {
  GameStateMachine, GameState, GameEvent
} from '../src/core/GameStateMachine';
import { EventBus } from '../src/core/EventBus';

function okLoader(): ResourceLoader {
  return { load: (_k: string) => Promise.resolve({ data: 1 }) };
}

test('LRU 淘汰：超容量逐出最久未使用且无引用的资源', async () => {
  const rs = new ResourceSystem(okLoader(), 3);
  await rs.load('a', ResourcePriority.ATLAS);
  await rs.load('b', ResourcePriority.ATLAS);
  await rs.load('c', ResourcePriority.ATLAS);
  rs.peek('a'); // 刷新 a 的 LRU 时间
  await rs.load('d', ResourcePriority.ATLAS);
  assertEq(rs.has('b'), false, 'oldest unused evicted');
  assertEq(rs.has('a'), true, 'recently used kept');
});

test('引用计数：被持有的资源不被 LRU 逐出', async () => {
  const rs = new ResourceSystem(okLoader(), 2);
  await rs.load('a', ResourcePriority.ATLAS);
  rs.acquire('a');
  await rs.load('b', ResourcePriority.ATLAS);
  await rs.load('c', ResourcePriority.ATLAS);
  assertEq(rs.has('a'), true, 'referenced resource kept');
  assertEq(rs.release('a'), true, 'released after refcount drops');
  assertEq(rs.has('a'), false, 'removed after release');
});

test('加载失败兜底：占位资源 + 错误日志，不崩溃', async () => {
  const rs = new ResourceSystem({
    load: (k: string) => k === 'bad' ? Promise.reject(new Error('404')) : Promise.resolve({ data: 1 })
  });
  const entry = await rs.load('bad', ResourcePriority.AUDIO);
  assertEq(entry.isPlaceholder, true, 'placeholder used');
  assertEq(rs.errors().length, 1, 'error logged');
  const good = await rs.load('good', ResourcePriority.CORE);
  assertEq(good.isPlaceholder, false, 'other resources unaffected');
});

test('内存压力：按优先级从低到高卸载非关键资源，核心与引用资源保留', async () => {
  const rs = new ResourceSystem(okLoader());
  await rs.load('sfx', ResourcePriority.AUDIO);
  await rs.load('atlas', ResourcePriority.ATLAS);
  await rs.load('chunk', ResourcePriority.MAP_CHUNK);
  await rs.load('core', ResourcePriority.CORE);
  await rs.load('held', ResourcePriority.AUDIO);
  rs.acquire('held');
  const evicted = rs.onMemoryPressure(['chunk']); // 当前窗口 chunk pin
  assertEq(evicted.includes('sfx'), true, 'audio evicted first');
  assertEq(evicted.includes('atlas'), true, 'atlas evicted');
  assertEq(evicted.includes('chunk'), false, 'pinned chunk kept');
  assertEq(evicted.includes('core'), false, 'core kept');
  assertEq(evicted.includes('held'), false, 'referenced kept');
});

test('状态机主链路：启动->加载->运行->暂停->继续->退出', () => {
  const sm = new GameStateMachine();
  assertEq(sm.current(), GameState.BOOTING, 'initial');
  assertEq(sm.fire(GameEvent.WINDOW_STAGE_READY), true, 'boot->loading');
  assertEq(sm.fire(GameEvent.CORE_RESOURCE_READY), true, 'loading->running');
  assertEq(sm.fire(GameEvent.PAUSE), true, 'running->paused');
  assertEq(sm.fire(GameEvent.RESUME), true, 'paused->running');
  assertEq(sm.fire(GameEvent.QUIT), true, 'running->ended');
});

test('非法迁移被拒绝并记日志，不崩溃', () => {
  const sm = new GameStateMachine();
  assertEq(sm.fire(GameEvent.PAUSE), false, 'booting->paused rejected');
  assertEq(sm.fire(GameEvent.RESUME), false, 'resume without pause rejected');
  assertEq(sm.current(), GameState.BOOTING, 'state unchanged');
  assertEq(sm.recentLogs(2).every((l) => !l.ok), true, 'rejections logged');
  assertEq(sm.fire(GameEvent.WINDOW_STAGE_READY), true, 'still operational');
});

test('结束后"再来一局"重置到加载链路', () => {
  const sm = new GameStateMachine();
  sm.fire(GameEvent.WINDOW_STAGE_READY);
  sm.fire(GameEvent.CORE_RESOURCE_READY);
  sm.fire(GameEvent.PAUSE);
  sm.fire(GameEvent.QUIT);
  assertEq(sm.fire(GameEvent.RESTART), true, 'ended->loading');
  assertEq(sm.current(), GameState.LOADING, 'back to loading');
  assertEq(sm.fire(GameEvent.CORE_RESOURCE_READY), true, 'can run again');
});

test('EventBus：订阅/派发/注销，回调异常不中断其它订阅者', () => {
  const bus = new EventBus();
  const got: string[] = [];
  const bad = (_p: object) => { throw new Error('boom'); };
  bus.on('evt', bad);
  bus.on('evt', (p: object) => { got.push(`a:${(p as Record<string, string>)['v']}`); });
  bus.emit('evt', { v: '1' });
  assertEq(got, ['a:1'], 'healthy handler still called');
  bus.off('evt', bad);
  bus.emit('evt', { v: '2' });
  assertEq(got, ['a:1', 'a:2'], 'second emit');
  assertEq(bus.listenerCount('evt'), 1, 'bad handler removed');
});

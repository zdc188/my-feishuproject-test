/**
 * DES-005 碰撞：逐轴 AABB、阻挡贴齐、落地/撞顶、触发器与敌人事件通道。
 */

import { test, assertEq } from './harness';
import { CollisionSystem, aabbOf, aabbOverlap } from '../src/collision/CollisionSystem';
import { MapSystem } from '../src/map/MapSystem';
import { buildMapData } from '../src/map/MapData';
import { TileKind } from '../src/map/MapData';

function makeMap(rows: string[], cols: number): MapSystem {
  const data = buildMapData(cols, rows.length, rows);
  return new MapSystem(data, { loadChunk: () => Promise.resolve(), releaseChunk: () => undefined });
}

test('AABB 重叠判定基本性质', () => {
  assertEq(aabbOverlap(aabbOf(0, 0, 10, 10), aabbOf(5, 5, 10, 10)), true, 'overlap');
  assertEq(aabbOverlap(aabbOf(0, 0, 10, 10), aabbOf(20, 20, 10, 10)), false, 'no overlap');
});

test('水平阻挡：向右撞 solid tile 贴齐左边缘', () => {
  // 第 4 列是一堵墙（row 0-7 全 solid 的窄墙）
  const rows = [
    '...#....',
    '...#....',
    '........',
    '........'
  ];
  const map = makeMap(rows, 8);
  const cs = new CollisionSystem(map);
  // 角色向右移动，右缘已伸入第 4 列 tile（x: 96~128）
  const box = aabbOf(96, 32, 32, 32); // right=128 已进入 wall col3(96..128)? wall at col3: 96..128
  const res = cs.resolveHorizontal(box, 100);
  assertEq(res.blocked, true, 'blocked');
  assertEq(res.newX, 96 - 32, 'snapped to wall left edge minus width');
});

test('水平阻挡：向左撞墙贴齐右边缘', () => {
  const rows = ['...#....', '...#....'];
  const map = makeMap(rows, 8);
  const cs = new CollisionSystem(map);
  const box = aabbOf(96, 0, 32, 32); // 左缘 96 与 col3(96..128) 重叠
  const res = cs.resolveHorizontal(box, -100);
  assertEq(res.blocked, true, 'blocked leftward');
  assertEq(res.newX, 128, 'snapped to wall right edge');
});

test('垂直落地：下落命中地面 tile 贴齐顶面', () => {
  const rows = [
    '........',
    '........',
    '########'
  ];
  const map = makeMap(rows, 8);
  const cs = new CollisionSystem(map);
  const box = aabbOf(32, 33, 32, 32); // bottom=65 已伸入地面 row2 顶面 y=64
  const res = cs.resolveVertical(box, 200);
  assertEq(res.landed, true, 'landed');
  assertEq(res.newY, 64 - 32, 'snapped on top of ground');
});

test('撞顶：上升命中 solid 贴齐底面', () => {
  const rows = ['####', '....', '....'];
  const map = makeMap(rows, 4);
  const cs = new CollisionSystem(map);
  const box = aabbOf(0, 31, 32, 32); // top=31 已伸入 row0 底面 y=32
  const res = cs.resolveVertical(box, -200);
  assertEq(res.hitCeil, true, 'hit ceiling');
  assertEq(res.newY, 32, 'snapped below ceiling');
});

test('触发器：重叠即报 trigger，不阻挡', () => {
  const rows = ['..T.....', '........'];
  const map = makeMap(rows, 8);
  const cs = new CollisionSystem(map);
  const box = aabbOf(64, 0, 32, 32); // 覆盖 col2 = trigger
  const res = cs.resolveHorizontal(box, 100);
  assertEq(res.blocked, false, 'trigger does not block');
  const over = cs.scanOverlaps(box);
  assertEq(over.triggers, [2, 0], 'trigger tile reported');
});

test('敌人碰撞体：重叠报 enemyHit', () => {
  const rows = ['..E.....', '........'];
  const map = makeMap(rows, 8);
  const cs = new CollisionSystem(map);
  const over = cs.scanOverlaps(aabbOf(64, 0, 32, 32));
  assertEq(over.enemyHits, [2, 0], 'enemy tile reported');
});

test('兜底空 chunk：加载失败的 chunk 底部两行视为 solid，防坠落穿模', async () => {
  const rows = [
    '........',
    '........',
    '........',
    '........'
  ];
  const data = buildMapData(16, 4, rows, 32, 32, 16);
  const fails = new Set<number>([0]);
  const map = new MapSystem(data, {
    loadChunk: (i: number) => fails.has(i) ? Promise.reject(new Error('io')) : Promise.resolve(),
    releaseChunk: () => undefined
  }, 128);
  map.updateCamera(0);
  await map.updateChunks(); // 重试 1 次仍失败 -> fallback
  assertEq(map.isFallbackChunk(0), true, 'chunk 0 fallback');
  assertEq(map.isEffectivelySolid(0, 2), true, 'bottom rows solid in fallback chunk');
  assertEq(map.isEffectivelySolid(0, 1), false, 'upper rows pass-through');
  assertEq(map.getTile(0, 0), TileKind.EMPTY, 'tile data itself untouched');
});

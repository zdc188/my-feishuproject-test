/**
 * DES-006 地图：相机跟随 clamp、chunk 窗口计算、加载/卸载、失败兜底重试。
 */

import { test, assertEq } from './harness';
import { MapSystem } from '../src/map/MapSystem';
import { buildMapData } from '../src/map/MapData';

function bigMap(): MapSystem {
  const cols = 96;
  const rows: string[] = [];
  for (let r = 0; r < 14; r++) {
    rows.push(r === 13 ? '#'.repeat(cols) : '.'.repeat(cols));
  }
  const data = buildMapData(cols, 14, rows, 32, 32, 16);
  return new MapSystem(data, { loadChunk: () => Promise.resolve(), releaseChunk: () => undefined }, 640);
}

test('相机跟随：角色保持视口 40% 位置', () => {
  const map = bigMap();
  const cam = map.updateCamera(320); // 角色中心 320
  assertEq(cam, 320 - 640 * 0.4, 'camera = player - 40% viewport');
});

test('相机 clamp：两端边界 [0, mapW-viewportW]', () => {
  const map = bigMap(); // mapW = 96*32 = 3072, maxCam = 3072-640 = 2432
  assertEq(map.updateCamera(0), 0, 'left boundary');
  assertEq(map.updateCamera(99999), 2432, 'right boundary');
});

test('窗口计算：视口 ± 1 chunk 预加载窗口', () => {
  const map = bigMap(); // chunk 宽 512px
  map.updateCamera(0);
  let w = map.windowRange();
  assertEq(w.first, 0, 'first clamped at 0');
  // camera=0 -> firstVisible=0, visibleCount=ceil(640/512)=2 -> last=min(5, 0+2+1)=3
  assertEq(w.last, 3, 'window extends 1 chunk beyond viewport');
  map.updateCamera(2000);
  w = map.windowRange();
  assertEq(w.first, Math.floor(2000 / 512) - 1, 'first = visible-1');
});

test('chunk 动态加载/卸载：滚动后旧 chunk 释放', async () => {
  const loaded: number[] = [];
  const released: number[] = [];
  const map = bigMap();
  const data = map.data;
  const map2 = new MapSystem(data, {
    loadChunk: (i: number) => { loaded.push(i); return Promise.resolve(); },
    releaseChunk: (i: number) => { released.push(i); }
  }, 640);
  map2.updateCamera(0);
  await map2.updateChunks();
  assertEq(loaded, [0, 1, 2, 3], 'initial window loaded');
  // 滚动到地图中段
  map2.updateCamera(1500);
  await map2.updateChunks();
  assertEq(released.length > 0, true, 'out-of-window chunks released');
  assertEq(loaded.includes(4), true, 'new chunks prefetched');
});

test('切片加载失败：重试 1 次仍失败用空 chunk 兜底，不抛异常', async () => {
  const cols = 48;
  const rows: string[] = [];
  for (let r = 0; r < 8; r++) {
    rows.push(r === 7 ? '#'.repeat(cols) : '.'.repeat(cols));
  }
  const data = buildMapData(cols, 8, rows);
  const attempts: number[] = [];
  const map = new MapSystem(data, {
    loadChunk: (i: number) => { attempts.push(i); return Promise.reject(new Error(`io-${i}`)); },
    releaseChunk: () => undefined
  }, 320);
  map.updateCamera(0);
  const results = await map.updateChunks();
  const failedChunk = results.find((r) => r.index === 0);
  assertEq(failedChunk !== undefined && failedChunk.fallback, true, 'fallback used');
  assertEq(attempts.filter((i) => i === 0).length, 2, 'retried exactly once');
});

test('重试成功后不使用兜底', async () => {
  const cols = 16;
  const rows = ['.'.repeat(cols), '#'.repeat(cols)];
  const data = buildMapData(cols, 2, rows);
  let fail = true;
  const map = new MapSystem(data, {
    loadChunk: (_i: number) => fail ? Promise.reject(new Error('io')) : Promise.resolve(),
    releaseChunk: () => undefined
  }, 320);
  map.updateCamera(0);
  const p = map.updateChunks();
  fail = false; // 重试时恢复
  await p;
  assertEq(map.isFallbackChunk(0), false, 'retry succeeded, no fallback');
  assertEq(map.isChunkLoaded(0), true, 'chunk loaded');
});

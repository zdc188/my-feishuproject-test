/**
 * 地图 JSON 数据校验：entry rawfile 中的正式地图可被解析且结构合法。
 * fixture 由 tools/check/prepare.sh 从 entry/src/main/resources/rawfile/map_level1.json 复制。
 */

import { test, assertEq } from './harness';
import { readFileSync } from 'fs';
import { join } from 'path';
import { parseMapData } from '../src/map/MapData';

test('rawfile 地图 JSON 可解析且满足头字段约束', () => {
  const text = readFileSync(join(__dirname, '..', '..', 'work', 'fixtures', 'map_level1.json'), 'utf-8');
  const data = parseMapData(JSON.parse(text));
  assertEq(data.cols, 96, 'cols');
  assertEq(data.rows, 14, 'rows');
  assertEq(data.chunkSize, 16, 'chunkSize');
  assertEq(data.tileW, 32, 'tileW');
  assertEq(data.playerSpawn.x, 64, 'spawn x');
  assertEq(data.tiles.length, 96 * 14, 'tile count');
  assertEq(data.tiles[13 * 96], 1, 'bottom row solid');
});

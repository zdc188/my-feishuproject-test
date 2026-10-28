/**
 * 地图数据（DES-006）：tile 网格 + 碰撞层 + 触发层 + chunk 索引。
 * 地图为应用内打包的本地 JSON；本文件提供解析与查询。
 */

export enum TileKind {
  EMPTY = 0,
  SOLID = 1,    // 阻挡
  TRIGGER = 2,  // 触发器（不阻挡，重叠派发事件）
  ENEMY = 3     // 敌人碰撞体（本次无 AI 与战斗规则，仅事件源）
}

/** 字符 -> tile 类型（地图 JSON 碰撞层字符表） */
export const TILE_CHARS: Map<string, TileKind> = new Map([
  ['.', TileKind.EMPTY],
  ['#', TileKind.SOLID],
  ['T', TileKind.TRIGGER],
  ['E', TileKind.ENEMY]
]);

export interface MapData {
  tileW: number;
  tileH: number;
  cols: number;
  rows: number;
  chunkSize: number;               // 建议 16 tile
  tiles: TileKind[];               // rows * cols，行优先
  playerSpawn: { x: number; y: number };
}

export function parseMapData(json: object): MapData {
  const obj = json as Record<string, Object>;
  const tileW = Number(obj['tileW']);
  const tileH = Number(obj['tileH']);
  const cols = Number(obj['cols']);
  const rows = Number(obj['rows']);
  const chunkSize = Number(obj['chunkSize']);
  const layers = obj['layers'] as Record<string, string[]>;
  const spawn = obj['playerSpawn'] as Record<string, number>;

  if (!(tileW > 0) || !(tileH > 0) || !(cols > 0) || !(rows > 0) || !(chunkSize > 0)) {
    throw new Error(`invalid map header: tileW=${tileW} tileH=${tileH} cols=${cols} rows=${rows} chunkSize=${chunkSize}`);
  }
  const rowsText: string[] = layers !== undefined && layers['collision'] !== undefined
    ? layers['collision'] : [];
  if (rowsText.length !== rows) {
    throw new Error(`collision layer rows ${rowsText.length} != rows ${rows}`);
  }
  const tiles: TileKind[] = new Array(rows * cols).fill(TileKind.EMPTY);
  for (let r = 0; r < rows; r++) {
    const line = rowsText[r];
    for (let c = 0; c < cols; c++) {
      const ch = c < line.length ? line[c] : '.';
      const kind = TILE_CHARS.get(ch);
      tiles[r * cols + c] = kind === undefined ? TileKind.EMPTY : kind;
    }
  }
  return {
    tileW: tileW, tileH: tileH, cols: cols, rows: rows, chunkSize: chunkSize,
    tiles: tiles,
    playerSpawn: { x: Number(spawn['x']), y: Number(spawn['y']) }
  };
}

/** 便捷构造（测试用） */
export function buildMapData(cols: number, rows: number, rowsText: string[],
  tileW: number = 32, tileH: number = 32, chunkSize: number = 16): MapData {
  return parseMapData({
    tileW: tileW, tileH: tileH, cols: cols, rows: rows, chunkSize: chunkSize,
    layers: { collision: rowsText },
    playerSpawn: { x: 64, y: 0 }
  });
}

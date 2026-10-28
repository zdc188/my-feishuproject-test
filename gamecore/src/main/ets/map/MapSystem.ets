/**
 * 地图系统（DES-006）：相机跟随、chunk 预加载窗口、动态加载/卸载与失败兜底。
 */

import { MapData, TileKind } from './MapData';

export interface LoadedChunk {
  index: number;
  /** 空兜底 chunk：无 tile、地面线以下默认 solid，防坠落穿模 */
  isFallback: boolean;
}

export type ChunkLoadResult = { index: number; ok: boolean; fallback: boolean };

/** chunk 资源加载器：真实实现由 ResourceSystem 提供；测试注入伪造实现 */
export interface MapLoader {
  loadChunk(index: number): Promise<void>;
  releaseChunk(index: number): void;
}

export class MapSystem {
  readonly data: MapData;
  private loader: MapLoader;
  private cameraX: number = 0;
  private viewportW: number = 0;
  private loadedChunks: Map<number, LoadedChunk> = new Map();
  private failedOnce: Set<number> = new Set();  // 重试 1 次的记录
  private pendingChunks: Set<number> = new Set();

  constructor(data: MapData, loader: MapLoader, viewportW: number = 1280) {
    this.data = data;
    this.loader = loader;
    this.viewportW = viewportW;
  }

  get chunkCols(): number {
    return Math.ceil(this.data.cols / this.data.chunkSize);
  }

  mapWidthPx(): number {
    return this.data.cols * this.data.tileW;
  }

  mapHeightPx(): number {
    return this.data.rows * this.data.tileH;
  }

  chunkCount(): number {
    return this.chunkCols;
  }

  /** 相机跟随：角色保持视口约 40% 位置，clamp 到 [0, mapW - viewportW] */
  updateCamera(playerCenterX: number): number {
    const mapW = this.mapWidthPx();
    const maxCam = Math.max(0, mapW - this.viewportW);
    this.cameraX = Math.max(0, Math.min(maxCam, playerCenterX - this.viewportW * 0.4));
    return this.cameraX;
  }

  getCameraX(): number {
    return this.cameraX;
  }

  setViewport(w: number): void {
    this.viewportW = w;
  }

  /** 视口 ± 1 chunk 预加载窗口（chunk 索引区间） */
  windowRange(): { first: number; last: number } {
    const firstVisible = Math.floor(this.cameraX / (this.data.chunkSize * this.data.tileW));
    const visibleCount = Math.ceil(this.viewportW / (this.data.chunkSize * this.data.tileW));
    const first = Math.max(0, firstVisible - 1);
    const last = Math.min(this.chunkCols - 1, firstVisible + visibleCount + 1);
    return { first: first, last: last };
  }

  /** 按窗口加载/卸载 chunk。加载失败重试 1 次；仍失败用空 chunk 兜底，不崩溃（异步不阻塞循环） */
  async updateChunks(): Promise<ChunkLoadResult[]> {
    const results: ChunkLoadResult[] = [];
    const win = this.windowRange();
    // 卸载移出窗口的 chunk
    for (const index of Array.from(this.loadedChunks.keys())) {
      if (index < win.first || index > win.last) {
        this.loadedChunks.delete(index);
        this.loader.releaseChunk(index);
      }
    }
    // 加载进入窗口的 chunk（优先移动方向：按索引升序预取即可覆盖向右主流方向）
    for (let index = win.first; index <= win.last; index++) {
      if (this.loadedChunks.has(index) || this.pendingChunks.has(index)) {
        continue;
      }
      this.pendingChunks.add(index);
      try {
        await this.loader.loadChunk(index);
        this.loadedChunks.set(index, { index: index, isFallback: false });
        results.push({ index: index, ok: true, fallback: false });
      } catch (e) {
        if (!this.failedOnce.has(index)) {
          // 重试 1 次
          this.failedOnce.add(index);
          this.pendingChunks.delete(index);
          try {
            await this.loader.loadChunk(index);
            this.loadedChunks.set(index, { index: index, isFallback: false });
            results.push({ index: index, ok: true, fallback: false });
            continue;
          } catch (e2) {
            console.error(`[MapSystem] chunk ${index} retry failed: ${JSON.stringify(e2)}`);
          }
        } else {
          console.error(`[MapSystem] chunk ${index} load failed: ${JSON.stringify(e)}`);
        }
        // 兜底空 chunk
        this.loadedChunks.set(index, { index: index, isFallback: true });
        results.push({ index: index, ok: false, fallback: true });
      } finally {
        this.pendingChunks.delete(index);
      }
    }
    return results;
  }

  isChunkLoaded(index: number): boolean {
    return this.loadedChunks.has(index);
  }

  isFallbackChunk(index: number): boolean {
    const c = this.loadedChunks.get(index);
    return c !== undefined && c.isFallback;
  }

  getTile(col: number, row: number): TileKind {
    if (col < 0 || col >= this.data.cols || row < 0 || row >= this.data.rows) {
      return TileKind.EMPTY;
    }
    return this.data.tiles[row * this.data.cols + col];
  }

  /** 兜底空 chunk 的地面线：chunk 内最下 2 行视为 solid，防坠落穿模 */
  isEffectivelySolid(col: number, row: number): boolean {
    if (col < 0 || col >= this.data.cols || row < 0 || row >= this.data.rows) {
      return false;
    }
    const tile = this.getTile(col, row);
    if (tile === TileKind.SOLID) {
      return true;
    }
    const chunk = Math.floor(col / this.data.chunkSize);
    const fallback = this.isFallbackChunk(chunk);
    if (fallback && row >= this.data.rows - 2) {
      return true;
    }
    return false;
  }
}

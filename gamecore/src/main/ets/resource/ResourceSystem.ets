/**
 * 资源管理系统（DES-007）：分级加载、LRU 淘汰、优先级卸载、失败兜底。
 * 加载器由外部注入（entry 侧用真实媒体资源加载；单测注入失败实现）。
 */

export enum ResourcePriority {
  AUDIO = 0,        // 音效（最先卸载）
  ATLAS = 1,        // 次要图集
  MAP_CHUNK = 2,    // 非窗口 chunk
  CORE = 3          // 核心资源（角色图集/首屏 chunk/UI），不卸载
}

export type ResourceHandle = object;

/** 资源加载器：load 成功返回句柄；失败抛异常（由 ResourceSystem 兜底） */
export interface ResourceLoader {
  load(key: string): Promise<ResourceHandle>;
}

export interface ResourceEntry {
  key: string;
  priority: ResourcePriority;
  handle: ResourceHandle;
  isPlaceholder: boolean;
  lastUsed: number;  // LRU 时间戳（逻辑时钟，ms）
  refCount: number;
}

export class ResourceSystem {
  private cache: Map<string, ResourceEntry> = new Map();
  private loader: ResourceLoader;
  private maxEntries: number;
  private clock: number = 0;
  private placeholder: ResourceHandle = { placeholder: true };
  private loadErrors: string[] = [];

  constructor(loader: ResourceLoader, maxEntries: number = 64) {
    this.loader = loader;
    this.maxEntries = maxEntries;
  }

  now(): number {
    this.clock += 1;
    return this.clock;
  }

  /** 同步获取缓存（未命中/未加载完成时返回 null） */
  peek(key: string): ResourceEntry | null {
    const e = this.cache.get(key);
    if (e !== undefined) {
      e.lastUsed = this.now();
      return e;
    }
    return null;
  }

  /** 异步加载；失败时使用占位资源（1x1 透明贴图/默认静音语义）继续运行，不崩溃 */
  async load(key: string, priority: ResourcePriority): Promise<ResourceEntry> {
    const hit = this.cache.get(key);
    if (hit !== undefined) {
      hit.lastUsed = this.now();
      return hit;
    }
    let entry: ResourceEntry;
    try {
      const handle = await this.loader.load(key);
      entry = { key: key, priority: priority, handle: handle, isPlaceholder: false, lastUsed: this.now(), refCount: 0 };
    } catch (e) {
      this.loadErrors.push(`load failed: ${key}: ${JSON.stringify(e)}`);
      entry = { key: key, priority: priority, handle: this.placeholder, isPlaceholder: true, lastUsed: this.now(), refCount: 0 };
    }
    this.cache.set(key, entry);
    this.evictIfNeeded();
    return entry;
  }

  acquire(key: string): void {
    const e = this.cache.get(key);
    if (e !== undefined) {
      e.refCount += 1;
    }
  }

  /** 引用计数为 0 才真正释放，避免卸载正在使用的资源 */
  release(key: string): boolean {
    const e = this.cache.get(key);
    if (e === undefined) {
      return false;
    }
    e.refCount = Math.max(0, e.refCount - 1);
    if (e.refCount === 0 && e.priority !== ResourcePriority.CORE) {
      this.cache.delete(key);
      return true;
    }
    return false;
  }

  /** LRU 淘汰：超容量时按 lastUsed 最旧逐出（核心资源也计入 LRU 但通常最近使用） */
  private evictIfNeeded(): void {
    while (this.cache.size > this.maxEntries) {
      let oldestKey: string | null = null;
      let oldestTime = Number.MAX_SAFE_INTEGER;
      for (const [k, v] of this.cache) {
        if (v.refCount === 0 && v.lastUsed < oldestTime) {
          oldestTime = v.lastUsed;
          oldestKey = k;
        }
      }
      if (oldestKey === null) {
        break; // 全部被引用则不逐出（宁可占用）
      }
      this.cache.delete(oldestKey);
    }
  }

  /** 内存压力响应：按优先级从低到高卸载非关键资源（音效 -> 次要图集 -> 非窗口 chunk） */
  onMemoryPressure(pinnedKeys: string[] = []): string[] {
    const pinned = new Set<string>(pinnedKeys);
    const evicted: string[] = [];
    const order = [ResourcePriority.AUDIO, ResourcePriority.ATLAS, ResourcePriority.MAP_CHUNK];
    for (const prio of order) {
      for (const [k, v] of Array.from(this.cache.entries())) {
        if (v.priority === prio && !pinned.has(k) && v.refCount === 0) {
          this.cache.delete(k);
          evicted.push(k);
        }
      }
    }
    return evicted;
  }

  /** 强制移除（测试用） */
  forceRemove(key: string): void {
    this.cache.delete(key);
  }

  has(key: string): boolean {
    return this.cache.has(key);
  }

  errors(): string[] {
    return this.loadErrors.slice();
  }
}

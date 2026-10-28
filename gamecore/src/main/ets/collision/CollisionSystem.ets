/**
 * 碰撞检测系统（DES-005）：逐轴 AABB 与 tile 网格碰撞。
 * 查询按角色包围盒膨胀一格后的 tile 范围扫描，复杂度 O(覆盖 tile 数)，
 * 不做全图遍历，保证单帧逻辑更新在预算内。
 */

import { MapSystem } from '../map/MapSystem';
import { TileKind } from '../map/MapData';

export interface CollisionResult {
  hitWall: boolean;       // 水平阻挡
  landed: boolean;        // 垂直落地
  hitCeil: boolean;        // 撞顶
  triggers: number[];     // 本步进入的触发器 tile 索引列表 [col, row, ...] 扁平存储
  enemyHits: number[];     // 与敌人碰撞体重叠的 tile 索引列表
}

export interface AABB {
  left: number; top: number; right: number; bottom: number;
}

export function aabbOf(x: number, y: number, w: number, h: number): AABB {
  return { left: x, top: y, right: x + w, bottom: y + h };
}

export function aabbOverlap(a: AABB, b: AABB): boolean {
  return a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
}

export class CollisionSystem {
  constructor(private map: MapSystem) {}

  /**
   * 水平阶段修正：角色 X 移动后，检查包围盒覆盖 tile 中 solid 的重叠，
   * 命中则贴齐 tile 边缘并要求调用方将 vx 置 0。
   */
  resolveHorizontal(box: AABB, vx: number): { blocked: boolean; newX: number } {
    const data = this.map.data;
    const col0 = Math.max(0, Math.floor(box.left / data.tileW) - 1);
    const col1 = Math.min(data.cols - 1, Math.floor((box.right - 0.01) / data.tileW) + 1);
    const row0 = Math.floor(box.top / data.tileH);
    const row1 = Math.floor((box.bottom - 0.01) / data.tileH);
    for (let row = row0; row <= row1; row++) {
      for (let col = col0; col <= col1; col++) {
        if (!this.map.isEffectivelySolid(col, row)) {
          continue;
        }
        const tileBox = aabbOf(col * data.tileW, row * data.tileH, data.tileW, data.tileH);
        if (aabbOverlap(box, tileBox)) {
          if (vx > 0) {
            return { blocked: true, newX: tileBox.left - (box.right - box.left) };
          } else if (vx < 0) {
            return { newX: tileBox.right, blocked: true };
          }
        }
      }
    }
    return { blocked: false, newX: box.left };
  }

  /**
   * 垂直阶段修正：命中地面置 onGround=true / vy=0；命中天花板贴齐并下落。
   */
  resolveVertical(box: AABB, vy: number): { landed: boolean; hitCeil: boolean; newY: number } {
    const data = this.map.data;
    const col0 = Math.floor(box.left / data.tileW);
    const col1 = Math.floor((box.right - 0.01) / data.tileW);
    const row0 = Math.max(0, Math.floor(box.top / data.tileH) - 1);
    const row1 = Math.min(data.rows - 1, Math.floor((box.bottom - 0.01) / data.tileH) + 1);
    for (let row = row0; row <= row1; row++) {
      for (let col = col0; col <= col1; col++) {
        if (!this.map.isEffectivelySolid(col, row)) {
          continue;
        }
        const tileBox = aabbOf(col * data.tileW, row * data.tileH, data.tileW, data.tileH);
        if (aabbOverlap(box, tileBox)) {
          if (vy >= 0) {
            return { landed: true, hitCeil: false, newY: tileBox.top - (box.bottom - box.top) };
          } else {
            return { landed: false, hitCeil: true, newY: tileBox.bottom };
          }
        }
      }
    }
    return { landed: false, hitCeil: false, newY: box.top };
  }

  /**
   * 触发器与敌人碰撞体检测（不阻挡移动，重叠即派发事件——由调用方转发 EventBus）。
   */
  scanOverlaps(box: AABB): { triggers: number[]; enemyHits: number[] } {
    const data = this.map.data;
    const triggers: number[] = [];
    const enemyHits: number[] = [];
    const col0 = Math.floor(box.left / data.tileW);
    const col1 = Math.floor((box.right - 0.01) / data.tileW);
    const row0 = Math.floor(box.top / data.tileH);
    const row1 = Math.floor((box.bottom - 0.01) / data.tileH);
    for (let row = row0; row <= row1; row++) {
      for (let col = col0; col <= col1; col++) {
        const tile = this.map.getTile(col, row);
        const tileBox = aabbOf(col * data.tileW, row * data.tileH, data.tileW, data.tileH);
        if (tile === TileKind.TRIGGER && aabbOverlap(box, tileBox)) {
          triggers.push(col, row);
        } else if (tile === TileKind.ENEMY && aabbOverlap(box, tileBox)) {
          enemyHits.push(col, row);
        }
      }
    }
    return { triggers: triggers, enemyHits: enemyHits };
  }
}

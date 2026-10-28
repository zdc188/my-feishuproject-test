/**
 * 渲染适配接口（渲染适配层抽象）：gamecore 不 import 任何 ArkUI 渲染 API。
 * 路线二由 entry 侧 CanvasRenderAdapter（ArkUI Canvas）实现；
 * 若 POC 选定路线一，则提供 Cocos 侧同名实现，玩法模块不动。
 */

export interface DrawTileCmd {
  col: number;      // 地图 tile 列
  row: number;      // 地图 tile 行
  tileW: number;    // tile 像素宽
  tileH: number;    // tile 像素高
  atlasIndex: number; // 图集子矩形索引
}

export interface DrawSpriteCmd {
  /** 世界坐标（左上角） */
  x: number;
  y: number;
  width: number;
  height: number;
  atlasIndex: number; // 精灵图集子矩形索引
  flip: boolean;      // 水平翻转（朝向）
}

export interface RenderContext {
  cameraX: number;
  viewportW: number;
  viewportH: number;
  /** accumulator 插值 alpha = accumulator / LOGIC_STEP，用于渲染平滑 */
  alpha: number;
}

export interface RenderAdapter {
  /** 清屏（含背景视差层） */
  clear(ctx: RenderContext): void;
  /** 地形 tile 层（视口裁剪由实现负责，只画可见列） */
  drawTiles(cmds: DrawTileCmd[], ctx: RenderContext): void;
  /** 实体层：角色/敌人/特效（分层绘制顺序由调用方保证） */
  drawSprites(cmds: DrawSpriteCmd[], ctx: RenderContext): void;
  /** 提交本帧（双缓冲语义） */
  present(ctx: RenderContext): void;
}

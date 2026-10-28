/**
 * 路线二渲染适配（DES-008）：基于 ArkUI Canvas + CanvasRenderingContext2D。
 * 分层绘制：背景视差层 -> 地形 tile 层 -> 实体层；视口裁剪只绘制可见 tile。
 * 占位美术：用色块绘制（正式资源到位后替换为图集子矩形绘制，接口不变）。
 */

import {
  RenderAdapter, RenderContext, DrawTileCmd, DrawSpriteCmd
} from 'gamecore';

const TILE_COLORS: Record<string, string> = {
  '1': '#6B4F2A',  // solid 地形
  '2': '#FFD24C',  // trigger
  '3': '#D9534F'   // enemy
};

export class CanvasRenderAdapter implements RenderAdapter {
  private ctx: CanvasRenderingContext2D;

  constructor(ctx: CanvasRenderingContext2D) {
    this.ctx = ctx;
  }

  clear(rc: RenderContext): void {
    const ctx = this.ctx;
    // 背景视差层（占位：天空渐变 + 0.3 倍视差远山）
    ctx.clearRect(0, 0, rc.viewportW, rc.viewportH);
    const grad = ctx.createLinearGradient(0, 0, 0, rc.viewportH);
    grad.addColorStop(0, '#4A90D9');
    grad.addColorStop(1, '#B8E0F5');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, rc.viewportW, rc.viewportH);
    ctx.fillStyle = '#7FA8C9';
    const parallax = rc.cameraX * 0.3;
    const hillW = 240;
    const start = Math.floor(parallax / hillW) - 1;
    for (let i = start; i < start + Math.ceil(rc.viewportW / hillW) + 2; i++) {
      const hx = i * hillW - parallax;
      const h = 80 + (i % 3) * 40;
      ctx.fillRect(hx, rc.viewportH - h - 120, hillW - 40, h + 120);
    }
  }

  drawTiles(cmds: DrawTileCmd[], rc: RenderContext): void {
    const ctx = this.ctx;
    const data = cmds;
    for (let i = 0; i < data.length; i++) {
      const cmd = data[i];
      // 视口裁剪：tile 屏幕外不绘制（调用方已裁剪，此处再防御一次）
      const sx = cmd.col * cmd.tileW - rc.cameraX;
      if (sx > rc.viewportW || sx + cmd.tileW < 0) {
        continue;
      }
      const sy = cmd.row * cmd.tileH;
      if (sy > rc.viewportH || sy + cmd.tileH < 0) {
        continue;
      }
      ctx.fillStyle = TILE_COLORS[`${cmd.atlasIndex}`] !== undefined ? TILE_COLORS[`${cmd.atlasIndex}`] : '#999999';
      ctx.fillRect(sx, sy, cmd.tileW, cmd.tileH);
      // tile 顶面高亮（占位）
      ctx.fillStyle = '#FFFFFF22';
      ctx.fillRect(sx, sy, cmd.tileW, 4);
    }
  }

  drawSprites(cmds: DrawSpriteCmd[], rc: RenderContext): void {
    const ctx = this.ctx;
    for (let i = 0; i < cmds.length; i++) {
      const cmd = cmds[i];
      const sx = cmd.x - rc.cameraX;
      ctx.save();
      if (cmd.flip) {
        ctx.translate(sx + cmd.width, cmd.y);
        ctx.scale(-1, 1);
        ctx.fillRect(0, 0, cmd.width, cmd.height);
      } else {
        ctx.translate(sx, cmd.y);
        ctx.fillRect(0, 0, cmd.width, cmd.height);
      }
      // 占位角色：身体 + 眼睛
      ctx.fillStyle = '#2E7D32';
      ctx.fillRect(0, 0, cmd.width, cmd.height);
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(cmd.width * 0.6, cmd.height * 0.2, 6, 6);
      ctx.restore();
    }
  }

  present(rc: RenderContext): void {
    // ArkUI Canvas 为立即模式，无显式提交；保留接口以兼容双缓冲后端
  }
}

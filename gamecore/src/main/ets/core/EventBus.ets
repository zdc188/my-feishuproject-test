/**
 * EventBus（引擎核心层）：模块间解耦通信。
 * 碰撞事件、触发器事件、资源事件通过它派发，避免模块互相持有引用。
 */

export type EventHandler = (payload: object) => void;

export class EventBus {
  private handlers: Map<string, EventHandler[]> = new Map();

  on(event: string, handler: EventHandler): void {
    const list = this.handlers.get(event);
    if (list === undefined) {
      this.handlers.set(event, [handler]);
    } else {
      list.push(handler);
    }
  }

  off(event: string, handler: EventHandler): void {
    const list = this.handlers.get(event);
    if (list === undefined) {
      return;
    }
    const idx = list.indexOf(handler);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
  }

  emit(event: string, payload: object = {}): void {
    const list = this.handlers.get(event);
    if (list === undefined) {
      return;
    }
    // 拷贝后遍历，允许回调内注销自身
    for (const h of list.slice()) {
      try {
        h(payload);
      } catch (e) {
        // 单个回调异常不中断其它订阅者与游戏循环
        console.error(`[EventBus] handler error on ${event}: ${JSON.stringify(e)}`);
      }
    }
  }

  listenerCount(event: string): number {
    const list = this.handlers.get(event);
    return list === undefined ? 0 : list.length;
  }
}

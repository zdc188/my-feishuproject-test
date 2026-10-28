import { UIAbility, Type, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: object): void {
    console.info('[EntryAbility] onCreate');
  }

  onDestroy(): void {
    console.info('[EntryAbility] onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 启动中 -> 资源加载中 的迁移由 GamePage 完成窗口加载后触发（DES-009）
    windowStage.loadContent('pages/GamePage', (err) => {
      if (err.code) {
        console.error(`[EntryAbility] loadContent failed: ${JSON.stringify(err)}`);
        return;
      }
      windowStage.getMainWindow((winErr, win) => {
        if (winErr.code || win === undefined) {
          return;
        }
        // 横版游戏：锁定横屏
        try {
          win.setPreferredOrientation(window.Orientation.LANDSCAPE);
        } catch (e) {
          console.error(`[EntryAbility] setPreferredOrientation failed: ${JSON.stringify(e)}`);
        }
        // 屏幕常亮
        try {
          win.setWindowKeepScreenOn(true);
        } catch (e) {
          console.error(`[EntryAbility] setWindowKeepScreenOn failed: ${JSON.stringify(e)}`);
        }
      });
    });
  }

  onWindowStageDestroy(): void {
    console.info('[EntryAbility] onWindowStageDestroy');
  }

  onForeground(): void {
    console.info('[EntryAbility] onForeground');
  }

  onBackground(): void {
    console.info('[EntryAbility] onBackground');
  }
}

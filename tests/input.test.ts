/**
 * DES-003 输入映射：杆量死区、按键边沿。
 */

import { test, assertEq } from './harness';
import { InputSystem, joystickToAxis, JOYSTICK_DEAD_ZONE } from '../src/input/InputSystem';

test('死区内杆量为 0（角色待机）', () => {
  assertEq(joystickToAxis(0.05, 0.05), 0, 'small vector dead zone');
  assertEq(joystickToAxis(0, 0.5), 0, 'pure vertical dead zone');
});

test('死区外幅度按 [死区,1] 线性归一（0.5 摇杆 -> ~0.444）', () => {
  const v = joystickToAxis(0.5, 0);
  assertEq(Math.abs(v - (0.5 - JOYSTICK_DEAD_ZONE) / (1 - JOYSTICK_DEAD_ZONE)) < 1e-9, true, 'linear mapping');
});

test('死区外水平分量决定方向（右为正）', () => {
  const v = joystickToAxis(0.5, 0);
  assertEq(v > 0, true, 'right positive');
  const vL = joystickToAxis(-0.5, 0);
  assertEq(vL < 0, true, 'left negative');
});

test('满杆映射幅度不超过 1', () => {
  const v = joystickToAxis(1, 0);
  assertEq(v <= 1 && v > 0.8, true, 'full axis normalized');
});

test('跳跃按键边沿：仅第一步 justPressed，持续按住不再触发', () => {
  const sys = new InputSystem();
  sys.setJump(true);
  const s1 = sys.snapshot();
  const s2 = sys.snapshot();
  assertEq(s1.jumpJustPressed, true, 'edge on first snapshot');
  assertEq(s2.jumpJustPressed, false, 'no edge while held');
  assertEq(s2.jumpHeld, true, 'held');
  sys.setJump(false);
  const s3 = sys.snapshot();
  assertEq(s3.jumpHeld, false, 'released');
  sys.setJump(true);
  const s4 = sys.snapshot();
  assertEq(s4.jumpJustPressed, true, 're-press produces edge');
});

test('快照不串改杆量：moveAxis 在快照间保持', () => {
  const sys = new InputSystem();
  sys.setMoveAxis(-0.7);
  const s = sys.snapshot();
  assertEq(s.moveAxis, -0.7, 'axis kept');
  const s2 = sys.snapshot();
  assertEq(s2.moveAxis, -0.7, 'axis still kept');
});

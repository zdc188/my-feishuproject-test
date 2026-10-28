/** 简易测试执行器（无外部依赖，node 直接运行） */

export type TestFn = () => void;
interface Case { name: string; fn: TestFn; }

const cases: Case[] = [];
let failed = 0;

export function test(name: string, fn: TestFn): void {
  cases.push({ name: name, fn: fn });
}

export function assert(cond: boolean, message: string): void {
  if (!cond) {
    throw new Error(`assert failed: ${message}`);
  }
}

export function assertEq<T>(actual: T, expected: T, message: string): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    throw new Error(`assertEq failed: ${message}\n  actual:   ${a}\n  expected: ${e}`);
  }
}

export async function runAll(): Promise<number> {
  for (const c of cases) {
    try {
      await c.fn();
      console.log(`PASS ${c.name}`);
    } catch (e) {
      failed += 1;
      console.error(`FAIL ${c.name}`);
      console.error(e instanceof Error ? e.stack : String(e));
    }
  }
  console.log(`---- total=${cases.length} failed=${failed}`);
  return failed;
}

#!/usr/bin/env bash
# 准备 tsc 检查工作目录：把 gamecore 的 .ets（纯 ArkTS 逻辑，无 ArkUI 依赖）
# 复制为 .ts，并复制测试与地图 fixture。
# 说明：gamecore 设计上不 import 任何 ArkUI/鸿蒙 API（技术方案 DES 关键解耦决策），
# 因此其源码与标准 TypeScript 语法兼容，可用 tsc 做等价静态类型检查。
set -euo pipefail
cd "$(dirname "$0")"

rm -rf work dist
mkdir -p work/src work/tests work/fixtures

cp -r ../../gamecore/src/main/ets/* work/src/
find work/src -name '*.ets' | while read -r f; do
  mv "$f" "${f%.ets}.ts"
done

cp -r ../../tests/* work/tests/
cp ../../entry/src/main/resources/rawfile/map_level1.json work/fixtures/

echo "prepare: work/ ready"

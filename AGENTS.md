# AGENTS.md

AssetsOS 是一个 SwiftUI + SwiftData 的个人资产总账 iOS App。本文件是 agent 协作规则。

## 启动流程

1. 用 `pwd` 确认工作目录。
2. 读本文件。
3. 读 `docs/spec/README.md`，从索引定位这次要改的模块，再读该模块的规格文件。**不需要通读全部规格。**
4. 读 `CHANGELOG.md` 中该模块最近的条目——重点看标了 **决策** 的行，那些是已经被否决或已经定下来的方向，不要重复推翻。
5. 读 `TODO.md` 了解未解决问题。
6. 运行 `./init.sh` 验证基线。如果失败特征是 `sandbox-exec`、`CoreSimulator`、模拟器服务或执行环境限制，这是环境阻塞，直接提权重试，不要因此停下。
7. `git log --oneline -5` 看最近提交。

## 文档职责

只有三处文档，职责不重叠：

| 文件 | 回答 | 什么时候写 |
|---|---|---|
| `docs/spec/*.md` | 现在是什么样 | 改了行为就同步改，保持与代码一致 |
| `CHANGELOG.md` | 最近改了什么、哪些方向已被否决 | 每次有行为变更或定下决策时追加一条 |
| `TODO.md` | 还差什么 | 发现问题时加一条，解决后删掉 |

**不要新建其它跟踪文件。** 不要在文档里堆验证日志、截图路径、命令输出、会话叙事——那些留在 git commit 里。

## 工作规则

- **规格文档是功能真源。** 代码与 `docs/spec/` 冲突时，先判断哪一边是对的，然后让两边一致，不要放着分叉不管。
- **一次只做一件事。** 避免在屏幕、模型和持久化代码之间做无关重构。
- **严格控范围。** `docs/spec/README.md` 的"当前不做"清单里的能力不要主动实现。
- **必须验证。** 没有跑过验证或没有记录阻塞原因前，不要宣称完成。
- 高风险区域：备份、持久化、删除规则、金额计算。改之前先读对应规格章节。
- 构建产物写到仓库内 `build/`，不依赖用户目录写权限。
- 默认验证路径因权限不足失败时，直接申请权限重试，不要停在解释阶段。

## 验证

```bash
./init.sh
```

- 改完代码逻辑：默认执行 `./init.sh` 重新编译
- 用户**明确**要求用模拟器测试/验证：`./deploy.sh --sim`
- 用户**明确**要求截图：`./deploy.sh --sim --shot`
- 验证被环境、签名或 runtime 阻塞时，把精确失败信息写进 `TODO.md` 的"已知环境限制"

底层构建命令：

```bash
xcodebuild -project "$PWD/AssetsOS.xcodeproj" -scheme AssetsOS -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath "$PWD/build/DerivedData-harness" \
  SYMROOT="$PWD/build/harness" build
```

## 完成定义

- [ ] 行为符合对应的 `docs/spec/` 文件，或用户明确给了覆盖要求
- [ ] 已实际运行验证，或已记录阻塞原因
- [ ] 有行为变更时，`docs/spec/` 对应模块已更新，`CHANGELOG.md` 已追加一条
- [ ] 没有无理由修改无关文件
- [ ] 仓库仍可从 `./init.sh` 重新启动

## 升级处理

- `./init.sh` 因环境限制失败时，先判断是项目问题还是沙箱/runtime 问题，再决定要不要动产品代码。
- 需求不清晰时，把 `docs/spec/` 中相关段落摘出来，向用户确认，不要自行扩大范围。

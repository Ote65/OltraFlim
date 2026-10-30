# AGENTS.md — OltraFlim

本文件是所有 coding agent 的入口规则。开始任务前必须读：

1. `CODE_MAP.md` — 代码地图、数据流、热点文件
2. `STATUS.md` — 当前版本、已验证/未验证事项、已知边界
3. `docs/DEVELOPMENT.md` — 本机构建环境
4. `docs/MULTI_AGENT_COORDINATION.md` — 多 agent / 多机器协作协议
5. `THIRD_PARTY_NOTICES.md` — 授权边界

## 1. 项目身份

- Product: **OltraFlim** — native macOS film-simulation darkroom.
- Stack: SwiftUI + AppKit + Metal, macOS 14+.
- Version: **1.4 / build 5**.
- Repo: `https://github.com/Ote65/OltraFlim`.
- License: application code is **PolyForm Noncommercial 1.0.0**; LUT/profile
  derivatives remain **CC BY-SA 4.0**. Never relicense upstream assets.

## 2. 绝对规则

1. **未经用户明确授权，不得启动 App、点击 UI、移动窗口或做桌面自动化。**
   - 用户负责 UI 验收。
   - 构建可以，启动/测试不可以。
   - 不要 `open dist/OltraFlim.app`、不要 `pkill -x OltraFlim`、不要用
     AppleScript/JXA/CGEvent 操作窗口。
2. **只用 `--no-launch` 做验证。**
   ```bash
   ./script/build_and_run.sh --no-launch
   ```
3. **不要提交 secrets。** 不要提交 `.env`、token、keychain 导出、签名证书、
   provisioning profile、用户照片、`dist/`、`.build/`。
4. **不要修改上游许可证或署名文件**：
   - `Resources/SPEKTRAFILM_LICENSE.txt`
   - `Resources/LUT_NOTICE.md`
   - `LICENSE`、`THIRD_PARTY_NOTICES.md` 的授权范围说明。
5. **不要删除用户数据**：`~/Library/Application Support/OltraFlim`
   里有用户路径/编辑/收藏。清理测试数据前必须确认那是测试数据并得到允许。
6. **不要伪造验证结果。** 编译通过 ≠ UI 通过；没有启动就写“未做 UI 测试”。
7. **不要在热点文件上并行写。** 见第 5 节。

## 3. 构建与验证

### 只编译 / 暂存（默认）

```bash
./script/build_and_run.sh --no-launch
```

输出 `dist/OltraFlim.app`，不启动进程。

### 编译到临时二进制（最快类型检查）

```bash
SDK=$(xcrun --show-sdk-path)
TC=.build/toolchain
SOURCES=(${(f)"$(find Sources/OltraFlim -name '*.swift' | sort)"})
swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" -sdk "$SDK" \
  -module-name OltraFlim -module-cache-path .build/modulecache \
  -resource-dir "$TC/lib/swift" -Xcc -I"$TC/include" -swift-version 5 -O \
  -framework SwiftUI -framework AppKit -framework Combine -framework Metal \
  -framework MetalKit -framework QuartzCore -framework CoreGraphics \
  -framework CoreImage -framework ImageIO -framework UniformTypeIdentifiers \
  -framework Foundation "${SOURCES[@]}" -o /tmp/OltraFlim-check
```

### 允许的验证

- `swiftc` 编译。
- 无头 `Tools/RenderCheck.swift`（不启动 App）。
- `plutil` 检查 Info.plist、`hdiutil` 检查 DMG 内容、`shasum` 校验。
- 静态检查/`grep`/`strings` 检查二进制包含功能符号。
- 不能声称 UI 通过；UI 标记为 **Manual test required (owner)**。

### 基线

- 当前唯一编译警告：`AppModel.swift` Toast Task 的 Swift 6 并发捕获。
- 任何新增错误/警告必须在 PR 中说明。
- 运行时 shader 编译错误不会在 `swiftc` 阶段暴露；相关改动必须标记手测。

## 4. 代码约定

- 遵循现有 `DS` token（`Support/DesignSystem.swift`）；不要引入新的颜色/
  圆角/动画常量，除非复用现有 token。
- **UI 中严禁出现任何形式的滚动条**（除非用户明确要求）：SwiftUI 滚动容器
  一律 `.scrollIndicators(.never)`；AppKit `NSScrollView` 必须
  `hasHorizontalScroller = false`、`hasVerticalScroller = false`。
  需要提示还有内容时用渐隐遮罩、悬停位移或少量露出的内容边缘，不要画滚动条。
- 所有用户可见文案用 `T("中文","English")`；默认中文。
- 不添加第三方依赖；不引入 Electron/WebView/Python 运行时。
- Metal uniform 布局必须与 `Shaders.metal` 的 `Uniforms` **字段顺序一致**；
  新增字段要同时改 Swift 与 Metal。
- 新参数必须同时覆盖：`Adjustments`、Codable、`RenderUniforms`、
  `Uniforms`、`processImage`、Inspector、README/STATUS。
- 照片库约定：
  - `folder == nil` 才是 loose 照片，才写入 `libraryPhotoPaths`。
  - 文件夹内容按需扫描；不要复制/移动用户文件。
  - 收藏/颜色标签只写 `LibraryMetaStore`，不要塞进 `PhotoEdit`。
- 卡片/行交互：不要把 `Button` 嵌套进外层 `Button`；操作按钮放 overlay。
- 窗口拖动只来自 `TopBar`；`window.isMovableByWindowBackground = false`。
- 导出 `renderFull` 必须独立生成曲线纹理，不能复用预览的 `curveTexture`。
- 颗粒种子保持小数值（`abs(hash)%4096/100`），否则会退化成色偏。

## 5. 热点文件与所有权

| 文件 | 建议 owner | 并行规则 |
| --- | --- | --- |
| `Stores/AppModel.swift` | library/data owner | 同一时间只允许一个 agent 编辑；其他任务先提 issue 拆分 |
| `Engine/Renderer.swift` | engine owner | 与 shader 改动合并评审 |
| `Resources/Shaders.metal` | engine owner | uniform 顺序变更必须和 `Renderer.swift` 同一 PR |
| `Views/HomeLibraryView.swift` | library UI owner | 只追加独立组件可并行，主文件串行 |
| `Views/InspectorView.swift` | inspector owner | Tab/滑杆改动串行 |
| `Views/TopBar.swift` | shell owner | 窗口 chrome/traffic lights 串行 |
| `Views/CanvasView.swift` | canvas owner | 与 `CanvasState` 同 PR |

如果一个任务要跨两个热点文件，优先拆成两个 PR，或在 issue 中声明锁。

## 6. 任务与 Git 流程

1. 在 GitHub Issue 认领任务并评论 `claim: <agent> / <machine> / <branch>`。
2. 从 `main` 创建分支：
   `agent/<agent-id>/<issue>-<slug>` 或 `human/<name>/<slug>`。
3. 每个 agent 使用独立 worktree 或独立 clone：
   ```bash
   git worktree add ../Oflim-agent-a -b agent/a/123-library-filter
   ```
4. 小步提交；格式化/编译后再提交。
5. PR 描述必须包含：
   - 改了什么、为什么；
   - 影响文件；
   - 验证命令与结果；
   - 未验证项（特别是 UI）；
   - 是否需要 shader/手测。
6. 合并前 rebase `main`；不要 force-push 共享分支。
7. Squash merge 或环节清晰的 merge commit；不要提交 `dist/`、`.build/`。

## 7. 多 agent 交接

在 issue 或 PR 评论中使用：

```yaml
agent: <name>
machine: <hostname>
branch: <branch>
issue: #<number>
status: ready-for-review | blocked | handoff
changed:
  - path/to/file
verified:
  - ./script/build_and_run.sh --no-launch
  - <other>
not_verified:
  - UI: traffic lights / folder navigation (owner manual test)
known_risks:
  - <risk>
next:
  - <next step>
```

不得只在私有对话里交接；GitHub issue/PR 是唯一事实来源。

## 8. 发布

- 版本号：`Resources/Info.plist` + `SettingsView` + README/STATUS。
- 构建：`--no-launch`；打包 DMG/ZIP 不做启动测试。
- 校验：DMG 可挂载、版本正确、sha256 写入 `STATUS.md`/release notes。
- GitHub Release 资产：DMG + ZIP。
- 发布前必须确认：
  - 无 secrets / 用户照片 / dist 进入 Git；
  - 上游许可证完整；
  - README 简介/许可证说明更新；
  - UI 手测清单交给 owner。

## 9. 何时停下来问用户

- 需要启动 App 或做桌面自动化。
- 需要删除/覆盖用户照片、编辑记录、应用支持目录。
- 需要修改 License、上游 attribution、品牌名。
- 需要添加依赖、网络服务、云同步、账号体系。
- 需要改变产品核心行为（比如把非商业许可改成商业许可）。
- 两个 agent 同时持有同一热点文件且无法拆分。

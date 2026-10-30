# OltraFlim 代码地图

> 版本：1.3 / build 4  
> 更新：2026-10-30  
> 平台：macOS 14+，SwiftUI + AppKit + Metal  
> 入口：`Sources/OltraFlim/App/OltraFlimApp.swift`

这份地图面向接手开发的工程师和 agent。先读本文件，再读
[`AGENTS.md`](AGENTS.md)、[`STATUS.md`](STATUS.md) 和
[`docs/MULTI_AGENT_COORDINATION.md`](docs/MULTI_AGENT_COORDINATION.md)。

## 1. 一句话结构

```text
ImageLoader ──► Photo / PhotoEdit ──► AppModel ──► Renderer ──► MTKView / Export
                   ▲                     │
                   │                     ├── FilmBrowserView / HomeLibraryView
                   │                     ├── InspectorView / CurveTabView
                   │                     └── EditStore / LibraryMetaStore
                   │
                   └── LibraryFolder ◄── folder index / scan
```

- `AppModel` 是唯一的应用状态中心（`@Observable`，`AppModel.shared`）。
- `Renderer` 是唯一的 Metal 胶片引擎；预览和导出共用 shader，导出使用独立曲线纹理。
- 照片库是“路径索引”，不复制、不删除用户文件。
- 胶片外观是离线烘焙的显示级 LUT；运行时没有 Python/OpenColorIO/Electron。

## 2. 目录结构

```text
Oflim/
├── Sources/OltraFlim/
│   ├── App/            SwiftUI 入口、中文/English 菜单、AppDelegate
│   ├── Engine/         Metal 渲染、图像读取、LUT 导入/注册
│   ├── Models/         Photo、Adjustments、Curves、FilmCatalog、LibraryFolder
│   ├── Stores/         AppModel、EditStore、ImportedLUTStore、LibraryMetaStore
│   ├── Support/        DesignSystem、Localization、WindowConfigurator
│   └── Views/          HomeLibrary、TopBar、FilmBrowser、Canvas、Inspector、Curves…
├── Resources/
│   ├── LUTs/           113 个 33³ RGBA16F .bin + 2 个 neutral
│   ├── Sample/         sample_preview.jpg（无照片时的库卡片预览）
│   ├── catalog.json    45 个胶片 stock / 113 个 look / 默认 stock
│   ├── Shaders.metal   运行时编译的 Metal 着色器
│   ├── Info.plist      版本 1.3 / build 4
│   └── SPEKTRAFILM_LICENSE.txt, LUT_NOTICE.md
├── Tools/
│   ├── build_luts.py   ACES 2.0 + OCIO 离线烘焙 LUT 的工具
│   └── RenderCheck.swift 无头渲染校验工具（不随 App 发布）
├── script/
│   └── build_and_run.sh 直接 swiftc + .app 组装 + ad-hoc 签名
├── docs/
│   ├── DEVELOPMENT.md  环境、构建、打包、调试
│   └── MULTI_AGENT_COORDINATION.md  多 agent / 多机器协议
├── CODE_MAP.md / STATUS.md / AGENTS.md / CONTRIBUTING.md
├── LICENSE             PolyForm Noncommercial 1.0.0（应用代码）
└── THIRD_PARTY_NOTICES.md  上游 LUT / ACES / 样品图授权边界
```

## 3. 启动与状态流

### 3.1 启动

1. `OltraFlimApp` 创建 `WindowGroup`，注入 `AppModel.shared`。
2. `AppModel.init`：
   - 读取语言、显示模式、分组模式、browseStock、favorites 等偏好。
   - 解码 `catalog.json`。
   - 创建 `LUTLibrary` 与 `Renderer`（shader 在运行时编译）。
   - `prepareLibrary()` 后台加载 113 个内置 LUT。
   - `loadSamplePreview()` 加载无照片时的参考图。
   - `restoreLibrary()` 恢复**直接导入**的照片路径。
   - `restoreFolders()` 恢复文件夹索引（只读路径，不载入文件夹内照片）。
   - `importLaunchArguments()` 处理 `--open` 等测试参数。
3. `ContentView` 根据 `model.screen` 显示：
   - `.library` → `HomeLibraryView`
   - `.editor` → 左侧 FilmBrowser + 中间 Canvas/Filmstrip + 右侧 Inspector

### 3.2 从主页进入编辑

```text
HomeLibraryView photo card
  → AppModel.openPhoto(id)
  → screen = .editor
  → selectPhoto(id)
  → 若 previewLoaded 则 installPreview；否则 loadPreview 后台解码
  → CanvasView 显示 LoadingPhotoView，完成后安装纹理
```

返回：`TopBar` 的“照片库”按钮 → `AppModel.showLibrary()`，`folderTrail`
保持不变，因此回到的是同一个文件夹层级。

## 4. 文件地图

### 4.1 App

| 文件 | 责任 |
| --- | --- |
| `App/OltraFlimApp.swift` | `@main` Scene、菜单、快捷键；导入照片/文件夹/LUT、导出、比较、上一张/下一张、设置 |
| `AppDelegate`（同文件） | 退出时保存等 AppKit 生命周期粘合 |

### 4.2 Engine

| 文件 | 责任 | 关键入口 |
| --- | --- | --- |
| `Renderer.swift` | Metal 设备/队列、运行时编译 shader、纹理、uniform、预览、导出、直方图、缩略图批量渲染、`CanvasState` 缩放/平移动画 | `draw(in:)`, `renderFull`, `encodeProcess`, `CanvasState` |
| `Shaders.metal` | 全部影像算法：白平衡、曝光、高光/阴影/白/黑、饱和、局部对比、光晕、LUT、曲线、色彩分级、通透、褪色、暗角、颗粒、抖动 | `processImage`, `bloomExtract`, `histogram`, `displayVertex/Fragment` |
| `ImageLoader.swift` | ImageIO 解码、EXIF、缩略图、预览、全分辨率、统计信息 | `loadPreview`, `loadFull`, `thumbnail` |
| `LUTLibrary.swift` | 加载内置/中性 LUT；用户 LUT 注册、查询、删除；资源定位 | `load(device:catalog:)`, `film`, `neutral0`, `userLUT` |
| `LUTImporter.swift` | 解析 3D `.cube`、RGBA16F 落盘、创建 Metal 3D texture、identity swatch | `parse`, `writeBinary`, `makeTexture` |
| `CurveTexture.swift` | 将 `CurveSet` 采样成 256×1 RGBA16F 曲线纹理；R/G/B 为通道，A 为明暗 | `CurveTextureBuilder.make` |

### 4.3 Models

| 文件 | 责任 |
| --- | --- |
| `Photo.swift` | `Adjustments`（全部滑块 + 自定义 Codable 兼容旧数据）、`PhotoEdit`（look/LUT/曲线）、`PhotoMetadata`、`Photo`、`ToneStats`、`HistogramData`、`PhotoColorLabel` |
| `Curves.swift` | `CurveChannel`、`CurvePoint`、`ChannelCurve`、`CurveSet`、PCHIP 单调三次插值 `CurveMath.values` |
| `FilmCatalog.swift` | `FilmCatalog`、`FilmStock`、`FilmVariant`、`CatalogIndex`、品牌/类型/引擎信息 |
| `LibraryFolder.swift` | 文件夹索引记录；`countText` 用于主页卡片 |
| `ImportedLUT.swift` | 用户 LUT 的 id、名称、size、文件名、创建时间、swatch |

### 4.4 Stores

| 文件 | 责任 |
| --- | --- |
| `AppModel.swift` | 应用状态与用例：照片库、文件夹、筛选/分组、收藏/颜色标签、编辑持久化、导入/导出、LUT 导入、直方图分析、通透、预览缩略图、测试启动参数、Toast/Alert |
| `EditStore.swift` | 按标准化文件路径保存 `PhotoEdit`（`edits.json`） |
| `ImportedLUTStore.swift` | 用户 LUT 二进制 + registry（Application Support/LUTs） |
| `LibraryMetaStore.swift` | 收藏、颜色标签，按路径保存在 `libraryMeta.json`；与显影参数分离 |

### 4.5 Views

| 文件 | 责任 | 备注 |
| --- | --- | --- |
| `HomeLibraryView.swift` | 主页照片库：文件夹/照片网格或列表、筛选、群组、搜索、收藏/颜色菜单、导入按钮、空状态 | 最长的 UI 文件（~1290 行），改动时注意卡片嵌套 Button |
| `TopBar.swift` | 46pt 标题条、返回照片库、照片信息、logo、自绘 traffic lights、窗口拖拽手势 | 窗口拖拽只在这里；`WindowTrafficLights` 隐藏系统按钮 |
| `FilmBrowserView.swift` | 左侧胶片/LUT 库、搜索、品牌/类型/引擎筛选、胶片卡片、变体、LUT 导入/删除、`SearchField` 供主页复用 | |
| `CanvasView.swift` | MTKView 包装、空状态、加载、CompareButton/CompareOverlay、缩放控件、元数据行、滚轮/捏合/拖拽/空格 | Ctrl/Cmd/Option + 滚轮；窗口拖动关闭后画布拖拽才有效 |
| `InspectorView.swift` | 右侧显影栏：header、直方图、LookCard、三个 Tab、通透/细节/胶片质感/信息、底部固定 Reset/Export/Settings | 底部 `actionBar` 不滚动 |
| `CurveTabView.swift` | 明暗/R/G/B 曲线编辑器、直方图背景、拖点约束、重置 | 曲线在胶片 LUT 之后、通透之前应用 |
| `FilmstripView.swift` | 编辑页底部照片条；使用 `collectionPhotos`（当前照片所在文件夹或根库） | |
| `ExportSheet.swift` | 导出格式/质量/长边 | |
| `SettingsView.swift` | 语言、导出默认、胶片包、credits、重置收藏；版本 1.3 | |
| `ContentView.swift` | 根布局、主页/编辑切换、drop、toast、导出进度、启动错误、导出 sheet | |

### 4.6 Support

| 文件 | 责任 |
| --- | --- |
| `DesignSystem.swift` | `DS` 色彩/表面/文字/线/圆角/动画/token；`PressableStyle`、`HoverSurface`、`hex` 扩展、`clamped` |
| `Localization.swift` | `AppLanguage`、全局 `T("中文","English")` 内联双语文案；默认中文 |
| `WindowConfigurator.swift` | 隐藏标题栏、深色窗口、最小尺寸、关闭全局背景拖动、隐藏原系统 traffic lights |

## 5. 关键数据结构与不变量

### 5.1 `Photo`

```swift
struct Photo: Identifiable {
    let id: UUID
    let url: URL
    let name: String
    var metadata: PhotoMetadata
    var pixelSize: CGSize
    var edit: PhotoEdit
    var thumbnail: CGImage?       // 主页卡片
    var previewImage: CGImage?    // 编辑预览
    var previewLoaded: Bool
    var sourceStats: ImageStats
    var folder: URL?              // 非 nil = 来自文件夹扫描
    var isFavorite: Bool
    var colorLabel: PhotoColorLabel?
}
```

不变量：

- `folder == nil` 的照片才是“直接导入”，才会写进 `libraryPhotoPaths`。
- 文件夹照片只在用户打开文件夹时扫描并加入 `photos`；根主页会过滤掉它们。
- 收藏/颜色标签只存在 `LibraryMetaStore`，不应写进 `PhotoEdit`。
- `PhotoEdit` 的 `adjustments` 与 `curves` 才属于显影；`strength` 也属于显影。

### 5.2 照片库状态

```swift
screen: .library | .editor
folders: [LibraryFolder]        // 根主页的顶层文件夹
folderTrail: [URL]              // 面包屑；最后一个是当前文件夹
subfolderEntries: [LibraryFolder] // 当前文件夹的子文件夹
libraryDisplay: .grid | .list
libraryGrouping: .none | .film | .favorite | .color
libraryFilter: .all | .favorites | .edited | .red … .purple
librarySearch: String
```

计算属性链：

```text
loosePhotos / folderPhotos
  → libraryPhotos
  → filteredLibraryPhotos（筛选 + 搜索）
  → libraryGroups（按电影/收藏/颜色分组）
```

### 5.3 显影参数

`Adjustments` 是唯一可编码的滑块集合，包括：

- Light：exposure、contrast、highlights、shadows、whites、blacks
- Color：temperature、tint、vibrance、saturation、hueShift、colorDensity、
  skin/green/blueSaturation、highlightWarmth、shadowCoolness
- Detail：clarity、sharpen
- Film texture：grain、grainSize、grainChroma、grainShadow、halation、
  halationThreshold、halationRadius、halationWarmth、vignette、fade
- Transparency：tonalTransparency、colorTransparency

`PhotoEdit` 另外包含 `lookID`、`lutID`、`strength`、`lutStrength`、`curves`。

## 6. 渲染管线

### 6.1 预览路径

```text
CanvasMTKView.draw
 → Renderer.draw(in:)
 → 若 needsProcess：encodeProcess（source → processed）
 → 直方图 pass（可选）
 → display pass：processed 或 compare 分割原图
 → MTKView drawable
```

`Renderer.update(edit:look:)` 在编辑变化时：

1. 构建共享 `curveTexture`（`CurveTextureBuilder`）。
2. 选择 `filmTexture` / `neutralTexture` / `userLUTTexture`。
3. 设置 `needsProcess`，触发重绘。
4. 直方图请求由 `requestHistogram()` 驱动；结果回调 `onHistogram` 更新
   `HistogramData` 与 `ToneStats`。

### 6.2 `processImage` 顺序（`Shaders.metal`）

1. sRGB → linear
2. 白平衡（temperature/tint）
3. 曝光
4. 对数域 tone shaping（高光/阴影/白/黑、对比、pivot 18% 灰）
5. 饱和 + 自然饱和
6. Clarity / Sharpen（采样原图的高频）
7. Halation（bloom texture）
8. Film LUT：ACEScc → AP1 → neutral/film LUT mix；或导入 LUT（Rec.709）
9. 白点（`whites` 在 LUT 之后的显示空间）
10. 用户曲线（R/G/B + 明暗 A）
11. 色彩分级（HSV、肤色/绿色/蓝色、色相、密度、分离色调）
12. 明暗通透（直方图黑/白点 Levels）
13. 颜色通透（高光/阴影互补色 delta）
14. 褪色
15. 暗角
16. 颗粒（种子、尺寸、彩噪、阴影颗粒）
17. 抖动

### 6.3 导出路径

`Renderer.renderFull(_:edit:look:)`：

- 直接创建全分辨率 source/destination/bloom 纹理。
- **单独构建 `exportCurveTexture`**；不要复用预览的共享 `curveTexture`。
- `previewScale = 1`，颗粒尺寸按全分辨率计算。
- 导出通过 `CGImageDestination` 写 JPEG/PNG/TIFF/HEIC（`ExportSheet`）。

### 6.4 关键已知陷阱（改之前先读）

- `grainSeed` 必须是 **小数值**（当前 `abs(hash)%4096/100`）；直接用
  `hashValue` 会因浮点精度丢失让噪声变成平坦色偏。
- `whites` 在胶片 LUT **之后**的显示空间处理；放回 pre-LUT 会再次变得几乎无效。
- `renderFull` 必须独立生成曲线纹理；不要依赖 `update()` 的副作用。
- 导入 LUT 上限 50 个、最大 65³；超过会在导入时被拒绝。
- 分享/发布时不要删除上游 `SPEKTRAFILM_LICENSE.txt` 与 `LUT_NOTICE.md`。

## 7. 照片库 / 文件夹流程

### 7.1 根主页

- 显示 `folders`（顶层文件夹）+ `loosePhotos`（直接导入照片）。
- 文件夹卡片点击 `enterFolder` → 扫描并显示其直接子文件夹/照片。
- 顶部“显示 / 群组”菜单、筛选 chips、搜索都只作用于照片。
- 文件夹卡片可右键刷新、从库中移除（仅移除索引，不删磁盘）。
- 文件夹内部照片不能单独从库移除（因为重新打开文件夹会再次扫描到它们）。

### 7.2 文件夹

- 导入：`chooseFolder` → `importFolders` → `makeFolderRecord`（只读目录，
  统计直接图片与子文件夹，不复制）。
- 打开：`enterFolder(url)` → `folderTrail` 入栈 → `loadCurrentFolder`：
  - `scanFolder` 当前层；
  - `subfolderEntries` = 子文件夹；
  - 追加新照片到 `photos`（`folder = 当前目录`）；
  - 更新顶层文件夹 count/cover。
- 面包屑：`navigateToTrail`；上一级：`goUpFolder`；回根：`goToLibraryRoot`。
- 持久化：顶层文件夹路径写入 `libraryFolderPaths`；图片不写入
  `libraryPhotoPaths`（只在打开时扫描）。
- 收藏/颜色标签仍按文件路径持久化，文件夹移动后需要重新导入。

### 7.3 编辑集合

`collectionPhotos`：

- 当前照片有 `folder` → 该文件夹内的照片（用于 filmstrip / 上一张 / 下一张）。
- 当前照片是 loose → 根库的 loose 照片。

## 8. 窗口与交互

- `WindowConfigurator`：
  - `isMovableByWindowBackground = false`。
  - 隐藏系统红黄绿按钮；`TopBar` 的 `WindowTrafficLights` 在 46pt 状态栏内自绘并垂直居中。
- `TopBar` 的拖拽手势用 `NSEvent.mouseLocation` 跟踪屏幕坐标，保证窗口 1:1 跟手。
- `CanvasView`：
  - `CanvasMTKView.mouseDownCanMoveWindow = false`。
  - 鼠标拖拽 → `CanvasState.panBy` → 目标值 + 120Hz 阻尼跟随。
  - Ctrl / Cmd / Option + 滚轮 → `CanvasState.zoom(by:anchor:)`，
    `pow(|Δ|, 0.88)` + 指数映射。
  - 空格（本地 key monitor + keyDown）→ `canvas.reset()`。
  - 双击 → Fit / 100%。
- Compare：`CompareButton` 在画布左上；`CompareOverlay` 根据
  `canvas.imageRect(in:)` 计算分割线；display shader 按 `splitX` 采样原图。

## 9. 构建与资源

- 构建入口：`script/build_and_run.sh`
  - `--no-launch` 只构建/stage，不启动。
  - 默认 release；`--debug`；`--verify`/`--logs` 会启动应用，使用前确认用户允许。
- 本机没有 Xcode，只有 Command Line Tools；CLT 有两个 `SwiftBridging`
  modulemap，脚本通过 `.build/toolchain/include/swift` overlay 绕过。
- 直接 `swiftc` 编译，SwiftPM manifest 因同一 SDK 问题不可用。
- App 组装：`dist/OltraFlim.app`，ad-hoc codesign。
- 运行时编译 `Resources/Shaders.metal`；修改 shader 后无需重新编译 Swift，
  但必须确认运行时 `MTLLibrary` 编译成功。
- 资源：`catalog.json`、`LUTs/`、`Sample/`、`Shaders.metal`、`AppIcon.icns`。
- `dist/` 与 `.build/` 不进入 Git；发布包通过 GitHub Releases 分发。

## 10. 扩展入口

### 新增一个显影参数

1. `Models/Photo.swift`：`Adjustments` 加字段、默认值、`CodingKeys`、`init(from:)`、
   `activeCount`。
2. `Engine/Renderer.swift`：`RenderUniforms` 加字段并在 `init(edit:...)` 赋值。
3. `Resources/Shaders.metal`：`Uniforms` 加字段（顺序必须与 Swift struct 对齐）
   并在 `processImage` 使用。
4. `Views/InspectorView.swift`：添加 `SliderRow`、绑定、范围、本地化。
5. `Tools/RenderCheck.swift`：如需无头验证，添加参数入口。
6. 更新 `README.md` / `STATUS.md`；确认导出路径使用同一 uniform。

### 新增筛选/群组类别

1. `AppModel.swift` 的 `LibraryFilter` / `LibraryGrouping`。
2. `filteredLibraryPhotos`、`libraryGroups`、`libraryFilterCount`。
3. `HomeLibraryView.swift` 的 chips / menus / card metadata。
4. 保持 `LibraryMetaStore` 的字段可编码、旧数据可缺省。

### 新增面板/页面

- 显影相关 → `InspectorView`；曲线 → `CurveTabView`。
- 库管理相关 → `HomeLibraryView`（注意不要把可点击 Button 嵌套进外层
  Button；卡片/行使用 overlay 放操作按钮）。
- 主页 / 编辑切换 → `ContentView` + `AppModel.screen`。

## 11. 热点文件与并行冲突

以下文件经常被多个任务修改，**同一时间只允许一个 agent 主写**：

| 热点 | 原因 |
| --- | --- |
| `Stores/AppModel.swift` | 1880+ 行，库/文件夹/编辑/导出/LUT 全在这里 |
| `Engine/Renderer.swift` | uniform 顺序、预览/导出、CanvasState |
| `Resources/Shaders.metal` | 所有参数、LUT/曲线、颗粒、光晕 |
| `Views/HomeLibraryView.swift` | 主页、文件夹、卡片、筛选、菜单 |
| `Views/InspectorView.swift` | 三个 Tab、滑杆、底部操作栏 |
| `Views/TopBar.swift` | 窗口拖拽、traffic lights、返回、logo |

并行策略见 [`docs/MULTI_AGENT_COORDINATION.md`](docs/MULTI_AGENT_COORDINATION.md)。

## 12. 相关文档

- [`README.md`](README.md)：用户视角功能、快捷键、安装
- [`STATUS.md`](STATUS.md)：当前版本、验证状态、已知问题、路线图
- [`AGENTS.md`](AGENTS.md)：agent 硬规则、命令、交接
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：人类贡献流程
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)：环境、构建、打包、调试
- [`docs/MULTI_AGENT_COORDINATION.md`](docs/MULTI_AGENT_COORDINATION.md)：多 agent / 多机器协议
- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)：授权边界

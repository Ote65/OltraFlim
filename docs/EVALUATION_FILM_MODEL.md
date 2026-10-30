# 评估报告：OltraFlim（分支 agent/oltra/colour-pipeline） vs spektrafilm vs AlcedoStudio

> 评估对象：
> - OltraFlim 当前分支 HEAD `aa60aea`（本地分支 `agent/oltra/colour-pipeline`）
> - spektrafilm `main` @ `3bb2c2d`（Python 参考实现）
> - AlcedoStudio `main`（C++20 / Qt / Metal·CUDA·OpenCL 重写）
>
> 方法：源码逐阶段对照 + LUT 二进制逐点采样 + 无头 RenderCheck 渲染统计。
> 未做：启动 UI 对比、主观画质打分。

---

## 0. 结论摘要

1. **三者做“胶片显影”的编辑路径其实是同一类架构**：离线用 spektrafilm 的物理模型烘焙 LMT，运行时只做 `RAW → ACEScc → LMT → 显示变换`。Alcedo 和 OltraFlim 都是这套；spektrafilm 的 Python 是烘焙侧的参考实现。
2. **就“对真实胶片的接近程度”排序**：spektrafilm（物理参考）> Alcedo（同一物理模型 + 数据表颗粒，但施加在显示域）> OltraFlim（同一 LMT，颗粒为程序噪声）。
3. **OltraFlim 的画面颜色并不“偏”**：内置 33³ 包与直接导入 65³ 源 LMT 的灰阶差 <2%，说明显影色彩链路和 Alcedo 同源。真正的差距在 **RAW 前端**与 **颗粒/光晕的物理性**。
4. 分支把 RAW 输入改成了场景线性（可超白）+ 自动曝光，解决了 1.4 之前“LUT 只用 55% 输入域、白点只有 0.84”的结构性问题；但 RAW 的去马赛克、高光重建、相机矩阵仍由 `CIRAWFilter` 黑盒决定。

---

## 1. RAW 解析

| 阶段 | OltraFlim（分支） | spektrafilm | AlcedoStudio |
| --- | --- | --- | --- |
| 解码库 | `CIRAWFilter`（Apple RAW，闭源） | LibRaw（rawpy） | LibRaw + 自有调度 |
| 输出 | 场景线性 Rec.709，`rgba16Float`，可 >1.0 | 16-bit 线性 ACES2065-1，`no_auto_bright`、`gamma=(1,1)` | 线性相机 RGB → 相机矩阵 → AP1 → ACES 参考色域压缩 → ACEScc |
| 去马赛克 | Apple 内部算法（不可选） | LibRaw 默认 | RCD + **DemosaicNet**（CPU/OpenCL/Metal/CUDA） |
| 高光重建 | Apple 内部（不可控） | 无（保留原始超白） | 对立色重建（darktable/RawTherapee 思路） |
| 相机矩阵 | Apple 相机配置文件（黑盒） | LibRaw 内建 | DNG 配置库（`cam_xyz`、`color_matrix_1/2`、AsShotNeutral） |
| 镜头校正 | `CIRAWFilter` 支持时开启（测试 ARW 不支持） | 无（靠外部） | Lensfun |
| 自动曝光 | 中心加权 → 18% 灰（可关） | 中心加权 → 0.184 | GUI 可调/默认自动 |
| 精度 | 半浮点、8-bit→16-bit 仅保留 8-bit 信息（非 RAW 时） | 16-bit 线性 | 32-bit 浮点全链路 |

**判断**：RAW 前端是 OltraFlim 与另外两者差距最大的一环。分支修好了“线性 + 超白 + 曝光基准”，但没有修“去马赛克/高光重建/相机矩阵”——这三项都在 `CIRAWFilter` 内部，Apple 不暴露。Alcedo 在这一环最完整；spektrafilm 次之（LibRaw 默认去马赛克，但保留线性超白，适合重采样）。

代码位置：`Sources/OltraFlim/Engine/ImageLoader.swift` 的 `rawImage`（第 187 行起）、`autoExposureEV`（第 227 行起）；`Renderer.makeLinearTexture`（`Renderer.swift` 第 502 行起）。

---

## 2. 胶片显影

### 2.1 离线物理模型（烘焙侧）

spektrafilm 是唯一的“从零物理”实现，五个阶段都在密度/光谱域：

1. `filming.expose`：RGB → 光谱响应（hanatos2025 / mallett2019）、扩散、镜头模糊、光晕 boost、log10
2. `filming.develop`：负片密度曲线插值 + **方向成色剂** + 颗粒（施加在 CMY 密度上）
3. `printing.expose`：负片密度 → 光谱密度 → 二向色滤光/预闪光 → 相纸曝光
4. `printing.develop`：相纸密度曲线
5. `scanning.scan`：密度 → XYZ（CMF）→ 输出色域压缩

Alcedo 把这套物理模型离线烘焙成 113 个 **ACEScc→ACEScc LMT**（就是 `Alcedo_LUT_导出` 里的 `.cube`），运行时不再跑光谱；OltraFlim 的 `Tools/build_luts.py` 把这些 LMT 进一步烘焙成 33³ `ACEScc→显示` 纹理。因此三者的“显影色彩”同源。

### 2.2 运行时路径

| 阶段 | OltraFlim | Alcedo | spektrafilm（GUI） |
| --- | --- | --- | --- |
| 进入 LMT 的域 | 线性 Rec.709 → AP1 → ACEScc | 相机 → AP1 → ACEScc（含色域压缩） | 线性 ACES → 光谱 |
| 胶片模型 | 33³ 表化 LMT | 65³ LMT + 逐像素 ACES 2.0/OpenDRT | 逐像素光谱 |
| 显示变换 | 33³ `neutral-0` 表（ACES 2.0 SDR 烘焙） | 逐像素 ACES 2.0 正/逆 DRT，另可选 OpenDRT、局部色调映射 | 无（输出线性，交给显示端） |
| 曝光/默认 grade | 自动曝光基线；用户 grade 默认 0 | 自动曝光 + Alcedo 默认 grade（+1.5EV/对比 15/饱和 1.3，随 LUT 头声明） | 曝光补偿、印片平衡 |

**数值证据**（Sony DSC03406.ARW，4240×2832，全部调整=0）：

```text
内置 33³ spk-portra-400            p05 0.043  p50 0.649  p95 0.939  max 0.983
直接导入 65³ 同一 LMT（+1.5EV）     p05 0.038  p50 0.664  p95 0.946  max 0.985
```

灰阶差 <2%，说明“同一 LMT + 表化显示变换”与“65³ 直采”在观感上等价。剩余差异主要来自 **33³ 重采样**和 **per-pixel DRT**。

**判断**：显影色彩上，OltraFlim ≈ Alcedo（同源 LMT）；与 spektrafilm 的差距在于没有逐像素光谱、没有逐像素 DRT、没有印片平衡等可调物理项。

---

## 3. 胶片颗粒

### 3.1 三种实现的结构差异

| | OltraFlim | Alcedo | spektrafilm |
| --- | --- | --- | --- |
| 域 | **显示编码后**（`enc`） | **显示编码后**（ODT 之后） | **负片 CMY 密度**（显影阶段，印片之前） |
| 随机模型 | 平滑 value-noise 多八度 + clump 场 | **布尔模型**：每 tap 一次 `draw < u ? 1 : 0`，再做高斯窗滤波（IPOL 2017） | **Poisson-binomial 粒子模型**：每像素粒子数 `pixel_area / particle_area`，显影概率 `density/density_max` |
| 色调依赖 | 抛物线 `4l(1-l)` + 高光/暗部掩膜 | 数据表 σD（R/G/B 各 11 点，密度→RMS 粒度） | `density_max` 来自胶片密度曲线，逐通道/逐子层 |
| 彩色 | 固定比例的三通道噪声 | 密度误差去相关，色度随高光收敛 | 3 子层（粗/中/细）× 3 通道，`particle_scale_layers` |
| 团簇 | 两个低频噪声调制 | 无显式团簇，靠布尔叠加+7 tap 高斯 | lognormal 微结构 + dye-cloud 模糊（µm 单位） |
| 分辨率 | `cells = 900/(1+size*9)`，按短边固定 | 参考坐标映射（ROI/预览一致） | 以 µm 计算，与像素尺寸绑定 |

代码：

- OltraFlim：`Resources/Shaders.metal` 第 531–580 行
- Alcedo：`edit/runtime/metal/shader/drt_neighbor.metal` 的 `DrtFilmSample/DrtFilmHorizontal/DrtFilmApply`，以及 `edit/runtime/cuda/cuda_film_grain_math.cuh`
- spektrafilm：`src/spektrafilm/model/grain.py` 的 `layer_particle_model` / `apply_grain_to_density_layers` / `apply_grain`

### 3.2 哪个更接近真实胶片

**spektrafilm 最接近**，原因不是“算法更复杂”，而是三件物理事实：

1. **颗粒形成在密度域**。银盐颗粒是显影后的密度起伏，之后还要经过印片曲线。把颗粒加在显示域，等于跳过了印片 gamma 对颗粒的放大/压缩，幅度和色调关系都会偏。
2. **粒子统计是离散的**。`Poisson(λ)` 决定每像素有多少颗粒，`Binomial(n, p)` 决定哪些被显影；颗粒是 0/1 事件，不是连续噪声。这正是 IPOL 2017 的核心。
3. **粒度有实测依据**。`density_max` 来自胶片 datasheet 的密度曲线，`particle_area_um2`（默认 0.2 µm²）、`particle_scale=(1.6,1.6,3.2)`、子层 `(2.0,1.0,0.5)` 都按真实乳剂层设置；还有 30 nm 的微结构团簇和 1 µm 的染料云模糊。

**Alcedo 次之**：它确实用了 IPOL 2017 的布尔模型（`FilmGrainSample` 是一次 Bernoulli，高斯窗是 Monte Carlo 积分），又用数据表 σD 补回了“密度→粒度”的关系，视觉上可信。但它在 **ODT 之后**施加，输入是显示值 `u` 而不是密度，所以：
- 颗粒幅度不随印片 gamma 变化；
- 高光处用了 `0.72–0.96` 的软阈值人为压暗/收敛；
- 色度去相关是固定的 `0.68→0.18`，不是逐层物理。

**OltraFlim 最不物理**：它是**平滑噪声**，没有离散粒子；幅度靠 `4l(1-l)` 抛物线和高光掩膜，没有 datasheet 依据；彩色颗粒是固定比例的三通道噪声。优点是便宜、分辨率无关、不会闪；缺点是高光/阴影的颗粒形态会偏“电子噪点”。

实测 OltraFlim 的颗粒幅度（4 段灰阶，grain=100，σ 以 0–255 计）：

```text
输出 38  (0.15) → std 4.31
输出 142 (0.56) → std 6.40
输出 223 (0.87) → std 2.91
输出 245 (0.96) → std 1.41
```

峰值在中间调、高光收敛，形状方向是对的；但它来自抛物线而非密度曲线，所以峰位和两侧斜率都不随胶片型号变化。

---

## 4. 光晕 / 其他

- spektrafilm：`boost_highlights` → 能量守恒的 Gaussian 核 + 指数尾散射 → 回反射光晕（N 个 sqrt(k) 间隔的高斯），全部在**线性乳剂域**。
- Alcedo：显示域的指数窗（`exp(-tap/sigma)`）+ `redshift[3]` 逐通道增益，在 ODT 之后；另有 `DrtHalation` 参数与 sigma。
- OltraFlim：半分辨率阈值 bloom，单一模糊 + 暖色 tint，在线性域加回（`Shaders.metal` 第 376–384 行）。

结论同上：spektrafilm 物理，Alcedo 视觉近似（位置在显示域），OltraFlim 最简化。

---

## 5. 总评分（5 分制，主观权重：RAW 35% / 显影 35% / 颗粒 30%）

| 维度 | OltraFlim（分支） | spektrafilm | Alcedo |
| --- | --- | --- | --- |
| RAW 解析与色彩管理 | **2.5** | 4.0 | **5.0** |
| 显影色彩（LMT 同源） | **4.0** | **5.0** | 4.5 |
| 颗粒物理性 | **2.0** | **5.0** | 3.5 |
| 光晕物理性 | 2.5 | 5.0 | 3.5 |
| 实时性 / 工程 | 5.0 | 1.5 | 5.0 |
| **接近真实胶片（加权）** | **2.9** | **4.6** | **4.2** |

一句话：**OltraFlim 的“胶片颜色”已经很接近 Alcedo / spektrafilm，但“胶片物质感”（颗粒、光晕）和“RAW 前端”仍差一个代际。**

---

## 6. 改进优先级（从物理性收益排序）

1. **颗粒搬到密度域或至少布尔化**（P0）
   - 最小改动：把 `value_noise` 换成 per-tap Bernoulli（`draw < u`）+ 高斯窗，幅度用一条按胶片型号的 σD 曲线（可先沿用 Alcedo 的 11 点表）。
   - 完整改动：在 LMT 之前以 CMY 密度做 `Poisson-binomial`，再经 LMT/显示变换；需要把 LMT 拆成“film LUT + print LUT”两段（65³ 源 cube 支持 3-LUT/4-LUT 拓扑）。
2. **RAW 前端接 LibRaw**（P0，需改构建链）：换取 RCD/DemosaicNet、DNG 相机矩阵、对立色高光重建；否则只能停留在 `CIRAWFilter` 黑盒。
3. **逐像素 ACES 2.0 DRT**（P1）：把 `neutral-0` 表换成 aces-core 的解析式实现，消除 33³ 采样误差。
4. **光谱光晕**（P2）：按 µm 的核 + 指数尾 + 逐通道回反射，替换当前阈值 bloom。
5. **33³ → 45³**（P2）：仅提升 LMT 重采样精度，收益小于前三项。

---

## 7. 复现

```bash
# 分支构建
./script/build_and_run.sh --no-launch

# 无头渲染（内置 spc LUT）
./.build/render-check "/path/to/photo.ARW" /tmp/out.png \
  spc-kodak-portra-400-kodak-portra-endura-paper-aces2-sdr

# LMT 直采对照
/tmp/lutprobe "/path/to/photo.ARW" \
  "/path/to/kodak_portra_400__kodak_portra_endura.cube"
```

上游对照版本：
- spektrafilm `3bb2c2d2801ff68b92019cf1dbcbb133d60832bc`
- AlcedoStudio `main`（`src/edit/runtime/metal/shader/drt_neighbor.metal`、`src/edit/runtime/cuda/cuda_film_grain_math.cuh`）

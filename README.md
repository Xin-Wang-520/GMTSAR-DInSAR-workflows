# GMTSAR DInSAR Processing Workflows

[中文说明](#中文说明) | [English Documentation](#english-documentation)

当前仓库包含 LT-1 的两景 DInSAR 流程，后续可按卫星添加新的处理目录。

```text
GMTSAR-DInSAR-workflows/
├── README.md
├── LT1/                 # 当前 LT-1 两景 DInSAR 脚本
├── Sentinel1/           # 后续可添加
└── GF3/                 # 后续可添加
```

当前 LT-1 流程请进入 `LT1/` 目录后，在独立的升轨或降轨数据目录中运行。

---

## 中文说明

本项目是一套基于
[GMTSAR](https://github.com/gmtsar/gmtsar) 的 LT-1 双景 Stripmap SLC DInSAR
命令行处理流程，包括数据解压、SLC 生成、轨道处理、数据对检查、DEM
准备、先裁剪后配准、干涉与滤波、掩膜生成、SNAPHU 解缠、地理编码、LOS
形变转换和可选的长波趋势去除。

本流程用于常规两景 DInSAR，不是 SBAS。脚本自动按日期排序，以较早影像为
主影像。升轨和降轨数据必须放在各自独立的轨道目录中处理。

### 作者

- Xin Wang
- 中国科学技术大学（USTC），中国合肥
- 最后更新：2026 年 9 月 14 日

### 主要特点

- 使用旧版 LT-1 目录布局：`data/zip/`、`data/orbit/` 和解压后的
  `data/LT1*/`。
- 要求每个轨道目录中恰好有两景数据，并自动按日期排序。
- 支持预处理程序可识别的 LT1A/LT1B L1A 和 S2A 格式产品名。
- `make_slc_lt1` 默认使用 `SLC_factor=10`，两景数据默认使用两个任务。
- 有精密轨道时优先使用精密轨道；没有时修复元数据/粗轨道 LED。
- 通过逐字节对比修复前后 LED，准确报告轨道是否真正发生变化。
- 先裁剪两景 SLC，再进行配准；设定范围超出某景数据时自动取公共有效范围。
- 支持全幅处理和按经纬度指定研究区。
- 多数脚本先预览检查，加参数 `1` 才正式执行。
- 解缠可选 `snaphu_interp.csh` 或标准 `snaphu.csh`。
- 已存在的地理编码缠绕相位、相关性和幅度结果不会被重复生成。

### 运行环境

本流程面向 Linux GMTSAR 处理环境，需要：

- Bash 和常用 Unix 命令行工具
- Python 3
- 包含 LT-1 支持和 `make_slc_lt1` 的 GMTSAR
- GMT 6
- SNAPHU
- GNU Parallel（并行解压时使用）

`SAT_baseline`、`cut_slc`、`xcorr`、`resamp`、`batch_processing.csh`、
`proj_ra2ll.csh`、`snaphu.csh` 和 `snaphu_interp.csh` 等 GMTSAR 命令需要
可以通过 `PATH` 直接调用。

### 目录结构

在一个独立的升轨或降轨目录中运行脚本：

```text
Track/
├── data/
│   ├── zip/                         # LT-1 原始 .tar.gz 数据
│   ├── orbit/                       # 可选的精密轨道 TXT 文件
│   └── LT1A_MONO_.../               # Run 1.1 解压后的产品
├── raw/                              # 原始尺寸 SLC/PRM/LED
├── SLC/                              # 裁剪并配准后的 SLC
├── topo/                             # dem.grd、topo_ra.grd 和 trans.dat
├── intf_all/
│   └── REFERENCE_ID_REPEAT_ID/       # 单个干涉对结果
├── config.LT1.txt
├── data.list
├── intf.list
└── run*.sh / run*.py
```

脚本只从 `data/zip/` 读取压缩包，只从 `data/orbit/` 读取精密轨道。

### 预览和正式运行

多数 Shell 脚本遵循以下规则：

```bash
./script.sh       # 预览或检查，不修改处理结果
./script.sh 1     # 正式执行
```

建议先阅读预览输出，确认无误后再加 `1`。脚本成功完成后，终端最后一行会
提示下一个建议运行的命令。

### Run 1：LT-1 SLC 数据解压和准备

#### 1.1 解压产品

将两个压缩包放入 `data/zip/`：

```bash
./run1.1_unzip_LT1.sh
./run1.1_unzip_LT1.sh 1
```

默认使用两个解压任务，需要时可以显式指定：

```bash
./run1.1_unzip_LT1.sh 1 --jobs 2
```

#### 1.2 准备 raw 输入、SLC 和轨道文件

```bash
./run1.2.1_prepare_raw_LT1.sh
./run1.2.1_prepare_raw_LT1.sh 1
./run1.2.2_make_slc_LT1.sh
./run1.2.2_make_slc_LT1.sh 1
./run1.2.3_apply_precise_orbit_LT1.sh
./run1.2.3_apply_precise_orbit_LT1.sh 1
```

Run 1.2.1 生成 `data.list` 和 `config.LT1.txt`。Run 1.2.2 调用 `make_slc_lt1`，
生成 `raw/LT1_YYYYMMDD.{SLC,PRM,LED}`。Run 1.2.3 优先匹配精密轨道；无精密
轨道时规整元数据 LED，并报告修复前后文件是否真正不同。

公共采样为可选步骤。完成轨道处理后先预览，只在 PRF 或距离向采样率不同时执行：

```bash
./run1.2.4_common_sampling_LT1.sh
./run1.2.4_common_sampling_LT1.sh 1
```

#### 1.3 检查数据对兼容性和基线

```bash
./run1.3_check_pair_LT1.sh
```

该步骤只读检查波长、轨道方向、视向、PRF、距离向采样率和数据尺寸，并运行
`SAT_baseline`，生成 `baseline_summary.tsv` 和 `baseline_plot.png`。终端中重复的
`hermite interpolation not in center interval` 会被合并显示，完整输出保留在日志中。
该信息表示某些插值时刻超出 LED 中心区间，应结合基线结果和轨道时间覆盖判断。

### Run 2：DEM 和雷达裁剪范围

#### 2.1 准备地理坐标 DEM

```bash
./run2.1_prepare_topo_DEM_LT1.sh
./run2.1_prepare_topo_DEM_LT1.sh 1 --margin-deg 0.30 --resolution 1
```

#### 2.2 将地理研究区转换到雷达坐标

推荐使用左上角和右下角经纬度：

```bash
./run2.2_geo_to_radar_region_LT1.sh \
  --upper-left 85.3042 28.3550 \
  --lower-right 85.5949 28.1879

./run2.2_geo_to_radar_region_LT1.sh 1 \
  --upper-left 85.3042 28.3550 \
  --lower-right 85.5949 28.1879
```

不规则研究区可以通过文件输入，每行为一组 `longitude latitude`：

```bash
./run2.2_geo_to_radar_region_LT1.sh --roi roi.lonlat
```

如果不裁剪，保留完整雷达影像：

```bash
./run2.2_geo_to_radar_region_LT1.sh --no-crop
./run2.2_geo_to_radar_region_LT1.sh 1 --no-crop
```

#### 2.3 更新 GMTSAR 配置

```bash
./run2.3_update_config_LT1.sh
./run2.3_update_config_LT1.sh 1
```

该步骤将 Run 2.2 的 `region_cut` 写入 `config.LT1.txt`，并准备配准和干涉处理参数。

### Run 3：两景 DInSAR 处理

#### 3.1 先裁剪后配准

```bash
./run3.1_cut_align_LT1.sh
./run3.1_cut_align_LT1.sh 1
```

两景 raw SLC 在配准前先裁剪。如果 `region_cut` 超出任意一景 SLC，脚本会自动使用
两景数据的公共有效雷达范围。配准依次使用 `SAT_baseline`、`xcorr`、`fitoffset.csh`
和 `resamp`。

#### 3.2 生成雷达坐标 DEM

```bash
./run3.2_dem_ra_LT1.sh
./run3.2_dem_ra_LT1.sh 1
```

该步骤运行 GMTSAR 第 3 阶段 DEM 反地理编码，生成 `topo/topo_ra.grd` 和
`topo/trans.dat`。

#### 3.3 生成并滤波干涉图

```bash
./run3.3_intf_filter_LT1.sh
./run3.3_intf_filter_LT1.sh 1
```

脚本调用：

```bash
batch_processing.csh LT1 LT1_YYYYMMDD intf.list 4 config.LT1.txt
```

GMTSAR `p2p_processing.csh` 把 `proc_stage` 解释为起始阶段，因此从第 4 阶段开始后还可能
继续检查第 5、6 阶段。实际是否执行由 `threshold_snaphu`、`threshold_geocode` 和
`skip_stage` 决定。已生成的地理编码缠绕相位、相关性和幅度结果会被保留。

#### 3.4 生成雷达坐标陆地掩膜

```bash
./run3.4_make_landmask_ra_LT1.sh
./run3.4_make_landmask_ra_LT1.sh 1
```

陆地掩膜会被重采样到与 `phasefilt.grd` 完全一致，并保存在干涉对目录：

```text
intf_all/REFERENCE_ID_REPEAT_ID/landmask_ra.grd
intf_all/REFERENCE_ID_REPEAT_ID/landmask_ra.pdf
```

#### 3.5 可选：选择小范围解缠区域

全幅解缠时跳过该步骤。如果只解缠小范围：

```bash
./run3.5_preview_unwrap_region_LT1.py \
  --upper-left 85.3042 28.3550 \
  --lower-right 85.5949 28.1879
```

后续命令只有加入 `--use-preview-region` 时才使用该范围。

#### 3.6 预览解缠前掩膜和缠绕相位

```bash
./run3.6_preview_unwrap_LT1.sh
./run3.6_preview_unwrap_LT1.sh 1 0.1
```

如需使用 Run 3.5 的小范围：

```bash
./run3.6_preview_unwrap_LT1.sh 1 0.1 --use-preview-region
```

默认相关性阈值为 `0.1`。组合掩膜为：

```text
(corr >= threshold) * mask * optional mask_def * landmask_ra
```

该步骤在 `run3.6_unwrap_preview/` 生成 `mask_presnaphu.png` 和
`phase_presnaphu.png`，然后删除临时 GRD。Run 3.6 不运行 `nearest_grid` 或 SNAPHU。

#### 3.7 相位解缠

显式选择一种方法；不给出方法时在终端中二选一：

```bash
# 在 SNAPHU 前对掩膜/低相关区域进行插值
./run3.7_unwrap_LT1.sh --snaphu_interp 0.1
./run3.7_unwrap_LT1.sh 1 --snaphu_interp 0.1

# 标准 SNAPHU，不运行 nearest_grid 插值
./run3.7_unwrap_LT1.sh --snaphu 0.1
./run3.7_unwrap_LT1.sh 1 --snaphu 0.1
```

如需使用 Run 3.5 的范围，加入 `--use-preview-region`。Run 3.7 生成
`intf_all/REFERENCE_ID_REPEAT_ID/unwrap.grd`。

#### 3.8 地理编码解缠相位并生成 LOS 形变

```bash
./run3.8_geocode_unwrap_LOS_LT1.sh
./run3.8_geocode_unwrap_LOS_LT1.sh 1 0.1
```

只生成尚不存在的结果，已存在的文件显示为 `[REUSE]` 并保持不变。LOS 转换方法与
`geocode.csh` 一致：

```text
LOS(mm) = unwrap(rad) * radar_wavelength(m) * -79.58
```

按 GMTSAR 约定，LOS 正值表示斜距减小，即地表朝卫星方向运动。主要输出：

```text
unwrap_mask.grd
unwrap_mask_ll.grd
unwrap_mask_ll.png
los.grd
los_ll.grd
los.png
los_ll.png
```

地理编码采样间距约为 `filter_wavelength` 的四分之一；当该参数为 `60` 时，采样间距约为
15 m。

#### 3.9 可选：去除 LOS 长波趋势

```bash
./run3.9_detrend_LOS_LT1.sh
./run3.9_detrend_LOS_LT1.sh 1
```

方法沿用早期 LT-1 处理流程：

```bash
gmt grdtrend los_ll.grd -N6r \
  -Tlos_ll_trend.grd \
  -Dlos_ll_detrend.grd
```

`-N6r` 拟合稳健六参数二次曲面。`los_ll_trend.grd` 仅为中间文件，绘图后删除。
保留的结果均放在干涉对目录中：

```text
los_ll_detrend.grd
los_ll_detrend.png
los_ll_detrend_comparison.png
```

多项式去趋势可以消除可能的电离层或残余轨道长波斜坡，但它不是唯一的电离层校正。
必须检查三联对比图，因为真实的宽范围形变也可能被去除。

### 主要输出

| 步骤 | 主要结果 |
|---|---|
| Run 1.2 | `raw/LT1_YYYYMMDD.{SLC,PRM,LED}` |
| Run 1.3 | `baseline_plot.png`、`baseline_summary.tsv` |
| Run 2.1 | `topo/dem.grd` |
| Run 3.1 | 裁剪并配准后的 `SLC/` |
| Run 3.2 | `topo/topo_ra.grd`、`topo/trans.dat` |
| Run 3.3 | `phasefilt.grd`、`corr.grd` |
| Run 3.4 | 干涉对目录内的 `landmask_ra.grd` |
| Run 3.7 | `unwrap.grd` |
| Run 3.8 | `unwrap_mask_ll.grd`、`los_ll.grd` |
| Run 3.9 | `los_ll_detrend.grd` 和对比图 |

### 可选的幅度变化工具

- `run_amp_geocode_change_LT1.sh` 对已有的 `amp1.grd` 和 `amp2.grd` 进行地理编码，
  并计算后时相/前时相功率变化。
- `LT1_existing_amp_geocode/` 包含相同流程和 Google Earth 导出工具。
- `amplitude_full_frame/` 包含全幅配准和强度变化脚本。

使用这些可选工具前，请阅读对应目录中的 README。

### 注意事项

- 不要在同一个轨道目录中混合升轨和降轨数据。
- 本流程需要恰好两景相容的 LT-1 数据。
- 优先使用精密轨道；元数据/粗轨道修复仅是后备方案。
- 参数检查通过不代表干涉对一定具有良好相关性。
- LT-1 网格较大，`grdmath`、`grdimage` 和 `proj_ra2ll.csh` 可能耗时且占用较多磁盘。
  需要时先用 Run 3.5 选择小区域测试。
- `SLC_factor=10` 是 LT-1 SLC 生成时的整数缩放因子，不是多视或空间降采样因子。
- 解释滑坡形变前，应检查相关性、掩膜、解缠相位、LOS 和去趋势结果图。

---

## English Documentation

This repository currently provides the LT-1 workflow under `LT1/`. Enter that
directory before running the scripts from an independent ascending or
descending track directory. Additional satellite-specific workflows can be
added as sibling directories such as `Sentinel1/` and `GF3/`.

A command-line workflow for processing one LT-1 Stripmap SLC pair with
[GMTSAR](https://github.com/gmtsar/gmtsar). It covers archive extraction, SLC
conversion, orbit handling, pair validation, DEM preparation, crop-first
coregistration, interferogram formation, filtering, masking, SNAPHU phase
unwrapping, geocoding, LOS displacement conversion, and optional removal of a
long-wavelength trend.

This repository is designed for conventional two-scene DInSAR, not SBAS. The
earlier acquisition is selected automatically as the reference/master. Process
ascending and descending tracks independently by placing the scripts in each
track directory.

## Author

- Xin Wang
- University of Science and Technology of China (USTC), Hefei, China
- Last updated: September 14, 2026

## Main features

- Uses the legacy LT-1 layout: `data/zip/`, `data/orbit/`, and extracted
  `data/LT1*/` products.
- Requires exactly two acquisitions and sorts them chronologically.
- Supports LT1A/LT1B L1A and S2A-style product names handled by the
  preprocessing program.
- Uses two scene jobs by default and `SLC_factor=10` with `make_slc_lt1`.
- Uses precise orbits when available and repairs metadata/coarse LED files when
  precise orbits are unavailable.
- Compares original and repaired LED contents instead of assuming every
  attempted repair changed the orbit.
- Crops both SLCs before coregistration and clamps an oversized crop to their
  common valid coverage.
- Supports full-frame or geographic-ROI processing.
- Provides read-only preview/check modes before most formal steps.
- Supports both `snaphu_interp.csh` and standard `snaphu.csh`.
- Preserves geocoded wrapped-phase, correlation, and amplitude products that
  already exist.

## Requirements

The workflow is intended for a Linux GMTSAR processing environment. Required
software includes:

- Bash and standard Unix command-line utilities
- Python 3
- GMTSAR with LT-1 support, including `make_slc_lt1`
- GMT 6
- SNAPHU
- GNU Parallel for parallel archive extraction, when used

GMTSAR commands such as `SAT_baseline`, `cut_slc`, `xcorr`, `resamp`,
`batch_processing.csh`, `proj_ra2ll.csh`, `snaphu.csh`, and
`snaphu_interp.csh` must be available through `PATH`.

## Directory layout

Run the scripts from one independent ascending or descending track directory:

```text
Track/
├── data/
│   ├── zip/                         # Original LT-1 .tar.gz products
│   ├── orbit/                       # Optional precise-orbit TXT files
│   └── LT1A_MONO_.../               # Products extracted by Run 1.1
├── raw/                              # Original-size SLC/PRM/LED products
├── SLC/                              # Cropped and aligned SLC stack
├── topo/                             # dem.grd, topo_ra.grd and trans.dat
├── intf_all/
│   └── REFERENCE_ID_REPEAT_ID/       # The single interferogram
├── config.LT1.txt
├── data.list
├── intf.list
└── run*.sh / run*.py
```

The scripts intentionally read archives only from `data/zip/` and precise
orbits only from `data/orbit/`.

## Processing convention

For most shell scripts:

```bash
./script.sh       # preview or check
./script.sh 1     # formal execution
```

Read the terminal summary before adding `1`. Successful scripts print the next
recommended command on their final line.

## Run 1: extract and prepare LT-1 SLC data

### 1.1 Extract the products

Place the two archives in `data/zip/`, then run:

```bash
./run1.1_unzip_LT1.sh
./run1.1_unzip_LT1.sh 1
```

The default number of extraction jobs is two. Override it only when needed:

```bash
./run1.1_unzip_LT1.sh 1 --jobs 2
```

### 1.2 Prepare raw inputs, SLCs, and orbit files

```bash
./run1.2.1_prepare_raw_LT1.sh
./run1.2.1_prepare_raw_LT1.sh 1

./run1.2.2_make_slc_LT1.sh
./run1.2.2_make_slc_LT1.sh 1

./run1.2.3_apply_precise_orbit_LT1.sh
./run1.2.3_apply_precise_orbit_LT1.sh 1
```

Run 1.2.1 creates `data.list` and `config.LT1.txt`. Run 1.2.2 calls
`make_slc_lt1` and creates `raw/LT1_YYYYMMDD.{SLC,PRM,LED}`. Run 1.2.3 uses a
matching precise orbit when available; otherwise it regularizes the metadata
LED and reports whether its bytes actually changed.

Common sampling is optional. Preview it after orbit processing and execute it
only if PRF or range sampling differs:

```bash
./run1.2.4_common_sampling_LT1.sh
./run1.2.4_common_sampling_LT1.sh 1
```

### 1.3 Check pair compatibility and baseline

```bash
./run1.3_check_pair_LT1.sh
```

This read-only step checks wavelength, orbit direction, look direction, PRF,
range sampling, and dimensions. It runs `SAT_baseline` and creates:

```text
baseline_summary.tsv
baseline_plot.png
```

Repeated `hermite interpolation not in center interval` messages are condensed
in the terminal while the complete output remains available in the log. These
messages indicate that some requested interpolation epochs are outside the
central LED interval; inspect the baseline result and orbit coverage rather
than treating message count alone as a pass/fail criterion.

## Run 2: DEM and radar crop selection

### 2.1 Prepare the geographic DEM

```bash
./run2.1_prepare_topo_DEM_LT1.sh
./run2.1_prepare_topo_DEM_LT1.sh 1 --margin-deg 0.30 --resolution 1
```

### 2.2 Convert a geographic ROI to radar coordinates

The recommended rectangular form is:

```bash
./run2.2_geo_to_radar_region_LT1.sh \
  --upper-left 85.3042 28.3550 \
  --lower-right 85.5949 28.1879

./run2.2_geo_to_radar_region_LT1.sh 1 \
  --upper-left 85.3042 28.3550 \
  --lower-right 85.5949 28.1879
```

An irregular ROI file may contain one `longitude latitude` pair per line:

```bash
./run2.2_geo_to_radar_region_LT1.sh --roi roi.lonlat
```

Keep the complete radar image when no crop is wanted:

```bash
./run2.2_geo_to_radar_region_LT1.sh --no-crop
./run2.2_geo_to_radar_region_LT1.sh 1 --no-crop
```

### 2.3 Update the GMTSAR configuration

```bash
./run2.3_update_config_LT1.sh
./run2.3_update_config_LT1.sh 1
```

This transfers the Run 2.2 `region_cut` into `config.LT1.txt` and prepares the
alignment/interferometry parameters.

## Run 3: two-scene DInSAR

### 3.1 Crop first and coregister

```bash
./run3.1_cut_align_LT1.sh
./run3.1_cut_align_LT1.sh 1
```

Both raw SLCs are cropped before alignment. If the requested `region_cut`
exceeds either SLC, the script uses their common valid radar coverage. The
coregistration sequence is `SAT_baseline`, `xcorr`, `fitoffset.csh`, and
`resamp`.

### 3.2 Generate the radar-coordinate DEM

```bash
./run3.2_dem_ra_LT1.sh
./run3.2_dem_ra_LT1.sh 1
```

This runs the GMTSAR step-3 DEM back-geocoding workflow and creates
`topo/topo_ra.grd` and `topo/trans.dat`.

### 3.3 Form and filter the interferogram

```bash
./run3.3_intf_filter_LT1.sh
./run3.3_intf_filter_LT1.sh 1
```

The script calls:

```bash
batch_processing.csh LT1 LT1_YYYYMMDD intf.list 4 config.LT1.txt
```

GMTSAR `p2p_processing.csh` treats `proc_stage` as the starting stage. A stage-4
run may therefore continue to check stages 5 and 6. Whether those stages do
work depends on `threshold_snaphu`, `threshold_geocode`, and `skip_stage` in the
configuration. Existing geocoded wrapped-phase, correlation, or amplitude
products from this run are retained; Run 3.8 does not regenerate them.

### 3.4 Generate the radar-coordinate land mask

```bash
./run3.4_make_landmask_ra_LT1.sh
./run3.4_make_landmask_ra_LT1.sh 1
```

The land mask is resampled to match `phasefilt.grd` exactly and is saved inside
the single pair directory:

```text
intf_all/REFERENCE_ID_REPEAT_ID/landmask_ra.grd
intf_all/REFERENCE_ID_REPEAT_ID/landmask_ra.pdf
```

### 3.5 Optionally select a small unwrapping region

Skip this step for full-interferogram unwrapping. For a smaller region:

```bash
./run3.5_preview_unwrap_region_LT1.py \
  --upper-left 85.3042 28.3550 \
  --lower-right 85.5949 28.1879
```

Later commands use this selection only when `--use-preview-region` is supplied.

### 3.6 Preview the pre-SNAPHU mask and wrapped phase

```bash
./run3.6_preview_unwrap_LT1.sh
./run3.6_preview_unwrap_LT1.sh 1 0.1
```

For the optional small region:

```bash
./run3.6_preview_unwrap_LT1.sh 1 0.1 --use-preview-region
```

The default correlation threshold is `0.1`. This step combines:

```text
(corr >= threshold) * mask * optional mask_def * landmask_ra
```

It creates two PNGs in `run3.6_unwrap_preview/` and deletes temporary GRDs:

```text
mask_presnaphu.png
phase_presnaphu.png
```

Run 3.6 does not call `nearest_grid` or SNAPHU.

### 3.7 Unwrap the phase

Choose one method explicitly or select it interactively when no method option
is supplied:

```bash
# Interpolate masked/low-coherence gaps before SNAPHU
./run3.7_unwrap_LT1.sh --snaphu_interp 0.1
./run3.7_unwrap_LT1.sh 1 --snaphu_interp 0.1

# Standard SNAPHU without nearest_grid interpolation
./run3.7_unwrap_LT1.sh --snaphu 0.1
./run3.7_unwrap_LT1.sh 1 --snaphu 0.1
```

For the Run 3.5 region, add `--use-preview-region`. Run 3.7 creates
`intf_all/REFERENCE_ID_REPEAT_ID/unwrap.grd`.

### 3.8 Geocode the unwrapped phase and generate LOS displacement

```bash
./run3.8_geocode_unwrap_LOS_LT1.sh
./run3.8_geocode_unwrap_LOS_LT1.sh 1 0.1
```

Only missing results are created. Existing files are reported as `[REUSE]` and
are not overwritten. In particular, wrapped-phase, correlation, and amplitude
geocoding produced earlier by GMTSAR is preserved.

The LOS conversion follows `geocode.csh`:

```text
LOS(mm) = unwrap(rad) * radar_wavelength(m) * -79.58
```

Positive LOS displacement follows the GMTSAR convention of range decrease,
meaning motion toward the satellite. Main outputs include:

```text
unwrap_mask.grd
unwrap_mask_ll.grd
unwrap_mask_ll.png
los.grd
los_ll.grd
los.png
los_ll.png
```

The geographic sampling is approximately one quarter of
`filter_wavelength`. A value of `60` therefore produces approximately 15 m
sampling.

### 3.9 Optionally remove a long-wavelength LOS trend

```bash
./run3.9_detrend_LOS_LT1.sh
./run3.9_detrend_LOS_LT1.sh 1
```

The method follows the earlier LT-1 batch workflow:

```bash
gmt grdtrend los_ll.grd -N6r \
  -Tlos_ll_trend.grd \
  -Dlos_ll_detrend.grd
```

`-N6r` fits a robust six-parameter quadratic surface. The fitted trend grid is
temporary and is deleted after plotting. Retained results are:

```text
intf_all/REFERENCE_ID_REPEAT_ID/los_ll_detrend.grd
intf_all/REFERENCE_ID_REPEAT_ID/los_ll_detrend.png
intf_all/REFERENCE_ID_REPEAT_ID/los_ll_detrend_comparison.png
```

Polynomial detrending removes a possible ionospheric or residual-orbit
long-wavelength ramp; it is not a unique ionospheric correction. Inspect the
three-panel comparison because broad real deformation can also be removed.

## Main output sequence

| Step | Main result |
|---|---|
| Run 1.2 | `raw/LT1_YYYYMMDD.{SLC,PRM,LED}` |
| Run 1.3 | `baseline_plot.png`, `baseline_summary.tsv` |
| Run 2.1 | `topo/dem.grd` |
| Run 3.1 | cropped and aligned `SLC/` stack |
| Run 3.2 | `topo/topo_ra.grd`, `topo/trans.dat` |
| Run 3.3 | `intf_all/REFERENCE_ID_REPEAT_ID/phasefilt.grd`, `corr.grd` |
| Run 3.4 | pair-local `landmask_ra.grd` |
| Run 3.7 | `unwrap.grd` |
| Run 3.8 | `unwrap_mask_ll.grd`, `los_ll.grd` |
| Run 3.9 | `los_ll_detrend.grd` and comparison figures |

## Optional amplitude-change tools

The repository also contains tools separate from the DInSAR phase workflow:

- `run_amp_geocode_change_LT1.sh` geocodes existing `amp1.grd` and `amp2.grd`
  and calculates post/pre power change.
- `LT1_existing_amp_geocode/` contains the same workflow with a Google Earth
  export helper.
- `amplitude_full_frame/` contains full-frame alignment and intensity-change
  scripts.

See the README files in those directories before using the optional products.

## Notes and limitations

- Do not mix ascending and descending acquisitions in one track directory.
- The workflow requires exactly two compatible LT-1 acquisitions.
- Precise orbits are preferred. Metadata/coarse orbit repair is a fallback.
- A successful parameter check does not guarantee useful coherence.
- Large LT-1 grids can make `grdmath`, `grdimage`, and `proj_ra2ll.csh` slow and
  disk-intensive. Use Run 3.5 for a small test region when appropriate.
- `SLC_factor=10` controls integer scaling during LT-1 SLC creation; it is not a
  multilook or spatial downsampling factor.
- Always inspect correlation, mask, unwrapped phase, LOS, and detrending plots
  before interpreting a landslide signal.

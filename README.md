# FlashAtten for Windows

从源码编译 Windows 版 `flash-attn` wheel，覆盖：

| GPU | 架构 | 本工程 gencode |
|-----|------|----------------|
| RTX 40 系 (4090 等) | sm_89 | `sm_80`（CUDA major-8 兼容） |
| RTX 50 系 (5060/5080/5090 等) | sm_120 | `sm_120`（需 CUDA Toolkit ≥ 12.8） |

当前默认对齐本机 Pointcept 环境：

- Python 3.11
- PyTorch `2.11.0+cu128`
- flash-attn `2.8.3`

## 目录

```text
FlashAtten_Win/
  build.ps1                 
  config.ps1                
  scripts/
    00_check_env.ps1
    01_install_build_deps.ps1
    02_fetch_source.ps1
    03_build_wheel.ps1
    04_install_and_verify.ps1
  source/                   # Flash Attention 源代码
  dist/                     # 输出 .whl
  logs/                     # 构建日志
```

## 一键构建

在 PowerShell 中：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -InstallAfter
```

常用参数：

- `-SkipDeps`  已装过 CUDA toolkit / pip 依赖时跳过
- `-SkipFetch` 源码已就绪时跳过下载
- `-InstallAfter` 编完后装进 Pointcept 并做 CUDA smoke test

分步：

```powershell
.\scripts\01_install_build_deps.ps1
.\scripts\00_check_env.ps1
.\scripts\02_fetch_source.ps1
.\scripts\03_build_wheel.ps1
.\scripts\04_install_and_verify.ps1
```

## 环境变量（可选）

| 变量 | 含义 | 默认 |
|------|------|------|
| `FLASHATTN_PYTHON` | 用于编译的 python.exe | `~/.conda/envs/Pointcept/python.exe` |
| `FLASHATTN_VERSION` | flash-attn 版本 | `2.8.3` |
| `FLASH_ATTN_CUDA_ARCHS` | flash-attn 架构标签 | `80;120` |
| `TORCH_CUDA_ARCH_LIST` | PyTorch 扩展架构 | `8.0;12.0` |
| `MAX_JOBS` | 并行编译任务 | `4` |
| `NVCC_THREADS` | nvcc 内部线程 | `2` |
| `CUDA_HOME` | CUDA toolkit 根目录 | 自动探测 |
| `FLASHATTN_SRC` | 源码工作目录（宜短路径，默认 C:） | `C:\fa_src` |

## 安装到其他机器

目标机需要：

1. 同一 OS：Windows x64
2. 同一 Python：3.11.x
3. 同一 PyTorch / CUDA 组合（当前为 `2.11.0+cu128`）
4. NVIDIA 驱动足够新（50 系尤其如此）

```powershell
pip install --force-reinstall --no-deps .\dist\flash_attn-*.whl
python -c "import flash_attn; print(flash_attn.__version__)"
```

## Tips

1. **Windows 路径过长**：源码解压到短路径 `C:\fa_src`（可用 `FLASHATTN_SRC` 覆盖）。
2. **日志**：完整编译输出在 `C:\fa_build_logs\build_combined.log`。
3. **断点续编**：设置 `$env:FLASHATTN_KEEP_BUILD=1` 可跳过清理 `build/`。
2. **conda CUDA 头文件布局**：`nv/target` 在 `include\targets\x64\nv`，脚本会建 junction 到 `include\nv`。
3. **必须用 VS 2022（或 2019）工具链**：CUDA 12.8 的 `cudafe++` 在 **VS 2026** 上会 `ACCESS_VIOLATION`（即使加了 `-allow-unsupported-compiler`）。  
   推荐安装：
   ```powershell
   winget install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-package-agreements --accept-source-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
   ```
4. **编译时间长、内存占用大**：默认 `MAX_JOBS=4`；内存不够可设 `MAX_JOBS=1`。

## 说明

- 官方 PyPI 几乎不提供 Windows 预编译 wheel，本工程强制 `FLASH_ATTENTION_FORCE_BUILD=TRUE` 本地编译。
- 完整编译通常 **30–120+ 分钟**，并占用较多 CPU/内存。
- 若只要 40 系、不要 50 系，可设 `FLASH_ATTN_CUDA_ARCHS=80` 以缩短编译时间。

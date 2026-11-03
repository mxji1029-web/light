# 光语者 · 让照片听得见

**基于安路 EG4S20 FPGA 的家庭记忆影音相册。**

22张动画风格照片串起一家人的童年、成长、离家与团聚。FPGA从TF卡自主读取照片与音乐，通过HDMI输出画面和声音，并叠加逐字歌词与实时音乐频谱。

![家庭记忆主题示例（AI绘制）](docs/images/family_memory.png)

## 作品特点

- **切图不断乐**：后台加载下一张照片，SDRAM双缓冲切换画面，背景音乐保持连续。
- **歌词跟随实际播放进度**：依据音频采样消费事件逐字推进，47句歌词、466个时间事件；暂停与继续共用媒体时间。
- **真实音频频谱**：PCM经Hann窗、1024点FFT与频带映射，驱动底边对齐的32根细柱及峰值线。
- **图片处理与转场**：FPGA内完成等比例居中、Q8双线性缩放；首对照片粒子飘散，其余照片使用几何转场。
- **板载交互**：手动切图、自动轮播、全局暂停，以及亮度、对比度、音量设置。

运行阶段由FPGA完成核心算法与控制，无额外处理器。逐照片独立人声讲述列为后续扩展。

## 硬件与最终版本

| 项目 | 配置 |
| --- | --- |
| 开发板 / FPGA | HX4S20C / EG4S20BG256 |
| 显示 / 音频 | 640×480 RGB24 / 标称48kHz、16位PCM |
| 缓存 | 8MiB合封SDRAM，前后台双缓冲 |
| 发布配置 | MEM50，内存用户时钟50MHz，转发相位150.75° |
| 开发环境 | Windows、TangDynasty 6.2.168116、EG4器件库与平台IP许可 |

已验证的相册位流：[oral_album_mem50_sip_candidate.bit](bitstreams/oral_album_mem50_sip_candidate.bit)。该版本已有实板播放、Flash固化及断电重启正常反馈。

## 快速编译

克隆或下载仓库后，在仓库根目录打开PowerShell，执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\prepare_project.ps1
```

随后用TD打开：

```text
work_build/proj/src/td_project/HDMI1.4b_Transmitter_v1.0.al
```

准备脚本核对113份相册输入，在新的工作副本中适配工程路径与四个歌词字库路径。`.gitattributes`保留冻结源文件的原始换行和字节；`*_Runs/`中的`.prj`及`settings.cfg`是构建配置，需要保留。

命令行完成综合、布局布线与位流生成：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_project.ps1 -TDHome D:\Anlogic
```

将`TDHome`改为本机TD安装目录。生成结果位于：

```text
work_build/proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0.bit
```

构建主工程不需要Python。素材、字模和仿真辅助工具按需使用Python3、Pillow、NumPy、Icarus Verilog或ModelSim。历史辅助脚本的路径与素材配置需按实际环境调整。

## 仓库结构

| 目录 | 内容 |
| --- | --- |
| [proj](proj) | 最终相册RTL、TD工程、约束、平台IP、字库与ROM数据 |
| [diagnostic_source](diagnostic_source) | 独立SDRAM自检源码，114份冻结输入 |
| [build_flow](build_flow) | 与最终发布一致的布局布线及独立hold修复流程 |
| [bitstreams](bitstreams) | 相册与自检位流 |
| [sim](sim) | 模块测试平台及参考向量 |
| [tools](tools) | 素材转换、歌词字模、频谱、缩放及开发辅助脚本 |
| [validation](validation) | 输入哈希、时序及资源报告、主要模型验证结果 |
| [third_party](third_party) | 转场参考源码、来源记录与许可证 |

## 按键与上板

| 按键 | 普通播放模式 |
| --- | --- |
| KEY2 | 下一张照片 |
| KEY4 | 开关自动轮播 |
| KEY3短按 | 开始、暂停、继续 |
| KEY3长按约1秒 | 进入或退出设置 |

设置中短按KEY3选择亮度、对比度、音量，KEY2减小、KEY4增大。上电先显示首张照片，短按KEY3开始播放。

相册可先用`PROGRAM_SRAM`验证；Flash固化参数为`PROGRAM_FLASH`、W25Q16、`16 Mbits`、`5 MHz`。独立自检位流使用`PROGRAM_SRAM`，运行时关闭HDMI。

## TF卡与素材

公开仓库提供代码、编译资源和一张AI主题预览图。演示配乐与完整照片集单独准备。播放需要24位非压缩BMP、配套PCM，以及记录文件实际扇区位置的ALY1资源索引；换卡或重新复制文件后，应重新生成索引。部署工具保留原开发卡盘符、卷校验与素材配置，使用时按实际卡调整。

字库、歌词表和生成的RTL事件表属于现有工程的编译输入，已保留。两个工程中各三份未被引用的历史音乐文件已从公开版本移除，并同步更新输入清单。

## 验证记录

- [输入清单](validation/album_input_sha256.json)逐项绑定113份相册源；自检清单绑定114份输入。
- [最终时序报告](validation/final_timing.rpt)及[完整分组记录](validation/timing_groups_complete.json)覆盖15个报告分组，两组SDRAM建立时间余量分别为+1.038ns、+0.913ns。
- 公开整理已核对保留源码、工程引用、位流哈希及路径准备流程。模型测试范围见各结果文件；真实SDRAM全温度、电压范围的可靠性属于专项验证。

最终相册位流SHA256：

```text
daf733e618c40b0ff3cc9948df83dd354099961012be393a167ee06ceb56646c
```

## 版权说明

平台HDMI、PLL、FIFO、存储原语及加密SDRAM IP保留提供方声明，使用时需要相应开发环境与许可。第三方参考遵循各自许可证，见[NOTICE](NOTICE)和[转场参考许可](third_party/gl_transitions_reference/LICENSE)。仓库没有对全部平台IP、素材与源码统一授予MIT许可。

`SHA256SUMS.json`记录公开文件的校验值，排除清单自身和Git元数据。


# Frostrail UE4SS Mods

非官方，与游戏开发商无关。

Frostrail（Steam Demo）的 Mod 和 Mod 管理器。作者 Yuuka。

- **Frostrail mod管理器**：Windows 上的单个 EXE。安装、启停、排序、设置、更新 Mod，查看和导出日志，也能在线更新自己。
- **UE4SS-FrostrailCore**：前置。包含固定版 UE4SS、公共 Lua 支持库和游戏内 F8 设置窗口。
- **功能 Mod**：辅助（穿墙高亮、头灯、一键拿取、基础负重）、快存与格子锁、分拣台扩容、种植、堆叠、房主菜单暂停。每个都是独立的包。

## 玩家

从 [Releases](https://github.com/yakumo-hx/Frostrail-UE4SS-Mods/releases/latest) 下载 `FrostrailModManager-<版本>.exe`、Core 和想用的功能 Mod ZIP。管理器在 Windows 10 22H2 和 Windows 11 上双击就能用，不用另装东西。

退出游戏，把 ZIP 拖进管理器就装好了。也可以在管理器里点“安装 → GitHub 链接…”，粘贴本仓库地址，勾选要装的包。具体步骤见[安装与配置](docs/安装与配置.md)。

多人游戏和存档兼容还没有完整测过，建议先备份存档。用堆叠 Mod 的话，关闭、卸载或调低倍率之前，先在 Mod 还开着的时候把超过原版上限的堆拆开并存档，否则多出来的数量会丢。

## Mod 作者

打包格式见[包规范 v2](docs/包规范-v2.md)。不用前置的普通 UE4SS Mod 也能按这个规范打包，用管理器安装。

## 从源码构建

管理器需要 Windows、.NET SDK 和 .NET Framework 4.8 Developer Pack。在仓库根目录运行：

```powershell
powershell -File scripts/Build-Manager.ps1
```

输出为 `build/v<版本>/manager/FrostrailModManager.exe`。构建好的 EXE 不需要 SDK。

Mod 打包需要 Python：

```powershell
python scripts/package.py
# 也可只打一个包：
python scripts/package.py --only FrostrailQuickstash
```

包输出到 `dist/<包版本>/`。以下二进制不在源码仓库中，打包对应的包时需要自行准备：

- **Core**：固定 [UE4SS 3.0.1-1183-gcdbc0b66](https://github.com/UE4SS-RE/RE-UE4SS/tree/cdbc0b66)，将 `dwmapi.dll`、`ue4ss/UE4SS.dll`、`ue4ss/UE4SS-settings.ini`、`ue4ss/LICENSE` 按此目录结构放进 `tools/ue4ss-3.0.1-1183/`。
- **辅助**：预先构建的 `build/FrostrailAssist_P.pak`、`.utoc`、`.ucas`。公开仓库不含资源重建工具；可从同版本的辅助 Release ZIP 取得这三份资源。

其余功能包可直接从仓库打包。锁图标和管理器图标已有成品，日常构建无需重新生成；修改图标时使用对应的 Python 脚本，需要 Pillow。

## 许可

自有源码使用 MIT 许可（[LICENSE](LICENSE)）。UE4SS 和 `mods/shared/Frostrail/json.lua` 保留各自的许可。辅助包里的高亮资源由游戏文件生成，不适用 MIT。

## English

Unofficial Frostrail Steam Demo mods and a portable Windows mod manager, not affiliated with the game developer. Download the manager EXE and the Core / feature ZIPs from [Releases](https://github.com/yakumo-hx/Frostrail-UE4SS-Mods/releases/latest). Close the game, then drag the ZIPs into the manager. See the [installation guide](docs/安装与配置.md) and [package specification](docs/包规范-v2.md) (Chinese).

Building the manager requires Windows, a .NET SDK and the .NET Framework 4.8 Developer Pack; run `scripts/Build-Manager.ps1`. Mod packaging uses `python scripts/package.py`. Core requires the pinned UE4SS binaries; Assist requires prebuilt game assets, neither included in this repository. Original code is MIT-licensed; third-party code and game-derived assets retain their own terms. Multiplayer and full save compatibility are unverified. Split oversized stacks before disabling, uninstalling or reducing the Stacks multiplier.

# 自动保存 DLL

只支持 Frostrail Demo Build `25985740` 和 UE4SS `3.0.1-1183-gcdbc0b66`。这是 Lua 包通过 `package.loadlib` 加载的辅助库，不是 UE4SS 的 `dlls/main.dll` 入口。

DLL 导出 `luaopen_frostrail_autosave`，成功时返回一个保存函数。调用方必须在游戏线程传入现查的本地房主控制器地址。函数返回 `成功布尔值、说明、原生槽名、观察到的写盘次数`；前置条件失败时返回 `false、说明`。它不缓存 UObject，不计时，不处理退出或界面。

初始化先核对 EXE 与 UE4SS 的 PE 时间戳、镜像大小及 x64 标识。任一不符直接返回零个 Lua 结果，不绑定 Lua 地址、不挂 Hook。Lua 入口收到空结果后记录停用原因，跳过整个功能初始化。没有哈希或特征码扫描。

保存使用原生当前世界采集、战役编号与写盘、快照析构。上层写盘函数忽略底层 bool，因此用 MinHook 原样转发底层调用，只收集本次同步保存线程及指定返回地址的结果；恰好一次且为 true 才报告成功。原生历史淘汰和出生点规则保持原样。

## 构建

Windows 下准备 Python、`pefile`（可放 `tools/pydeps/`）及以下工具。版本路径是构建脚本的输入，不随玩家包分发。

- [固定 UE4SS 源码](https://github.com/UE4SS-RE/RE-UE4SS/tree/cdbc0b66)对应的运行包解压到 `tools/ue4ss-3.0.1-1183/`，官方开发包保存为 `tools/zDEV-UE4SS_v3.0.1-1183-gcdbc0b66.zip`。脚本从其中的 PDB 读取 Lua C API 地址，并逐字节核对开发包 DLL 与本地固定 DLL。
- [LLVM-MinGW 20261020](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261020)，解压到 `tools/llvm-mingw-20261020-ucrt-x86_64/`。
- [MinHook 1.3.4](https://github.com/TsudaKageyu/minhook/releases/tag/v1.3.4)，源码解压到 `tools/minhook-1.3.4/`。

在仓库根目录运行：

```powershell
python scripts/build_autosave.py
python scripts/package.py --only FrostrailAutosave --output build/autosave-package
```

DLL 输出到 `build/FrostrailAutosave/autosave.dll`，包内位置为 `FrostrailAutosave/native/autosave.dll`。玩家不需要编译器、Python 或另一份 Lua。自有代码用仓库 MIT 许可，包根另附 MinHook 许可。

私有开发仓库可运行 `python scripts/build_autosave.py --test` 与 `python scripts/check_autosave.py`。测试只覆盖版本拒绝及 Lua 边界，不能替代游戏内写盘和读档。

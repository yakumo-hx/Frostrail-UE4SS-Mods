# 管理器图标

雪花（Frostrail）加右下角橙色拼图徽章（Mod）。图案由 `make_icon.py` 用代码画出，属本项目原创，和其余代码一样按 MIT 授权；没有用到游戏或第三方的图像。

- `Manager.ico`：16、20、24、32、40、48、64、128、256 九档。小尺寸简化画法：24 及以下雪花去掉分叉，48 及以下拼图只留橙色圆点，16 像素下也看得清。64 及以下存为 32 位 BMP，128、256 存为 PNG。
- `Manager.png`：512 像素大图，给 README、发布页用。

构建时 ICO 既是 EXE 的文件图标，也作为资源嵌入；`Program.cs` 从资源读取整个 ICO 给主窗口，标题栏、任务栏、Alt+Tab 各取合适的尺寸。子窗口沿用主窗口图标。

改图时改 `make_icon.py`，在仓库根目录运行（需要 Pillow）：

```powershell
python manager/Assets/make_icon.py
```

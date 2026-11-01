using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Frostrail.ModManager
{
    internal sealed class MainForm : Form
    {
        ManagerService service;
        GameBar gameBar;
        ModList list;
        ModDetails details;
        LogView logs;
        TabControl tabs;
        HeaderTabs pages;
        Label status;
        readonly Timer timer = new Timer { Interval = 2000 };
        readonly string preferences;
        readonly bool isolated;
        string currentGame, selectedId;
        bool busy, syncing, checking;
        DateTime lastCheck;
        List<ModInfo> mods = new List<ModInfo>();
        LaunchLog launch = new LaunchLog();
        Dictionary<string, UpdateInfo> updates = new Dictionary<string, UpdateInfo>();
        public MainForm(string initialGame, string uiDirectory = null)
        {
            isolated = uiDirectory != null;
            preferences = Path.Combine(uiDirectory ?? Path.Combine(Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData), "Yuuka", "FrostrailModManager"), "ui.json");
            var ui = JsonData.Load(preferences);
            currentGame = initialGame ?? JsonData.Text(JsonData.Get(ui, "game"));
            var language = JsonData.Text(JsonData.Get(ui, "language"));
            if (language.Length > 0) UiText.Chinese = language == "zh";
            DateTime.TryParse(JsonData.Text(JsonData.Get(ui, "last_check")), out lastCheck);
            Font = Theme.Body;
            // Sizes are scaled explicitly through Theme.S, so WinForms must not scale them a second time.
            AutoScaleMode = AutoScaleMode.None;
            MinimumSize = new Size(Theme.S(980), Theme.S(660));
            Size = new Size(Convert.ToInt32(JsonData.Get(ui, "width", Theme.S(1280))),
                Convert.ToInt32(JsonData.Get(ui, "height", Theme.S(820))));
            StartPosition = FormStartPosition.CenterScreen;
            Build();
            // Hook once; controls rebuilt later (language switch) are hooked through ControlAdded.
            HookDrop(this);
            Shown += async (s, e) => {
                SelectGame(currentGame);
                if (!isolated && service != null && DateTime.UtcNow - lastCheck.ToUniversalTime() > TimeSpan.FromHours(12))
                    await CheckUpdates();
            };
            timer.Tick += (s, e) => {
                if (service == null) return;
                var before = service.GameRunning;
                service.RefreshGameRunning();
                if (before != service.GameRunning) Availability();
            };
            timer.Start();
            FormClosing += (s, e) => {
                if (busy) { e.Cancel = true; SetStatus(UiText.T("请等当前操作完成。", "Wait for the current operation.")); return; }
                SavePreferences();
                timer.Stop();
            };
        }
        void SavePreferences() => JsonData.Save(preferences, new {
            game = currentGame, language = UiText.Chinese ? "zh" : "en", width = Width, height = Height,
            last_check = lastCheck.ToUniversalTime().ToString("o")
        });
        void Build()
        {
            SuspendLayout();
            foreach (Control old in Controls.Cast<Control>().ToArray()) old.Dispose();
            Text = UiText.T("Frostrail mod管理器 ", "Frostrail mod manager ")
                + typeof(MainForm).Assembly.GetName().Version.ToString(3);
            BackColor = Theme.Back;
            status = new Label { Dock = DockStyle.Bottom, Height = Theme.S(30), Padding = Theme.P(16, 0, 16, 0),
                TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true, BackColor = Theme.Side, ForeColor = Theme.Muted };
            gameBar = new GameBar(isolated ? new string[0] : ManagerService.DiscoverGames(), currentGame);
            pages = new HeaderTabs("Mod", UiText.T("日志", "Logs"));
            tabs = new PageHost { Dock = DockStyle.Fill };
            var modTab = new TabPage("Mod") { BackColor = Theme.Back };
            var logTab = new TabPage(UiText.T("日志", "Logs")) { BackColor = Theme.Back };
            // The splitter is a one-pixel line: the container color shows through it.
            var split = new SplitContainer { Dock = DockStyle.Fill, SplitterWidth = 1, Width = Theme.S(1200),
                SplitterDistance = Theme.S(460), Panel1MinSize = Theme.S(360), Panel2MinSize = Theme.S(480),
                FixedPanel = FixedPanel.Panel1, BackColor = Theme.Line };
            split.Panel1.BackColor = Theme.Back;
            split.Panel2.BackColor = Theme.Back;
            list = new ModList();
            details = new ModDetails();
            logs = new LogView();
            split.Panel1.Controls.Add(list);
            split.Panel2.Controls.Add(details);
            modTab.Controls.Add(split);
            logTab.Controls.Add(logs);
            tabs.TabPages.AddRange(new[] { modTab, logTab });
            Controls.Add(tabs);
            Controls.Add(pages);
            Controls.Add(gameBar);
            Controls.Add(Theme.Rule(DockStyle.Bottom));
            Controls.Add(status);
            pages.Changed += index => tabs.SelectedIndex = index;
            split.SplitterMoving += (s, e) => details.BeginResize();
            split.SplitterMoved += (s, e) => details.EndResize();
            split.MouseUp += (s, e) => details.EndResize();
            gameBar.GameSelected += SelectGame;
            gameBar.LanguageSelected += () => {
                SavePreferences();
                Build();
                RefreshData(true);
            };
            list.Selected += id => {
                if (syncing || selectedId == id) return;
                selectedId = id;
                ShowDetails();
            };
            list.Toggled += Toggle;
            list.LocalInstall += async () => {
                using (var dialog = new OpenFileDialog { Filter = "ZIP|*.zip", Multiselect = true })
                    if (dialog.ShowDialog(this) == DialogResult.OK) await InstallFiles(dialog.FileNames);
            };
            list.RemoteInstall += RemoteInstall;
            list.UpdateRequested += async () => {
                if (updates.Values.Any(u => u.Available)) await UpdateAll();
                else await CheckUpdates();
            };
            list.MoveRequested += async (id, offset) => {
                if (id != null) await Run(() => Task.Run(() => service.Move(id, offset)), false);
            };
            details.UninstallRequested += Uninstall;
            details.UpdateRequested += async id => await UpdateOne(id);
            details.LogsRequested += id => {
                if (tabs.SelectedIndex != 1) tabs.SelectedIndex = 1;
                else logs.LoadLogs(service, mods);
                logs.SelectMod(id);
            };
            details.Status += SetStatus;
            logs.Status += SetStatus;
            tabs.SelectedIndexChanged += (s, e) => {
                pages.Selected = tabs.SelectedIndex;
                if (tabs.SelectedIndex == 1 && service != null) logs.LoadLogs(service, mods);
            };
            ResumeLayout();
        }
        // Dragging the window edge would otherwise reflow the whole details page on every mouse move.
        protected override void OnResizeBegin(EventArgs e)
        {
            base.OnResizeBegin(e);
            details?.BeginResize();
        }
        protected override void OnResizeEnd(EventArgs e)
        {
            base.OnResizeEnd(e);
            details?.EndResize();
        }
        void HookDrop(Control control)
        {
            control.AllowDrop = true;
            control.DragEnter += (s, e) => e.Effect = service != null && !busy && !service.GameRunning
                && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            control.DragDrop += async (s, e) => {
                if (e.Data.GetData(DataFormats.FileDrop) is string[] paths) await InstallFiles(paths);
            };
            control.ControlAdded += (s, e) => HookDrop(e.Control);
            foreach (Control child in control.Controls) HookDrop(child);
        }
        void SelectGame(string path)
        {
            if (busy || string.IsNullOrWhiteSpace(path)) return;
            try
            {
                var root = ManagerService.NormalizeGameRoot(path);
                if (service != null && root == currentGame) return;
                service = new ManagerService(root);
                currentGame = root;
                updates.Clear();
                selectedId = null;
                SavePreferences();
                RefreshData(true);
                SetStatus(UiText.T("已读取 ", "Loaded ") + mods.Count + " Mod");
            }
            catch (Exception e)
            {
                service = null;
                mods.Clear();
                updates.Clear();
                selectedId = null;
                list.Sync(mods, new LaunchLog(), updates);
                details.ShowMod(null, null, new LaunchLog(), null);
                Availability();
                SetStatus(e.Message);
            }
        }
        void RefreshData(bool detailChanged)
        {
            if (service == null) return;
            mods = service.ListMods();
            // A local install or uninstall after a check changes what is installed; re-judge the old results.
            foreach (var info in updates.Values) info.Compare(mods.FirstOrDefault(m => m.Id == info.Id)?.Version);
            launch = service.ReadLaunch(mods);
            syncing = true;
            list.Sync(mods, launch, updates);
            if (selectedId != null) list.SelectId(selectedId);
            var next = list.SelectedId;
            bool changed = next != selectedId;
            selectedId = next;
            syncing = false;
            if (changed || detailChanged) ShowDetails();
            Availability();
        }
        void ShowDetails()
        {
            var mod = mods.FirstOrDefault(m => m.Id == selectedId);
            updates.TryGetValue(selectedId ?? "", out var update);
            details.ShowMod(service, mod, launch, update);
            Availability();
        }
        void Availability()
        {
            bool running = service?.GameRunning ?? false;
            bool canWrite = service != null && !busy && !running;
            gameBar.SetBusy(busy);
            gameBar.ShowRunning(running);
            list.SetAvailability(canWrite,
                busy || checking || service == null || running && updates.Values.Any(u => u.Available));
            details.SetAvailability(canWrite, running);
            UseWaitCursor = busy;
        }
        void SetStatus(string message) { status.Text = message; }
        async Task<bool> Run(Func<Task> action, bool detailChanged = true, bool writes = true)
        {
            if (service == null || busy) return false;
            if (writes && service.GameRunning) { SetStatus(UiText.T("请先退出游戏。", "Close the game first.")); return false; }
            busy = true;
            Availability();
            try
            {
                await action();
                RefreshData(detailChanged);
                SetStatus(UiText.T("操作完成。", "Operation completed."));
                return true;
            }
            catch (Exception e) { SetStatus(e.Message); return false; }
            finally { busy = false; Availability(); }
        }
        bool Confirm(string text) => MessageBox.Show(this, text, UiText.T("确认操作", "Confirm operation"),
            MessageBoxButtons.OKCancel, MessageBoxIcon.None) == DialogResult.OK;
        async Task InstallFiles(string[] paths)
        {
            if (service == null || busy || service.GameRunning) return;
            try
            {
                var enable = new Dictionary<string, bool>();
                foreach (var path in paths) using (var package = service.InspectPackage(path))
                {
                    var notice = JsonData.Local(JsonData.Get(package.Manifest.Notices, "enable"), UiText.Chinese ? "zh" : "en");
                    enable[package.Manifest.Id] = notice.Length == 0 || Confirm(notice);
                }
                if (await Run(() => Task.Run(() => service.InstallMany(paths, m => enable[m.Id]))))
                    SetStatus(service.LastResult);
            }
            catch (Exception e) { SetStatus(e.Message); }
        }
        async void Toggle(string id, bool enabled)
        {
            if (service == null || busy || service.GameRunning) return;
            try
            {
                var group = service.ToggleGroup(id, enabled);
                var notices = group.Select(m => m.Notice(enabled ? "enable" : "disable", UiText.Chinese ? "zh" : "en"))
                    .Where(t => t.Length > 0).ToList();
                if (group.Count > 1) notices.Insert(0, UiText.T("一起更改：", "Change together: ") + string.Join(", ", group.Select(m => m.Name(UiText.Chinese ? "zh" : "en"))));
                if (notices.Count > 0 && !Confirm(string.Join("\n\n", notices))) return;
                await Run(() => Task.Run(() => service.SetEnabled(id, enabled)), group.Any(m => m.Id == selectedId));
            }
            catch (Exception e) { SetStatus(e.Message); }
        }
        async void Uninstall(string id)
        {
            if (service == null || busy || service.GameRunning) return;
            var mod = mods.First(m => m.Id == id);
            var dependents = mods.Where(m => m.Manifest.Requires.Contains(id)).Select(m => m.Id).ToArray();
            using (var dialog = Dialog(UiText.T("卸载 ", "Uninstall ") + mod.Name(UiText.Chinese ? "zh" : "en"), 480, 250))
            {
                var message = mod.Notice("uninstall", UiText.Chinese ? "zh" : "en");
                if (message.Length == 0) message = UiText.T("这个 Mod 放进游戏目录的文件都会被删除。", "Files this mod placed in the game folder will be removed.");
                if (dependents.Length > 0)
                    message += "\n\n" + UiText.T("依赖它的 Mod 会被关闭：", "Mods that depend on it will be disabled: ") + string.Join(", ", dependents);
                dialog.Controls.Add(new Label { Dock = DockStyle.Fill, Padding = Theme.P(20, 18, 20, 0), Text = message, ForeColor = Theme.Text });
                var keep = new CheckBox { Dock = DockStyle.Bottom, Height = Theme.S(40), Padding = Theme.P(20, 0, 0, 0),
                    Text = UiText.T("保留设置（重新安装后沿用）", "Keep settings (used again after reinstalling)") };
                dialog.Controls.Add(keep);
                dialog.Controls.Add(Buttons(dialog, UiText.T("卸载", "Uninstall"), Look.Danger));
                if (dialog.ShowDialog(this) == DialogResult.OK)
                    await Run(() => Task.Run(() => service.Uninstall(id, keep.Checked)));
            }
        }
        Form Dialog(string title, int width, int height) => new Form {
            Icon = Icon,
            Text = title, ClientSize = new Size(Theme.S(width), Theme.S(height)), StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false, ShowInTaskbar = false,
            Font = Theme.Body, BackColor = Theme.Back };
        // Bottom button row: confirm on the right, cancel beside it.
        static Control Buttons(Form dialog, string confirm, Look look)
        {
            var row = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = Theme.S(56), FlowDirection = FlowDirection.RightToLeft,
                Padding = Theme.P(16, 12, 8, 12), BackColor = Theme.Side };
            var ok = Theme.Button(confirm, look);
            ok.DialogResult = DialogResult.OK;
            var cancel = Theme.Button(UiText.T("取消", "Cancel"));
            cancel.DialogResult = DialogResult.Cancel;
            row.Controls.Add(ok);
            row.Controls.Add(cancel);
            dialog.CancelButton = cancel;
            // Enter confirms ordinary dialogs. A destructive one starts on Cancel: Enter closes it, Tab reaches the action.
            if (look != Look.Danger) dialog.AcceptButton = ok;
            else dialog.Load += (s, e) => dialog.ActiveControl = cancel;
            return row;
        }
        // Checking only reads GitHub, so it runs beside other work instead of making the window busy.
        async Task CheckUpdates()
        {
            if (service == null || checking) return;
            var target = service;
            checking = true;
            Availability();
            SetStatus(UiText.T("正在检查更新…", "Checking for updates…"));
            try
            {
                var result = await target.CheckUpdatesAsync();
                if (IsDisposed || target != service) return;
                updates = result.ToDictionary(u => u.Id);
                lastCheck = DateTime.UtcNow;
                SavePreferences();
                RefreshData(selectedId != null && updates.ContainsKey(selectedId));
                var errors = updates.Values.Where(u => u.Error.Length > 0).Select(u => u.Id + ": " + u.Error).ToArray();
                int count = updates.Values.Count(u => u.Available);
                SetStatus(errors.Length > 0 ? string.Join("; ", errors)
                    : count > 0 ? UiText.T("有 " + count + " 个更新。", count + " update(s) available.")
                    : result.Count == 0 ? UiText.T("已装的 Mod 都没有更新来源。", "No installed mod has an update source.")
                    : UiText.T("都是最新版本。", "Everything is up to date."));
            }
            catch (Exception e) { SetStatus(e.Message); }
            finally { checking = false; Availability(); }
        }
        async Task UpdateOne(string id)
        {
            if (!updates.TryGetValue(id, out var info) || !info.Available) return;
            await Run(async () => { await service.InstallRemoteAsync(info); updates.Remove(id); });
        }
        async Task UpdateAll()
        {
            await Run(async () => {
                // One batch, so a prerequisite updates before the mods that need it.
                var ready = updates.Values.Where(u => u.Available).ToList();
                await service.InstallRemoteManyAsync(ready);
                foreach (var info in ready) updates.Remove(info.Id);
            });
        }
        async void RemoteInstall()
        {
            if (service == null || busy || service.GameRunning) return;
            using (var dialog = Dialog(UiText.T("从 GitHub 安装", "Install from GitHub"), 560, 190))
            {
                var url = new TextBox { Dock = DockStyle.Top, BorderStyle = BorderStyle.FixedSingle };
                var hint = new Label { Dock = DockStyle.Top, Height = Theme.S(30), ForeColor = Theme.Muted,
                    Text = UiText.T("粘贴仓库链接，或 …/tree/分支/目录 形式的链接。", "Paste a repository link or a …/tree/branch/folder link.") };
                var box = new Panel { Dock = DockStyle.Fill, Padding = Theme.P(20, 16, 20, 0) };
                box.Controls.Add(url);
                box.Controls.Add(hint);
                dialog.Controls.Add(box);
                dialog.Controls.Add(Buttons(dialog, UiText.T("读取", "Read"), Look.Primary));
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                await Run(async () => {
                    var choices = await service.GetInstallChoicesAsync(url.Text);
                    if (choices.Count == 0) throw new IOException(UiText.T("没有找到 ZIP 附件。", "No ZIP assets found."));
                    var picked = choices.ToList();
                    if (choices.Count > 1) using (var picker = Dialog(UiText.T("选择要安装的包", "Choose packages"), 520, 360))
                    {
                        // All ticked by default: a repository link usually means "give me this set".
                        var list = new CheckedListBox { Dock = DockStyle.Fill, CheckOnClick = true, BorderStyle = BorderStyle.None,
                            IntegralHeight = false };
                        foreach (var item in choices) list.Items.Add(item.Name, true);
                        var frame = new Panel { Dock = DockStyle.Fill, Padding = Theme.P(20, 16, 20, 8) };
                        frame.Controls.Add(list);
                        picker.Controls.Add(frame);
                        picker.Controls.Add(Buttons(picker, UiText.T("安装", "Install"), Look.Primary));
                        if (picker.ShowDialog(this) != DialogResult.OK) return;
                        picked = list.CheckedIndices.Cast<int>().Select(i => choices[i]).ToList();
                        if (picked.Count == 0) return;
                    }
                    await service.InstallRemoteManyAsync(picked, manifest => {
                        var notice = JsonData.Local(JsonData.Get(manifest.Notices, "enable"), UiText.Chinese ? "zh" : "en");
                        return notice.Length == 0 || (bool)Invoke(new Func<bool>(() => Confirm(notice)));
                    });
                });
            }
        }
    }
}

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace Frostrail.ModManager
{
    internal sealed class ModDetails : UserControl
    {
        sealed class CachedPage
        {
            public string Key;
            public ModDetailsPage View;
        }
        readonly Dictionary<string, CachedPage> pages = new Dictionary<string, CachedPage>(StringComparer.OrdinalIgnoreCase);
        ManagerService manager;
        ModDetailsPage current;
        bool canWrite, gameRunning;
        public event Action<string> UninstallRequested, UpdateRequested, LogsRequested, Status;
        public ModDetails() { Dock = DockStyle.Fill; BackColor = Theme.Back; }
        public void BeginResize() => current?.BeginResize();
        public void EndResize() => current?.EndResize();
        public void ShowMod(ManagerService service, ModInfo mod, LaunchLog launch, UpdateInfo update,
            List<ModInfo> installed = null) =>
            Theme.Batch(this, () => SelectMod(service, mod, launch, update, installed));
        void SelectMod(ManagerService service, ModInfo mod, LaunchLog launch, UpdateInfo update, List<ModInfo> installed)
        {
            EndResize();
            current?.ValidateChildren();
            current?.SaveScroll();
            if (manager != service)
            {
                ClearPages();
                manager = service;
            }
            if (installed != null)
            {
                var ids = new HashSet<string>(installed.Select(m => m.Id), StringComparer.OrdinalIgnoreCase) { "" };
                foreach (var id in pages.Keys.Where(id => !ids.Contains(id)).ToArray())
                {
                    pages[id].View.Dispose();
                    pages.Remove(id);
                }
            }
            var all = (installed ?? service?.ListMods() ?? new List<ModInfo>())
                .ToDictionary(m => m.Id, StringComparer.OrdinalIgnoreCase);
            string idKey = mod?.Id ?? "";
            string key = mod == null ? "empty" : JsonData.Serialize(new {
                manifest = mod.Manifest.Data(), mod.Entries, mod.UpdateSource,
                mod.Installed, mod.Changed, failure = launch.Failure(mod),
                update = update?.Available == true ? update.Version : "",
                requires = mod.Manifest.Requires.Select(id => ModDetailsPage.Requirement(id, all)).ToArray(),
                files = FileStamp.Read(service.DetailFiles(mod))
            });
            pages.TryGetValue(idKey, out var cached);
            if (cached == null || cached.Key != key)
            {
                var view = new ModDetailsPage { Visible = false };
                view.UninstallRequested += id => UninstallRequested?.Invoke(id);
                view.UpdateRequested += id => UpdateRequested?.Invoke(id);
                view.LogsRequested += id => LogsRequested?.Invoke(id);
                view.Status += message => Status?.Invoke(message);
                try { view.LoadMod(service, mod, launch, update, all); }
                catch { view.Dispose(); throw; }
                if (cached != null)
                {
                    view.ScrollPosition = cached.View.ScrollPosition;
                    cached.View.Dispose();
                }
                cached = new CachedPage { Key = key, View = view };
                pages[idKey] = cached;
                Controls.Add(view);
            }
            cached.View.SetAvailability(canWrite, gameRunning);
            if (current == cached.View) return;
            SuspendLayout();
            try
            {
                if (current != null && !current.IsDisposed) current.SetShown(false);
                current = cached.View;
                current.SetShown(true);
                current.BringToFront();
            }
            finally { ResumeLayout(true); }
            current.RestoreScroll();
        }
        public void SetAvailability(bool writable, bool running)
        {
            canWrite = writable;
            gameRunning = running;
            current?.SetAvailability(writable, running);
        }
        void ClearPages()
        {
            foreach (var page in pages.Values) page.View.Dispose();
            pages.Clear();
            current = null;
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing) ClearPages();
            base.Dispose(disposing);
        }
    }

    // Retained pages stay parented so switching does not recreate their native child windows.
    internal sealed class ModDetailsPage : UserControl
    {
        // Fixed header: the title, one meta line and the action buttons never move with the content below.
        readonly Label title = new Label { Dock = DockStyle.Fill, AutoEllipsis = true, Font = Theme.Title,
            ForeColor = Theme.Text, TextAlign = ContentAlignment.MiddleLeft, Margin = Padding.Empty };
        readonly Label meta = new Label { Dock = DockStyle.Fill, AutoEllipsis = true, Font = Theme.Body,
            ForeColor = Theme.Muted, TextAlign = ContentAlignment.MiddleLeft, Margin = Padding.Empty };
        readonly FlowLayoutPanel actions = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false,
            Margin = Padding.Empty, Padding = Theme.P(0, 6, 0, 0) };
        readonly Panel body = new Panel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Theme.Back };
        readonly TableLayoutPanel content = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 1,
            Padding = Theme.P(24, 18, 24, 24) };
        readonly List<SettingsEditor> editors = new List<SettingsEditor>();
        readonly List<Button> changes = new List<Button>();
        readonly Label readOnly = new Label { AutoSize = true, ForeColor = Theme.Warn, Font = Theme.Body };
        readonly ToolTip tips = new ToolTip();
        bool resizing;
        public event Action<string> UninstallRequested, UpdateRequested, LogsRequested, Status;
        public Point ScrollPosition { get; set; }
        public void SaveScroll() => ScrollPosition = new Point(-body.AutoScrollPosition.X, -body.AutoScrollPosition.Y);
        public void RestoreScroll() => body.AutoScrollPosition = ScrollPosition;
        public void SetShown(bool visible)
        {
            // Visibility propagates to every child. Suspend their layouts too, not just the outer host.
            var controls = Descendants(this).ToArray();
            foreach (var control in controls) control.SuspendLayout();
            try { Visible = visible; }
            finally
            {
                foreach (var control in controls.Reverse()) control.ResumeLayout(false);
            }
        }
        static IEnumerable<Control> Descendants(Control parent)
        {
            yield return parent;
            foreach (Control child in parent.Controls)
                foreach (var control in Descendants(child)) yield return control;
        }
        public ModDetailsPage()
        {
            Dock = DockStyle.Fill;
            BackColor = Theme.Back;
            var header = new TableLayoutPanel { Dock = DockStyle.Top, Height = Theme.S(128), ColumnCount = 1, RowCount = 3,
                Padding = Theme.P(24, 18, 24, 10), BackColor = Theme.Back };
            header.RowStyles.Add(new RowStyle(SizeType.Absolute, Theme.S(36)));
            header.RowStyles.Add(new RowStyle(SizeType.Absolute, Theme.S(24)));
            header.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            header.Controls.Add(title, 0, 0);
            header.Controls.Add(meta, 0, 1);
            header.Controls.Add(actions, 0, 2);
            body.Controls.Add(content);
            Controls.Add(body);
            Controls.Add(Theme.Rule(DockStyle.Top));
            Controls.Add(header);
            body.Resize += (s, e) => { if (!resizing) FitText(); };
        }
        static string Language => UiText.Chinese ? "zh" : "en";
        static string Local(object value) => JsonData.Local(value, Language);

        // While the window edge or the splitter is dragged, the body keeps its layout and reflows once at the end.
        public void BeginResize()
        {
            if (resizing) return;
            resizing = true;
            body.SuspendLayout();
        }
        public void EndResize()
        {
            if (!resizing) return;
            resizing = false;
            FitText();
            body.ResumeLayout(true);
        }
        int TextWidth => Math.Max(Theme.S(200), body.ClientSize.Width - content.Padding.Horizontal - Theme.S(4));
        void FitText()
        {
            int width = TextWidth;
            foreach (var label in content.Controls.OfType<Label>())
            {
                label.MaximumSize = new Size(width, 0);
                if (Equals(label.Tag, "wide")) label.MinimumSize = new Size(width, 0);
            }
        }
        void Add(Control control, int below = 14)
        {
            int row = content.RowCount++;
            content.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            control.Margin = new Padding(0, 0, 0, Theme.S(below));
            content.Controls.Add(control, 0, row);
        }
        Label Line(string text, Color color, Font font = null) => new Label { Text = text, AutoSize = true,
            ForeColor = color, Font = font ?? Theme.Body, MaximumSize = new Size(TextWidth, 0) };
        void AddAction(string label, Action click, bool writes, Look look = Look.Secondary)
        {
            var button = Theme.Button(label, look);
            button.Click += (s, e) => { try { click(); } catch (Exception ex) { Status?.Invoke(ex.Message); } };
            actions.Controls.Add(button);
            if (writes) changes.Add(button);
        }
        public void LoadMod(ManagerService service, ModInfo mod, LaunchLog launch, UpdateInfo update,
            Dictionary<string, ModInfo> installed)
        {
            SuspendLayout();
            body.SuspendLayout();
            content.SuspendLayout();
            actions.SuspendLayout();
            try
            {
                if (mod == null) ShowEmpty();
                else ShowPage(service, mod, launch, update, installed);
            }
            finally
            {
                actions.ResumeLayout(true);
                content.ResumeLayout(true);
                body.ResumeLayout(true);
                ResumeLayout(true);
            }
        }
        void ShowEmpty()
        {
            title.Text = "";
            meta.Text = "";
            Add(Line(UiText.T("在左侧选择一个 Mod。", "Select a mod on the left."), Theme.Muted));
        }
        void ShowPage(ManagerService service, ModInfo mod, LaunchLog launch, UpdateInfo update,
            Dictionary<string, ModInfo> installed)
        {
            // Header: what the player needs to recognise the mod. IDs and entry folders go to the footer.
            var parts = new List<string> { mod.Version.Length == 0 ? "—" : mod.Version };
            if (mod.Manifest.Author.Length > 0) parts.Add(mod.Manifest.Author);
            if (mod.Manifest.Requires.Count > 0)
                parts.Add(UiText.T("需要 ", "Requires ")
                    + string.Join(", ", mod.Manifest.Requires.Select(id => Requirement(id, installed))));
            title.Text = mod.Name(Language);
            meta.Text = string.Join("  ·  ", parts);
            tips.SetToolTip(meta, meta.Text);

            var pages = service.ReadSettings(mod);
            var readme = service.Readme(mod);
            var folder = mod.Entries.Count == 0 ? service.GameRoot : Path.Combine(service.ModsRoot, mod.Entries[0]);
            if (update?.Available == true)
                AddAction(UiText.T("更新到 ", "Update to ") + update.Version, () => UpdateRequested?.Invoke(mod.Id), true, Look.Primary);
            AddAction(UiText.T("打开文件夹", "Open folder"), () => Open(folder), false);
            AddAction(UiText.T("查看日志", "View log"), () => LogsRequested?.Invoke(mod.Id), false);
            if (readme.Length > 0) AddAction(UiText.T("说明", "Readme"), () => ShowReadme(mod, readme), false);
            if (pages.Count > 0) AddAction(UiText.T("恢复默认设置", "Restore defaults"), RestoreDefaults, true);
            if (pages.Count == 0 && mod.Entries.Count > 0)
            {
                var config = Path.Combine(folder, "config.json");
                if (File.Exists(config)) AddAction(UiText.T("打开配置文件", "Open config"), () => Open(config), false);
            }
            AddAction(UiText.T("卸载…", "Uninstall…"), () => UninstallRequested?.Invoke(mod.Id), true, Look.Danger);

            // Body: description, notices, launch problems, then settings.
            var description = mod.Manifest.Description == null ? "" : Local(mod.Manifest.Description);
            if (description.Length > 0) Add(Line(description, Theme.Text));
            var notices = mod.Manifest.Notices.Values.Select(Local).Where(x => x.Length > 0).Distinct().ToArray();
            if (notices.Length > 0)
                Add(Theme.Note(UiText.T("作者提示\n", "Author notes\n") + string.Join("\n", notices), Theme.WarnSoft, Theme.Warn));
            var failure = launch.Failure(mod);
            if (failure.Length > 0)
                Add(Theme.Note(UiText.T("上次启动失败\n", "Last launch failed\n") + failure, Theme.DangerSoft, Theme.Danger));

            if (pages.Count > 0)
            {
                Add(Line(UiText.T("设置", "Settings"), Theme.Text, Theme.Heading), 2);
                Add(Line(UiText.T("标着 F8 的项也能在游戏里即时调整；其余下次启动游戏生效。",
                    "Items marked F8 can also be changed live in game; the rest apply at next launch."), Theme.Muted, Theme.Small), 6);
                Add(readOnly, 4);
                foreach (var page in pages)
                {
                    var editor = new SettingsEditor();
                    editor.Status += message => Status?.Invoke(message);
                    editor.LoadPage(service, page);
                    editors.Add(editor);
                    Add(editor);
                }
            }
            else Add(Line(UiText.T("这个 Mod 没有可在这里调整的设置。", "This mod has no settings to adjust here."), Theme.Muted));

            // Footer: identifiers for bug reports, kept out of the way.
            var footer = "ID " + mod.Id;
            if (!(mod.Entries.Count == 1 && mod.Entries[0] == mod.Id) && mod.Entries.Count > 0)
                footer += "  ·  " + UiText.T("入口 ", "Entries ") + string.Join(", ", mod.Entries);
            if (mod.UpdateSource.Length > 0) footer += "  ·  " + mod.UpdateSource;
            Add(Line(footer, Theme.Muted, Theme.Small), 0);
            FitText();
        }
        internal static string Requirement(string id, Dictionary<string, ModInfo> installed)
        {
            if (!installed.TryGetValue(id, out var required)) return id + UiText.T("（未安装）", " (not installed)");
            return required.Name(Language) + (required.Enabled ? "" : UiText.T("（未启用）", " (disabled)"));
        }
        void RestoreDefaults()
        {
            Theme.Batch(this, () => { foreach (var editor in editors) editor.RestoreDefaults(); });
            Status?.Invoke(UiText.T("已恢复默认设置。", "Defaults restored."));
        }
        void ShowReadme(ModInfo mod, string readme)
        {
            using (var window = new Form { Text = mod.Name(Language), Size = new Size(Theme.S(720), Theme.S(560)),
                Icon = FindForm()?.Icon,
                StartPosition = FormStartPosition.CenterParent, Font = Theme.Body, ShowInTaskbar = false })
            {
                window.Controls.Add(new TextBox { Multiline = true, ReadOnly = true, Dock = DockStyle.Fill, BackColor = Theme.Back,
                    BorderStyle = BorderStyle.None, ScrollBars = ScrollBars.Vertical, Text = readme.Replace("\r\n", "\n").Replace("\n", "\r\n") });
                window.Padding = Theme.P(16, 12, 8, 12);
                window.BackColor = Theme.Back;
                window.ShowDialog(this);
            }
        }
        static void Open(string path) => Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        public void SetAvailability(bool canWrite, bool gameRunning)
        {
            foreach (var button in changes) button.Enabled = canWrite;
            foreach (var editor in editors) editor.SetReadOnly(!canWrite);
            readOnly.Text = gameRunning ? UiText.T("游戏运行中，设置暂时只读。", "Settings are read-only while the game runs.") : "";
            readOnly.Visible = gameRunning;
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing) { tips.Dispose(); readOnly.Dispose(); }
            base.Dispose(disposing);
        }
    }
}

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace Frostrail.ModManager
{
    internal sealed class LogView : UserControl
    {
        readonly RichTextBox summary = new RichTextBox { Dock = DockStyle.Fill, ReadOnly = true, BorderStyle = BorderStyle.None,
            BackColor = Theme.Side, Font = Theme.Body, ScrollBars = RichTextBoxScrollBars.Vertical };
        readonly ComboBox sources = new ComboBox { Width = Theme.S(270), DropDownStyle = ComboBoxStyle.DropDownList };
        readonly ComboBox levels = new ComboBox { Width = Theme.S(110), DropDownStyle = ComboBoxStyle.DropDownList };
        readonly TextBox search = new TextBox { Width = Theme.S(220), BorderStyle = BorderStyle.FixedSingle, Font = Theme.Body };
        readonly RichTextBox text = new RichTextBox { Dock = DockStyle.Fill, ReadOnly = true, BorderStyle = BorderStyle.None,
            Font = Theme.Mono, BackColor = Theme.Back, WordWrap = false };
        ManagerService service;
        List<ModInfo> mods = new List<ModInfo>();
        LaunchLog launch = new LaunchLog();
        List<LogEntry> entries = new List<LogEntry>();
        string launchStamp, sourceStamp, renderedStamp, summaryDocument, textDocument;
        int launchRevision;
        bool loading;
        public event Action<string> Status;
        public LogView()
        {
            Dock = DockStyle.Fill;
            Padding = Theme.P(16, 14, 16, 12);
            BackColor = Theme.Back;
            Font = Theme.Body;
            Theme.StyleCombo(sources);
            Theme.StyleCombo(levels);
            foreach (var control in new Control[] { sources, levels, search }) control.Margin = Theme.P(0, 4, 8, 0);
            // Summary card: game build, loader version, failures first.
            var card = new Panel { Dock = DockStyle.Top, Height = Theme.S(92), Padding = Theme.P(14, 10, 14, 10), BackColor = Theme.Side };
            card.Controls.Add(summary);
            var bar = new FlowLayoutPanel { Dock = DockStyle.Top, Height = Theme.S(52), Padding = Theme.P(0, 10, 0, 0), WrapContents = false };
            var export = Theme.Button(UiText.T("导出诊断包", "Export diagnostics"), Look.Primary);
            var refresh = Theme.Button(UiText.T("刷新", "Refresh"));
            var frame = new Panel { Dock = DockStyle.Fill, Padding = Theme.P(1, 1, 1, 1), BackColor = Theme.Line };
            frame.Controls.Add(text);
            levels.Items.AddRange(new object[] { UiText.T("全部", "All"), UiText.T("警告", "Warnings"), UiText.T("错误", "Errors") });
            levels.SelectedIndex = 0;
            bar.Controls.AddRange(new Control[] { sources, levels, search, refresh, export });
            Controls.Add(frame);
            Controls.Add(bar);
            Controls.Add(card);
            sources.SelectedIndexChanged += (s, e) => Render();
            levels.SelectedIndexChanged += (s, e) => Render();
            search.TextChanged += (s, e) => Render();
            refresh.Click += (s, e) => {
                if (service == null) return;
                try { LoadLogs(service, service.ListMods(), force: true); }
                catch (Exception ex) { Status?.Invoke(ex.Message); }
            };
            export.Click += (s, e) => {
                if (service == null) return;
                using (var dialog = new SaveFileDialog { Filter = "ZIP|*.zip", FileName = "Frostrail-diagnostics.zip" })
                {
                    if (dialog.ShowDialog(this) != DialogResult.OK) return;
                    try
                    {
                        var selected = sources.SelectedIndex >= 2 ? new[] { mods[sources.SelectedIndex - 2].Id } : new string[0];
                        service.ExportLogs(dialog.FileName, selected);
                        Status?.Invoke(UiText.T("诊断包已导出。", "Diagnostics exported."));
                    }
                    catch (Exception ex) { Status?.Invoke(ex.Message); }
                }
            };
        }
        // Navigation reuses the existing view. Refresh (or changed files) rereads data, keeping the current filters.
        public void LoadLogs(ManagerService manager, List<ModInfo> installed, LaunchLog parsed = null,
            string selectedMod = null, bool force = false) =>
            Theme.Batch(this, () => Reload(manager, installed, parsed, selectedMod, force));
        void Reload(ManagerService manager, List<ModInfo> installed, LaunchLog parsed, string selectedMod, bool force)
        {
            bool changedGame = service != manager;
            string selected = selectedMod ?? (changedGame ? null : sources.SelectedItem as string);
            if (changedGame)
            {
                launchStamp = sourceStamp = renderedStamp = summaryDocument = textDocument = null;
                force = true;
            }
            service = manager;
            mods = installed;
            loading = true;
            try
            {
                var choices = new[] { UiText.T("上次启动 (UE4SS.log)", "Last launch (UE4SS.log)"),
                    UiText.T("管理器操作 (log.jsonl)", "Manager operations (log.jsonl)") }
                    .Concat(mods.Select(m => m.Id)).ToArray();
                if (!sources.Items.Cast<string>().SequenceEqual(choices))
                {
                    sources.Items.Clear();
                    sources.Items.AddRange(choices);
                }
                sources.SelectedIndex = selected != null && sources.Items.Contains(selected)
                    ? sources.Items.IndexOf(selected) : 0;
            }
            finally { loading = false; }
            var stamp = JsonData.Serialize(mods.Select(m => new { m.Id, m.Entries }))
                + FileStamp.Read(new[] { service.RuntimeLog, service.GameManifest });
            if (force || stamp != launchStamp || parsed != null && parsed != launch)
            {
                launch = parsed ?? service.ReadLaunch(mods);
                launchStamp = stamp;
                launchRevision++;
                var document = new RichTextDocument();
                document.Append("Frostrail Build " + (launch.GameVersion.Length > 0 ? launch.GameVersion : "—")
                    + "    UE4SS " + launch.LoaderVersion + "\n", Theme.Text);
                foreach (var pair in launch.Failures)
                    document.Append("⚠ " + pair.Key + ": " + pair.Value + "\n", Theme.Danger);
                document.Append(UiText.T("已加载：", "Loaded: ") + string.Join(", ", launch.Loaded), Theme.Good);
                var rtf = document.Build(summary.Font);
                if (rtf != summaryDocument) { summary.Rtf = rtf; summaryDocument = rtf; }
            }
            if (force) sourceStamp = null;
            Render();
        }
        public void SelectMod(string id)
        {
            int index = sources.Items.IndexOf(id);
            sources.SelectedIndex = index >= 0 ? index : 0;
        }
        void Render()
        {
            if (loading || service == null || sources.SelectedIndex < 0) return;
            Theme.Batch(text, Fill);
        }
        void Fill()
        {
            try
            {
                string stamp = sources.SelectedIndex == 1 ? FileStamp.Read(new[] { service.LogPath })
                    : launchRevision.ToString() + (sources.SelectedIndex >= 2
                        ? FileStamp.Read(service.ModLogs(mods[sources.SelectedIndex - 2])) : "");
                stamp = sources.Text + "\n" + stamp;
                if (stamp != sourceStamp)
                {
                    entries = sources.SelectedIndex == 0 ? launch.Lines : sources.SelectedIndex == 1
                        ? service.ReadManagerLog() : service.ReadModLogs(mods[sources.SelectedIndex - 2], launch);
                    sourceStamp = stamp;
                    renderedStamp = null;
                }
                var viewStamp = JsonData.Serialize(new { sourceStamp, level = levels.SelectedIndex, search = search.Text });
                if (viewStamp == renderedStamp) return;
                var document = new RichTextDocument();
                foreach (var line in entries)
                {
                    if (levels.SelectedIndex == 1 && line.Level != "warn" || levels.SelectedIndex == 2 && line.Level != "error") continue;
                    if (line.Message.IndexOf(search.Text, StringComparison.OrdinalIgnoreCase) < 0) continue;
                    var prefix = line.Action.Length > 0 ? ActionLabel(line.Action) + " · " : "";
                    document.Append(prefix + line.Message + "\n",
                        line.Level == "error" ? Theme.Danger : line.Level == "warn" ? Theme.Warn : Theme.Text);
                }
                var rtf = document.Build(text.Font);
                // An unchanged view keeps its selection and scroll position, including after explicit refresh.
                if (rtf == textDocument) { renderedStamp = viewStamp; return; }
                text.Rtf = rtf;
                textDocument = rtf;
                renderedStamp = viewStamp;
                text.Select(text.TextLength, 0);
                text.ScrollToCaret();
            }
            catch (Exception ex) { Status?.Invoke(ex.Message); }
        }
        static string ActionLabel(string action)
        {
            switch (action)
            {
                case "install": return UiText.T("安装", "Install");
                case "uninstall": return UiText.T("卸载", "Uninstall");
                case "enable": return UiText.T("启用", "Enable");
                case "disable": return UiText.T("停用", "Disable");
                case "update": return UiText.T("更新", "Update");
                case "export": return UiText.T("导出", "Export");
                default: return action;
            }
        }
    }
}

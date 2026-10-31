using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Text;
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
                try { LoadLogs(service, service.ListMods()); } catch (Exception ex) { Status?.Invoke(ex.Message); }
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
        public void LoadLogs(ManagerService manager, List<ModInfo> installed, LaunchLog parsed = null)
        {
            service = manager;
            mods = installed;
            launch = parsed ?? service.ReadLaunch(mods);
            var selected = sources.SelectedIndex >= 2 && sources.SelectedIndex - 2 < mods.Count
                ? sources.Text : "";
            loading = true;
            try
            {
                sources.Items.Clear();
                sources.Items.Add(UiText.T("上次启动 (UE4SS.log)", "Last launch (UE4SS.log)"));
                sources.Items.Add(UiText.T("管理器操作 (log.jsonl)", "Manager operations (log.jsonl)"));
                foreach (var mod in mods) sources.Items.Add(mod.Id);
                sources.SelectedIndex = selected.Length > 0 && sources.Items.Contains(selected)
                    ? sources.Items.IndexOf(selected) : 0;
            }
            finally { loading = false; }
            summary.Clear();
            summary.AppendText("Frostrail Build " + (launch.GameVersion.Length > 0 ? launch.GameVersion : "—")
                + "    UE4SS " + launch.LoaderVersion + "\n");
            summary.SelectionColor = Theme.Danger;
            foreach (var pair in launch.Failures) summary.AppendText("⚠ " + pair.Key + ": " + pair.Value + "\n");
            summary.SelectionColor = Theme.Good;
            summary.AppendText(UiText.T("已加载：", "Loaded: ") + string.Join(", ", launch.Loaded));
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
            try
            {
                var lines = sources.SelectedIndex == 0 ? launch.Lines : sources.SelectedIndex == 1
                    ? service.ReadManagerLog() : service.ReadModLogs(mods[sources.SelectedIndex - 2], launch);
                var rendered = new StringBuilder();
                var highlights = new List<Tuple<int, int, Color>>();
                foreach (var line in lines)
                {
                    if (levels.SelectedIndex == 1 && line.Level != "warn" || levels.SelectedIndex == 2 && line.Level != "error") continue;
                    if (line.Message.IndexOf(search.Text, StringComparison.OrdinalIgnoreCase) < 0) continue;
                    int start = rendered.Length;
                    if (line.Action.Length > 0) rendered.Append(ActionLabel(line.Action)).Append(" · ");
                    // RichTextBox uses LF character positions, including multiline error messages.
                    rendered.Append(line.Message.Replace("\r\n", "\n").Replace('\r', '\n')).Append('\n');
                    if (line.Level == "warn" || line.Level == "error")
                        highlights.Add(Tuple.Create(start, rendered.Length - start,
                            line.Level == "error" ? Theme.Danger : Theme.Warn));
                }
                // Appending each line forces repeated native layout and blocks the page switch.
                text.Text = rendered.ToString();
                text.SelectAll();
                text.SelectionColor = Theme.Text;
                foreach (var highlight in highlights)
                {
                    text.Select(highlight.Item1, highlight.Item2);
                    text.SelectionColor = highlight.Item3;
                }
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

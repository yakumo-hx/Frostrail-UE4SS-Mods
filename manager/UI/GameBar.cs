using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace Frostrail.ModManager
{
    internal sealed class GameBar : UserControl
    {
        readonly ComboBox games = new ComboBox { Dock = DockStyle.Fill };
        readonly ComboBox languages = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList };
        readonly Label running = new Label { AutoSize = true, Anchor = AnchorStyles.Left, Font = Theme.Body };
        readonly Button browse = Theme.Button(UiText.T("浏览…", "Browse…"));
        // Hidden until a check finds a newer manager on GitHub.
        readonly Button selfUpdate = Theme.Button("", Look.Primary);
        public event Action<string> GameSelected;
        public event Action LanguageSelected;
        public event Action SelfUpdateRequested;
        public string Game => games.Text;
        public GameBar(IEnumerable<string> discovered, string current)
        {
            Height = Theme.S(56);
            Dock = DockStyle.Top;
            BackColor = Theme.Back;
            Theme.StyleCombo(games);
            Theme.StyleCombo(languages);
            languages.Width = Theme.S(110);
            languages.Anchor = AnchorStyles.Right;
            games.Margin = Theme.P(0, 2, 8, 0);
            browse.Anchor = AnchorStyles.Left;
            running.Margin = Theme.P(8, 0, 0, 0);
            selfUpdate.Anchor = AnchorStyles.Right;
            selfUpdate.Visible = false;
            selfUpdate.Click += (s, e) => SelfUpdateRequested?.Invoke();
            var row = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 6, Padding = Theme.P(16, 12, 16, 10) };
            row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Theme.S(150)));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            row.Controls.Add(new Label { Text = UiText.T("游戏", "Game"), AutoSize = true, Anchor = AnchorStyles.Left,
                Font = Theme.Body, ForeColor = Theme.Muted, Margin = Theme.P(0, 0, 10, 0) }, 0, 0);
            foreach (var path in discovered) games.Items.Add(path);
            games.Text = current ?? "";
            row.Controls.Add(games, 1, 0);
            row.Controls.Add(browse, 2, 0);
            row.Controls.Add(running, 3, 0);
            languages.Items.AddRange(new object[] { "简体中文", "English" });
            languages.SelectedIndex = UiText.Chinese ? 0 : 1;
            row.Controls.Add(selfUpdate, 4, 0);
            row.Controls.Add(languages, 5, 0);
            Controls.Add(row);
            Controls.Add(Theme.Rule(DockStyle.Bottom));
            games.SelectionChangeCommitted += (s, e) => GameSelected?.Invoke(games.Text);
            games.Validated += (s, e) => GameSelected?.Invoke(games.Text);
            games.KeyDown += (s, e) => {
                if (e.KeyCode != Keys.Enter) return;
                e.SuppressKeyPress = true;
                GameSelected?.Invoke(games.Text);
            };
            languages.SelectionChangeCommitted += (s, e) => {
                UiText.Chinese = languages.SelectedIndex == 0;
                BeginInvoke(new Action(() => LanguageSelected?.Invoke()));
            };
            browse.Click += (s, e) => {
                var menu = new ContextMenuStrip { Font = Theme.Body };
                menu.Items.Add(UiText.T("选文件夹…", "Choose folder…"), null, (a, b) => {
                    using (var dialog = new FolderBrowserDialog())
                        if (dialog.ShowDialog(this) == DialogResult.OK) Choose(dialog.SelectedPath);
                });
                menu.Items.Add(UiText.T("选游戏 EXE…", "Choose game EXE…"), null, (a, b) => {
                    using (var dialog = new OpenFileDialog { Filter = "EXE|*.exe|All files|*.*" })
                        if (dialog.ShowDialog(this) == DialogResult.OK) Choose(dialog.FileName);
                });
                menu.Closed += (a, b) => BeginInvoke(new Action(menu.Dispose));
                menu.Show(browse, new Point(0, browse.Height));
            };
        }
        void Choose(string path)
        {
            games.Text = path;
            GameSelected?.Invoke(path);
        }
        public void SetBusy(bool busy)
        {
            games.Enabled = !busy;
            browse.Enabled = !busy;
            languages.Enabled = !busy;
            selfUpdate.Enabled = !busy;
        }
        public void ShowSelfUpdate(string version)
        {
            selfUpdate.Text = UiText.T("更新管理器到 ", "Update manager to ") + version;
            selfUpdate.Visible = version != null;
        }
        public void ShowRunning(bool value)
        {
            running.Text = value ? UiText.T("● 游戏运行中", "● Game running") : UiText.T("● 游戏已关闭", "● Game closed");
            running.ForeColor = value ? Theme.Warn : Theme.Good;
        }
    }
}

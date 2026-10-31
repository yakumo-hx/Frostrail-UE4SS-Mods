using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace Frostrail.ModManager
{
    internal sealed class ModList : UserControl
    {
        sealed class Grid : DataGridView
        {
            public Grid() { DoubleBuffered = true; }
        }
        readonly Grid grid = new Grid();
        readonly Button install = Theme.Button(UiText.T("安装 ▾", "Install ▾"), Look.Primary);
        readonly Button update = Theme.Button(UiText.T("检查更新", "Check updates"));
        readonly Button up = Theme.Button("↑"), down = Theme.Button("↓");
        readonly ContextMenuStrip installMenu = new ContextMenuStrip { Font = Theme.Body };
        public event Action<string> Selected;
        public event Action<string, bool> Toggled;
        public event Action LocalInstall, RemoteInstall, UpdateRequested;
        public event Action<string, int> MoveRequested;
        public string SelectedId => grid.CurrentRow?.Tag as string;
        public ModList()
        {
            Dock = DockStyle.Fill;
            BackColor = Theme.Back;
            installMenu.Items.Add(UiText.T("本地 ZIP…", "Local ZIP…"), null, (s, e) => LocalInstall?.Invoke());
            installMenu.Items.Add(UiText.T("GitHub 链接…", "GitHub link…"), null, (s, e) => RemoteInstall?.Invoke());
            install.Click += (s, e) => installMenu.Show(install, new Point(0, install.Height));
            update.Click += (s, e) => UpdateRequested?.Invoke();
            up.Click += (s, e) => MoveRequested?.Invoke(SelectedId, -1);
            down.Click += (s, e) => MoveRequested?.Invoke(SelectedId, 1);
            var tips = new ToolTip();
            tips.SetToolTip(up, UiText.T("加载顺序上移", "Load earlier"));
            tips.SetToolTip(down, UiText.T("加载顺序下移", "Load later"));
            up.Margin = Theme.P(0, 0, 4, 0);
            down.Margin = Padding.Empty;

            // Toolbar: install and update on the left, load-order arrows on the right.
            var tools = new TableLayoutPanel { Dock = DockStyle.Top, Height = Theme.S(52), ColumnCount = 5,
                Padding = Theme.P(12, 10, 12, 8), BackColor = Theme.Back };
            tools.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            tools.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            tools.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            tools.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            tools.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            tools.Controls.Add(install, 0, 0);
            tools.Controls.Add(update, 1, 0);
            tools.Controls.Add(up, 3, 0);
            tools.Controls.Add(down, 4, 0);

            grid.Dock = DockStyle.Fill;
            Theme.StyleGrid(grid);
            grid.ReadOnly = true;
            grid.AllowUserToAddRows = false;
            grid.AllowUserToDeleteRows = false;
            grid.AllowUserToResizeColumns = false;
            grid.MultiSelect = false;
            grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            grid.AutoGenerateColumns = false;
            grid.Columns.Add(new DataGridViewCheckBoxColumn { Name = "Enabled", HeaderText = "",
                AutoSizeMode = DataGridViewAutoSizeColumnMode.None, Width = Theme.S(40) });
            grid.Columns.Add("Name", UiText.T("名称", "Name"));
            grid.Columns.Add("Version", UiText.T("版本", "Version"));
            grid.Columns.Add("State", UiText.T("状态", "Status"));
            grid.Columns[1].FillWeight = 130;
            grid.Columns[2].FillWeight = 45;
            grid.Columns[3].FillWeight = 70;
            grid.Columns[2].DefaultCellStyle.ForeColor = Theme.Muted;
            grid.Columns[2].DefaultCellStyle.SelectionForeColor = Theme.Muted;
            foreach (DataGridViewColumn column in grid.Columns) column.SortMode = DataGridViewColumnSortMode.NotSortable;
            grid.CellContentClick += (s, e) => {
                if (e.RowIndex >= 0 && e.ColumnIndex == 0)
                    Toggled?.Invoke((string)grid.Rows[e.RowIndex].Tag, !(bool)grid.Rows[e.RowIndex].Cells[0].Value);
            };
            grid.SelectionChanged += (s, e) => Selected?.Invoke(SelectedId);

            // A thin frame keeps the list apart from the toolbar and the drop hint.
            var frame = new Panel { Dock = DockStyle.Fill, Padding = Theme.P(12, 0, 12, 0), BackColor = Theme.Back };
            frame.Controls.Add(grid);
            Controls.Add(frame);
            Controls.Add(tools);
            Controls.Add(new DropHint(UiText.T("拖入 ZIP 或文件夹即可安装", "Drop ZIPs or folders here to install")));
        }
        public void Sync(IReadOnlyList<ModInfo> mods, LaunchLog launch, IDictionary<string, UpdateInfo> updates)
        {
            var ids = new HashSet<string>(mods.Select(m => m.Id));
            var byId = mods.ToDictionary(m => m.Id, StringComparer.OrdinalIgnoreCase);
            foreach (var row in grid.Rows.Cast<DataGridViewRow>().ToArray())
                if (!ids.Contains((string)row.Tag)) grid.Rows.Remove(row);
            for (int index = 0; index < mods.Count; index++)
            {
                var mod = mods[index];
                var row = grid.Rows.Cast<DataGridViewRow>().FirstOrDefault(r => (string)r.Tag == mod.Id);
                if (row == null)
                {
                    var n = grid.Rows.Add();
                    row = grid.Rows[n];
                    row.Tag = mod.Id;
                }
                if (row.Index != index)
                {
                    grid.Rows.Remove(row);
                    grid.Rows.Insert(index, row);
                }
                var missing = mod.Manifest.Requires.Where(id => !ids.Contains(id)).ToArray();
                var failure = launch.Failure(mod);
                bool hasUpdate = updates.TryGetValue(mod.Id, out var u) && u.Available;
                var status = missing.Length > 0 ? UiText.T("缺少前置：", "Missing: ") + string.Join(", ", missing)
                    : failure.Length > 0 ? UiText.T("⚠ 启动失败", "⚠ Failed")
                    : hasUpdate ? UiText.T("↑ 可更新 ", "↑ Update ") + u.Version : "";
                var color = missing.Length > 0 ? Theme.Warn : failure.Length > 0 ? Theme.Danger : Theme.Accent;
                object[] values = { mod.Enabled, mod.Name(UiText.Chinese ? "zh" : "en"),
                    mod.Version.Length == 0 ? "—" : mod.Version, status };
                for (int column = 0; column < values.Length; column++)
                    if (!Equals(row.Cells[column].Value, values[column])) row.Cells[column].Value = values[column];
                var state = row.Cells[3];
                if (state.Style.ForeColor != color)
                {
                    state.Style.ForeColor = color;
                    state.Style.SelectionForeColor = color;
                }
                state.ToolTipText = failure;
                // Prerequisites and whether each is installed and enabled, without spending a column on it.
                row.Cells[1].ToolTipText = mod.Manifest.Requires.Count == 0 ? ""
                    : UiText.T("需要：", "Requires: ")
                        + string.Join(", ", mod.Manifest.Requires.Select(id => Requirement(id, byId)));
            }
            var count = updates.Values.Count(u => u.Available);
            update.Text = count == 0 ? UiText.T("检查更新", "Check updates")
                : UiText.T("全部更新", "Update all") + " (" + count + ")";
        }
        static string Requirement(string id, Dictionary<string, ModInfo> installed)
        {
            if (!installed.TryGetValue(id, out var mod)) return id + UiText.T("（未安装）", " (not installed)");
            return mod.Name(UiText.Chinese ? "zh" : "en")
                + (mod.Enabled ? UiText.T("（已启用）", " (enabled)") : UiText.T("（未启用）", " (disabled)"));
        }
        public void SelectId(string id)
        {
            var row = grid.Rows.Cast<DataGridViewRow>().FirstOrDefault(r => (string)r.Tag == id);
            if (row != null) grid.CurrentCell = row.Cells[1];
        }
        public void SetAvailability(bool canWrite, bool busy)
        {
            install.Enabled = canWrite;
            up.Enabled = canWrite;
            down.Enabled = canWrite;
            update.Enabled = !busy;
        }
    }
}

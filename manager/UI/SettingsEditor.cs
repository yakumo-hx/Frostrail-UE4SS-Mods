using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;

namespace Frostrail.ModManager
{
    internal sealed class SettingsEditor : UserControl
    {
        public event Action<string> Status;
        readonly TableLayoutPanel table = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2 };
        readonly List<Control> inputs = new List<Control>();
        ManagerService service;
        SettingsPage page;
        bool loading;
        public SettingsEditor()
        {
            Dock = DockStyle.Top;
            AutoSize = true;
            table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 45));
            table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 55));
            Font = Theme.Body;
            Controls.Add(table);
        }
        static string Local(object value) => JsonData.Local(value, UiText.Chinese ? "zh" : "en");
        public void LoadPage(ManagerService manager, SettingsPage settings)
        {
            service = manager;
            page = settings;
            loading = true;
            // One layout pass for the whole form instead of one per added row.
            table.SuspendLayout();
            try { Fill(); }
            finally
            {
                table.ResumeLayout(true);
                loading = false;
            }
        }
        // Called from the action row above the page; the page is rebuilt from the restored values.
        public void RestoreDefaults()
        {
            service.ResetSettings(page);
            LoadPage(service, page);
        }
        void Fill()
        {
            foreach (Control old in table.Controls.Cast<Control>().ToArray()) old.Dispose();
            table.Controls.Clear();
            table.RowStyles.Clear();
            table.RowCount = 0;
            inputs.Clear();
            string group = null;
            foreach (var field in page.Fields)
            {
                if (Local(field.Group) != group && Local(field.Group).Length > 0)
                {
                    group = Local(field.Group);
                    AddWide(new Label { Text = group, AutoSize = true, Font = Theme.Strong, ForeColor = Theme.Text,
                        Margin = Theme.P(0, 14, 0, 4) });
                }
                var baseline = JsonData.Serialize(page.Value(field.Key));
                Action<object> save = value => {
                    if (loading || baseline == JsonData.Serialize(value)) return;
                    service.WriteSetting(page, field.Key, value);
                    baseline = JsonData.Serialize(value);
                    Status?.Invoke(UiText.T("已保存：", "Saved: ") + Local(field.Label ?? field.Key));
                };
                Control editor = Editor(field, page.Value(field.Key), JsonData.At(page.Defaults, field.Key), save);
                editor.Name = field.Key;
                editor.Margin = Theme.P(0, 4, 0, 4);
                inputs.Add(editor);
                var label = LabelCell(field);
                int row = table.RowCount++;
                table.RowStyles.Add(new RowStyle(SizeType.AutoSize));
                table.Controls.Add(label, 0, row);
                if (editor is CollectionEditor)
                {
                    table.SetColumnSpan(label, 2);
                    AddWide(editor);
                }
                else
                {
                    editor.Anchor = AnchorStyles.Left;
                    table.Controls.Add(editor, 1, row);
                }
            }
        }
        // Name, an F8 badge for live fields, and the author's help text underneath.
        Control LabelCell(SettingField field)
        {
            var cell = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = Theme.P(0, 6, 16, 6),
                MaximumSize = new Size(Theme.S(320), 0) };
            var name = new Label { AutoSize = true, Text = Local(field.Label ?? field.Key), ForeColor = Theme.Text,
                MaximumSize = new Size(Theme.S(270), 0), Margin = Theme.P(0, 3, 6, 0) };
            cell.Controls.Add(name);
            if (field.Live) cell.Controls.Add(Theme.Badge("F8"));
            if (field.Help == null) return cell;
            cell.SetFlowBreak(cell.Controls[cell.Controls.Count - 1], true);
            cell.Controls.Add(new Label { AutoSize = true, Text = Local(field.Help), ForeColor = Theme.Muted, Font = Theme.Small,
                MaximumSize = new Size(Theme.S(310), 0), Margin = Theme.P(0, 2, 0, 0) });
            return cell;
        }
        void AddWide(Control control)
        {
            int row = table.RowCount++;
            table.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            table.Controls.Add(control, 0, row);
            table.SetColumnSpan(control, 2);
        }
        void Try(Action action)
        {
            try { action(); } catch (Exception e) { Status?.Invoke(e.Message); }
        }
        Control Editor(SettingField field, object value, object defaults, Action<object> save)
        {
            var kind = field.Kind(defaults);
            if (kind == "bool")
            {
                var box = new CheckBox { Checked = JsonData.Bool(value), AutoSize = true, Text = "" };
                box.CheckedChanged += (s, e) => Try(() => save(box.Checked));
                return box;
            }
            if (kind == "number")
            {
                // Show the precision the author wrote: 60 stays "60", 0.25 shows two decimals.
                int places = field.Integer ? 0 : new object[] { defaults, value, field.Step }.Max(x => Decimals(x));
                var number = new NumericUpDown { Minimum = field.Min ?? decimal.MinValue,
                    Maximum = field.Max ?? decimal.MaxValue, DecimalPlaces = places,
                    Increment = field.Step ?? 1, Width = Theme.S(140), BorderStyle = BorderStyle.FixedSingle };
                number.Value = Math.Max(number.Minimum, Math.Min(number.Maximum, Convert.ToDecimal(value ?? defaults)));
                number.ValueChanged += (s, e) => Try(() => save(number.Value));
                number.Validated += (s, e) => Try(() => save(number.Value));
                number.KeyDown += (s, e) => {
                    if (e.KeyCode == Keys.Enter) { number.Validate(); Try(() => save(number.Value)); e.SuppressKeyPress = true; }
                };
                return number;
            }
            if (kind == "choice")
            {
                var combo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = Theme.S(220) };
                Theme.StyleCombo(combo);
                foreach (var option in field.Options)
                {
                    var entry = new Choice { Value = option is Dictionary<string, object> ? JsonData.Get(option, "value") : option,
                        Label = option is Dictionary<string, object> ? Local(JsonData.Get(option, "label", JsonData.Get(option, "value"))) : Local(option) };
                    combo.Items.Add(entry);
                    if (JsonData.Serialize(entry.Value) == JsonData.Serialize(value)) combo.SelectedItem = entry;
                }
                combo.SelectionChangeCommitted += (s, e) => Try(() => save(((Choice)combo.SelectedItem).Value));
                return combo;
            }
            if (kind == "list" || kind == "map")
            {
                var collection = new CollectionEditor(field, value, defaults);
                collection.Changed += () => Try(() => {
                    var result = collection.ReadValue();
                    Status?.Invoke("");
                    save(result);
                });
                collection.Error += message => Status?.Invoke(message);
                return collection;
            }
            var text = new TextBox { Text = JsonData.Text(value), BorderStyle = BorderStyle.FixedSingle,
                Width = Theme.S(kind == "color" ? 110 : 260) };
            Action commit = () => Try(() => {
                var result = text.Text;
                if (kind == "color" && (result.Length != 6 || !result.All(Uri.IsHexDigit)))
                    throw new ArgumentException(UiText.T("颜色需要六位十六进制值。", "Enter six hexadecimal color digits."));
                save(result);
            });
            text.Validated += (s, e) => commit();
            text.KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { commit(); e.SuppressKeyPress = true; } };
            if (kind != "color") return text;
            // A swatch next to the hex value, updated while typing.
            var swatch = new Panel { Size = new Size(Theme.S(22), Theme.S(22)), BorderStyle = BorderStyle.FixedSingle,
                Margin = Theme.P(0, 1, 8, 0) };
            Action paint = () => {
                if (text.Text.Length == 6 && text.Text.All(Uri.IsHexDigit))
                    swatch.BackColor = Color.FromArgb(Convert.ToInt32(text.Text, 16) | unchecked((int)0xFF000000));
            };
            paint();
            text.TextChanged += (s, e) => paint();
            text.Margin = Padding.Empty;
            var pair = new FlowLayoutPanel { AutoSize = true, WrapContents = false };
            pair.Controls.Add(swatch);
            pair.Controls.Add(text);
            return pair;
        }
        static int Decimals(object value)
        {
            if (!(value is decimal || value is double || value is float)) return 0;
            int scale = (decimal.GetBits(Convert.ToDecimal(value, CultureInfo.InvariantCulture))[3] >> 16) & 0xFF;
            return Math.Min(6, scale);
        }
        public void SetReadOnly(bool value) { foreach (var input in inputs) input.Enabled = !value; }
        sealed class Choice
        {
            public object Value;
            public string Label;
            public override string ToString() => Label;
        }
    }
    internal sealed class CollectionEditor : UserControl
    {
        readonly DataGridView grid = new DataGridView { Dock = DockStyle.Fill, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            AllowUserToAddRows = false, AllowUserToDeleteRows = false, RowHeadersVisible = false };
        readonly SettingField field;
        readonly object defaults;
        readonly bool map, objects;
        readonly List<string> keys = new List<string>();
        public event Action Changed;
        public event Action<string> Error;
        static string Local(object value) => JsonData.Local(value, UiText.Chinese ? "zh" : "en");
        static string Display(object value) => value is System.Collections.IEnumerable && !(value is string)
            ? JsonData.Serialize(value) : JsonData.Text(value);
        public CollectionEditor(SettingField spec, object value, object defaultValue)
        {
            field = spec;
            defaults = defaultValue;
            map = spec.Kind(defaultValue) == "map";
            objects = !map && (spec.Columns.Count > 0 || JsonData.List(defaultValue).Any(x => x is Dictionary<string, object>));
            Height = Theme.S(220);
            Dock = DockStyle.Top;
            Theme.StyleGrid(grid);
            grid.RowTemplate.Height = Theme.S(30);
            grid.CellBorderStyle = DataGridViewCellBorderStyle.Single;
            grid.BorderStyle = BorderStyle.FixedSingle;
            var bar = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = Theme.S(42), Padding = Theme.P(0, 8, 0, 0) };
            var add = Theme.Button(UiText.T("添加一行", "Add row"));
            var remove = Theme.Button(UiText.T("删除选中行", "Remove row"));
            bar.Controls.Add(add);
            bar.Controls.Add(remove);
            Controls.Add(grid);
            Controls.Add(bar);
            if (map)
            {
                grid.Columns.Add("key", UiText.T("名称", "Name"));
                grid.Columns.Add("value", UiText.T("值", "Value"));
                foreach (var pair in JsonData.Map(value)) grid.Rows.Add(pair.Key, Display(pair.Value));
            }
            else if (objects)
            {
                keys.AddRange(field.Columns.Select(c => c.Key));
                foreach (var row in JsonData.List(defaultValue).Concat(JsonData.List(value)))
                    foreach (var key in JsonData.Map(row).Keys) if (!keys.Contains(key)) keys.Add(key);
                foreach (var key in keys) grid.Columns.Add(key, Local(field.Columns.FirstOrDefault(c => c.Key == key)?.Label ?? key));
                foreach (var item in JsonData.List(value))
                {
                    int n = grid.Rows.Add(keys.Select(k => (object)Display(JsonData.Get(item, k))).ToArray());
                    grid.Rows[n].Tag = item;
                }
            }
            else
            {
                grid.Columns.Add("value", UiText.T("值", "Value"));
                foreach (var item in JsonData.List(value)) grid.Rows.Add(Display(item));
            }
            add.Click += (s, e) => {
                int n = grid.Rows.Add();
                grid.CurrentCell = grid.Rows[n].Cells[0];
                grid.BeginEdit(true);
            };
            remove.Click += (s, e) => {
                if (grid.CurrentRow == null) return;
                grid.Rows.Remove(grid.CurrentRow);
                Changed?.Invoke();
            };
            grid.CellEndEdit += (s, e) => Changed?.Invoke();
            grid.DataError += (s, e) => { e.ThrowException = false; Error?.Invoke(e.Exception.Message); };
        }
        object ConvertValue(object text, object sample, SettingField spec, string explicitType = "")
        {
            var value = JsonData.Text(text);
            if (JsonData.IsNumber(sample) || explicitType == "number")
            {
                var number = decimal.Parse(value, NumberStyles.Float, CultureInfo.InvariantCulture);
                if (spec.Integer && decimal.Truncate(number) != number) throw new ArgumentException(UiText.T("请输入整数。", "Enter an integer."));
                if (spec.Min.HasValue && number < spec.Min || spec.Max.HasValue && number > spec.Max)
                    throw new ArgumentException(UiText.T("数值超出作者规定的范围。", "Value is outside the author's range."));
                return number;
            }
            if (sample is bool || explicitType == "bool") return bool.Parse(value);
            if (sample is System.Collections.IEnumerable && !(sample is string)) return JsonData.Parse(value);
            return value;
        }
        public object ReadValue()
        {
            if (map)
            {
                var result = new Dictionary<string, object>();
                foreach (DataGridViewRow row in grid.Rows)
                {
                    var key = JsonData.Text(row.Cells[0].Value);
                    result.Add(key, ConvertValue(row.Cells[1].Value,
                        JsonData.Get(defaults, key, JsonData.Map(defaults).Values.FirstOrDefault()), field, field.ValueType));
                }
                return result;
            }
            var list = new List<object>();
            foreach (DataGridViewRow row in grid.Rows)
            {
                if (objects)
                {
                    var sample = JsonData.List(defaults).FirstOrDefault();
                    var item = new Dictionary<string, object>(JsonData.Map(row.Tag));
                    for (int i = 0; i < keys.Count; i++)
                    {
                        var column = field.Columns.FirstOrDefault(c => c.Key == keys[i]) ?? new SettingField();
                        var baseline = JsonData.Get(sample, keys[i]);
                        if (JsonData.IsNumber(baseline) && string.IsNullOrWhiteSpace(JsonData.Text(row.Cells[i].Value)))
                            throw new ArgumentException(UiText.T(
                                "第 " + (row.Index + 1) + " 行：请填写“" + Local(column.Label ?? keys[i]) + "”，填完后自动保存。",
                                "Row " + (row.Index + 1) + ": enter " + Local(column.Label ?? keys[i]) + "; the row saves when complete."));
                        item[keys[i]] = ConvertValue(row.Cells[i].Value, baseline, column);
                    }
                    list.Add(item);
                }
                else list.Add(ConvertValue(row.Cells[0].Value, JsonData.List(defaults).FirstOrDefault(), field));
            }
            return list;
        }
    }
}

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Frostrail.ModManager
{
    internal enum Look { Secondary, Primary, Danger }

    // One place for colors, fonts and sizes, so every control looks like part of the same window.
    internal static class Theme
    {
        public static readonly Color Back = Color.White;
        public static readonly Color Side = Color.FromArgb(247, 248, 250);
        public static readonly Color Line = Color.FromArgb(228, 231, 235);
        public static readonly Color Border = Color.FromArgb(205, 210, 217);
        public static readonly Color Text = Color.FromArgb(31, 35, 40);
        public static readonly Color Muted = Color.FromArgb(99, 108, 118);
        public static readonly Color Accent = Color.FromArgb(37, 99, 235);
        public static readonly Color AccentDark = Color.FromArgb(29, 78, 216);
        public static readonly Color AccentSoft = Color.FromArgb(232, 240, 254);
        public static readonly Color Warn = Color.FromArgb(154, 103, 0);
        public static readonly Color WarnSoft = Color.FromArgb(255, 248, 230);
        public static readonly Color Danger = Color.FromArgb(207, 34, 46);
        public static readonly Color DangerSoft = Color.FromArgb(255, 238, 238);
        public static readonly Color Good = Color.FromArgb(26, 127, 55);

        // The process is system-DPI aware; fonts scale by themselves, pixel sizes go through S().
        static readonly float scale = ReadScale();
        static float ReadScale()
        {
            using (var g = Graphics.FromHwnd(IntPtr.Zero)) return g.DpiX / 96f;
        }
        public static int S(int pixels) => (int)Math.Round(pixels * scale);
        public static Padding P(int left, int top, int right, int bottom) => new Padding(S(left), S(top), S(right), S(bottom));

        // YaHei UI covers Chinese and Latin text in one face; Segoe UI is the fallback.
        static readonly string family = PickFamily();
        static string PickFamily()
        {
            using (var font = new Font("Microsoft YaHei UI", 9f)) return font.Name == "Microsoft YaHei UI" ? font.Name : "Segoe UI";
        }
        public static readonly Font Body = new Font(family, 9.5f);
        public static readonly Font Small = new Font(family, 8.5f);
        public static readonly Font Strong = new Font(family, 9.5f, FontStyle.Bold);
        public static readonly Font Heading = new Font(family, 11f, FontStyle.Bold);
        public static readonly Font Title = new Font(family, 15f, FontStyle.Bold);
        public static readonly Font Mono = new Font("Consolas", 9.5f);

        public static Button Button(string text, Look look = Look.Secondary)
        {
            var button = new Button { Text = text, AutoSize = true, FlatStyle = FlatStyle.Flat, Font = Body,
                UseVisualStyleBackColor = false, Cursor = Cursors.Hand, Padding = P(8, 0, 8, 0),
                MinimumSize = new Size(0, S(32)), Margin = P(0, 0, 8, 0) };
            button.FlatAppearance.BorderSize = 1;
            if (look == Look.Primary)
            {
                button.BackColor = Accent;
                button.ForeColor = Color.White;
                button.FlatAppearance.BorderColor = Accent;
                button.FlatAppearance.MouseOverBackColor = AccentDark;
                button.FlatAppearance.MouseDownBackColor = AccentDark;
            }
            else
            {
                button.BackColor = Back;
                button.ForeColor = look == Look.Danger ? Danger : Text;
                button.FlatAppearance.BorderColor = Border;
                button.FlatAppearance.MouseOverBackColor = look == Look.Danger ? DangerSoft : Side;
                button.FlatAppearance.MouseDownBackColor = Line;
            }
            return button;
        }

        // A one-pixel divider, docked against the area it separates.
        public static Control Rule(DockStyle dock) => new Panel { Dock = dock, Height = 1, Width = 1, BackColor = Line };

        // Tinted note with a colored bar on the left (author notices, launch failures).
        public static Label Note(string text, Color back, Color bar)
        {
            var label = new Label { Text = text, AutoSize = true, BackColor = back, ForeColor = Text, Font = Body,
                Padding = P(14, 10, 12, 10), Tag = "wide" };
            label.Paint += (s, e) => {
                using (var brush = new SolidBrush(bar)) e.Graphics.FillRectangle(brush, 0, 0, S(3), label.Height);
            };
            return label;
        }

        public static Label Badge(string text) => new Label { Text = text, AutoSize = true, Font = Small,
            ForeColor = Accent, BackColor = AccentSoft, Padding = P(5, 1, 5, 1), Margin = P(0, 3, 0, 0) };

        [DllImport("user32.dll")]
        static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")]
        static extern bool RedrawWindow(IntPtr window, IntPtr rect, IntPtr region, uint flags);
        const int SetRedraw = 0x000B;
        const uint RedrawAll = 0x0001 | 0x0004 | 0x0080 | 0x0100 | 0x0400; // INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW|FRAME

        // Rebuilding a page creates and disposes many child windows. Without this, each one paints on its own
        // as the message queue drains: color swatches first, text later, old pixels in between.
        // Redraw stays off for the whole subtree during the change, then everything paints in one pass.
        public static void Batch(Control control, Action change)
        {
            bool live = control.IsHandleCreated && control.Visible;
            if (live) SendMessage(control.Handle, SetRedraw, IntPtr.Zero, IntPtr.Zero);
            try { change(); }
            finally
            {
                if (live)
                {
                    SendMessage(control.Handle, SetRedraw, (IntPtr)1, IntPtr.Zero);
                    RedrawWindow(control.Handle, IntPtr.Zero, IntPtr.Zero, RedrawAll);
                }
            }
        }

        public static void StyleCombo(ComboBox combo)
        {
            combo.Font = Body;
        }

        public static void StyleGrid(DataGridView grid)
        {
            grid.BackgroundColor = Back;
            grid.BorderStyle = BorderStyle.None;
            grid.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
            grid.GridColor = Line;
            grid.EnableHeadersVisualStyles = false;
            grid.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None;
            grid.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing;
            grid.ColumnHeadersHeight = S(32);
            grid.ColumnHeadersDefaultCellStyle = new DataGridViewCellStyle { BackColor = Back, ForeColor = Muted,
                Font = Small, SelectionBackColor = Back, SelectionForeColor = Muted, Padding = P(6, 0, 4, 0) };
            grid.DefaultCellStyle = new DataGridViewCellStyle { BackColor = Back, ForeColor = Text, Font = Body,
                SelectionBackColor = AccentSoft, SelectionForeColor = Text, Padding = P(6, 0, 4, 0) };
            grid.RowHeadersVisible = false;
            grid.AllowUserToResizeRows = false;
            grid.RowTemplate.Height = S(36);
        }
    }

    // Page switcher drawn as text with an underline; the native tab strip looked out of place.
    internal sealed class HeaderTabs : Control
    {
        readonly string[] items;
        int selected;
        public event Action<int> Changed;
        public HeaderTabs(params string[] labels)
        {
            items = labels;
            Dock = DockStyle.Top;
            Height = Theme.S(40);
            BackColor = Theme.Back;
            Font = Theme.Body;
            Cursor = Cursors.Hand;
            DoubleBuffered = true;
            ResizeRedraw = true;
        }
        public int Selected
        {
            get => selected;
            set { selected = value; Invalidate(); }
        }
        Rectangle[] Slots()
        {
            var slots = new Rectangle[items.Length];
            int x = Theme.S(12);
            for (int i = 0; i < items.Length; i++)
            {
                int width = TextRenderer.MeasureText(items[i], Theme.Strong).Width + Theme.S(20);
                slots[i] = new Rectangle(x, 0, width, Height);
                x += width + Theme.S(4);
            }
            return slots;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var slots = Slots();
            for (int i = 0; i < items.Length; i++)
            {
                bool on = i == selected;
                TextRenderer.DrawText(e.Graphics, items[i], on ? Theme.Strong : Theme.Body, slots[i],
                    on ? Theme.Text : Theme.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                if (!on) continue;
                using (var brush = new SolidBrush(Theme.Accent))
                    e.Graphics.FillRectangle(brush, slots[i].X + Theme.S(8), Height - Theme.S(3), slots[i].Width - Theme.S(16), Theme.S(3));
            }
            using (var pen = new Pen(Theme.Line)) e.Graphics.DrawLine(pen, 0, Height - 1, Width, Height - 1);
        }
        protected override void OnMouseClick(MouseEventArgs e)
        {
            base.OnMouseClick(e);
            int hit = Array.FindIndex(Slots(), r => r.Contains(e.Location));
            if (hit < 0 || hit == selected) return;
            Selected = hit;
            Changed?.Invoke(hit);
        }
    }

    // TabControl kept only as a page container; its own tab strip is hidden (TCM_ADJUSTRECT).
    internal sealed class PageHost : TabControl
    {
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x1328 && !DesignMode) { m.Result = (IntPtr)1; return; }
            base.WndProc(ref m);
        }
    }

    // Dashed drop target hint under the mod list.
    internal sealed class DropHint : Control
    {
        public DropHint(string text)
        {
            Text = text;
            Dock = DockStyle.Bottom;
            Height = Theme.S(64);
            Font = Theme.Body;
            ForeColor = Theme.Muted;
            BackColor = Theme.Back;
            DoubleBuffered = true;
            ResizeRedraw = true;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var box = new Rectangle(Theme.S(12), Theme.S(10), Width - Theme.S(24) - 1, Height - Theme.S(20) - 1);
            using (var pen = new Pen(Theme.Border) { DashStyle = DashStyle.Dash }) e.Graphics.DrawRectangle(pen, box);
            TextRenderer.DrawText(e.Graphics, Text, Font, box, ForeColor,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }
}

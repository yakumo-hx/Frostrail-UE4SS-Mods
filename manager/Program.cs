using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace Frostrail.ModManager
{
    internal static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            if (args.Any(a => new[] { "--list", "--install", "--enable", "--disable", "--uninstall", "--update", "--export-log" }.Contains(a)))
            { Environment.ExitCode = CommandLine.Run(args); return; }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            string game = null;
            for (int i = 0; i < args.Length; i++) if (args[i] == "--game" && i + 1 < args.Length) game = args[++i];
            if (game == null && args.Length > 0 && !args[0].StartsWith("--")) game = args[0];
            using (var icon = LoadIcon())
            using (var window = new MainForm(game, CommandLine.Value(args, "--ui-data")))
            {
                if (icon != null) window.Icon = icon;
                Application.Run(window);
            }
        }

        // The whole ICO, not the single 32 px frame ExtractAssociatedIcon returns,
        // so the title bar, taskbar and Alt+Tab each get a size drawn for them.
        static Icon LoadIcon()
        {
            using (var stream = typeof(Program).Assembly.GetManifestResourceStream("Frostrail.ModManager.Manager.ico"))
                return stream == null ? null : new Icon(stream);
        }
    }
}

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
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
            var exe = Application.ExecutablePath;
            // After a self-update the previous copy may still be exiting; retry briefly, then leave it for next start.
            Task.Run(async () => {
                for (int i = 0; i < 10 && File.Exists(exe + ".old"); i++)
                {
                    ManagerService.RemoveOldManager(exe);
                    await Task.Delay(500);
                }
            });
            bool restart;
            string game = null;
            for (int i = 0; i < args.Length; i++) if (args[i] == "--game" && i + 1 < args.Length) game = args[++i];
            if (game == null && args.Length > 0 && !args[0].StartsWith("--")) game = args[0];
            using (var icon = LoadIcon())
            using (var window = new MainForm(game, CommandLine.Value(args, "--ui-data")))
            {
                if (icon != null) window.Icon = icon;
                Application.Run(window);
                restart = window.RestartRequested;
            }
            // The window saved its preferences while closing, so the new copy reads them complete.
            if (restart) Process.Start(exe, string.Join(" ", args.Select(Quote)));
        }
        static string Quote(string arg) => "\"" + (arg.EndsWith("\\") ? arg + "\\" : arg).Replace("\"", "\\\"") + "\"";

        // The whole ICO, not the single 32 px frame ExtractAssociatedIcon returns,
        // so the title bar, taskbar and Alt+Tab each get a size drawn for them.
        static Icon LoadIcon()
        {
            using (var stream = typeof(Program).Assembly.GetManifestResourceStream("Frostrail.ModManager.Manager.ico"))
                return stream == null ? null : new Icon(stream);
        }
    }
}

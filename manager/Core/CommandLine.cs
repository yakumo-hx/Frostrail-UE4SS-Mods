using System;
using System.Linq;

namespace Frostrail.ModManager
{
    public static class CommandLine
    {
        public static string Value(string[] args, string key)
        {
            int n = Array.IndexOf(args, key);
            return n >= 0 && n + 1 < args.Length ? args[n + 1] : null;
        }
        public static int Run(string[] args)
        {
            try
            {
                var service = new ManagerService(Value(args, "--game"));
                if (Value(args, "--install") is string install) service.InstallPackage(install, !args.Contains("--disabled"));
                if (Value(args, "--enable") is string enable) service.SetEnabled(enable, true);
                if (Value(args, "--disable") is string disable) service.SetEnabled(disable, false);
                if (Value(args, "--uninstall") is string remove) service.Uninstall(remove, args.Contains("--keep-config"));
                if (Value(args, "--export-log") is string export) service.ExportLogs(export);
                if (Value(args, "--update") is string update)
                {
                    var info = service.CheckUpdatesAsync().GetAwaiter().GetResult().First(u => u.Id == update);
                    if (info.Error.Length > 0) throw new Exception(info.Error);
                    if (info.Available) service.InstallRemoteAsync(info).GetAwaiter().GetResult();
                }
                var output = new { success = true, mods = service.ListMods().Select(m => m.Data()).ToArray() };
                if (Value(args, "--output") is string file) JsonData.Save(file, output);
                Console.WriteLine(JsonData.Serialize(output));
                return 0;
            }
            catch (Exception e)
            {
                if (Value(args, "--output") is string file) JsonData.Save(file, new { success = false, error = e.Message });
                Console.Error.WriteLine(e);
                return 1;
            }
        }
    }
}

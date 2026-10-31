using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Frostrail.ModManager
{
    public sealed class LogEntry
    {
        public string Time = "", Mod = "", Level = "info", Action = "", Message = "";
        public object Data() => new { time = Time, mod = Mod, level = Level, action = Action, message = Message };
    }
    public sealed class LaunchLog
    {
        public string LoaderVersion = "", GameVersion = "", EngineVersion = "";
        public DateTime Started;
        public List<string> Loaded = new List<string>();
        public List<LogEntry> Lines = new List<LogEntry>();
        public Dictionary<string, string> Failures = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public static LaunchLog Parse(string text, IEnumerable<ModInfo> mods, DateTime fallback)
        {
            var result = new LaunchLog { Started = fallback };
            var lines = text.Replace("\r", "").Split('\n');
            var start = Array.FindLastIndex(lines, l => l.Contains("UE4SS - v"));
            var owners = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var mod in mods) foreach (var entry in mod.Entries) owners[entry] = mod.Id;
            LogEntry previous = null;
            foreach (var line in lines.Skip(Math.Max(0, start)))
            {
                if (line.Length == 0) continue;
                var stamp = Regex.Match(line, @"^\[([^\]]+)\]");
                var loader = Regex.Match(line, @"UE4SS - v([^\s]+)");
                if (loader.Success)
                {
                    result.LoaderVersion = loader.Groups[1].Value;
                    if (DateTime.TryParse(stamp.Groups[1].Value, out var time)) result.Started = time.ToUniversalTime();
                }
                if (line.Contains("Unreal Engine version")) result.EngineVersion = line;
                var loaded = Regex.Match(line,
                    @"(?:Starting (?:Lua|C\+\+) mod '([^']+)'|Mod '([^']+)' has enabled\.txt, starting mod\.)");
                var failed = Regex.Match(line,
                    @"Failed to execute main script:.*[\\/]Mods[\\/]([^\\/]+)[\\/]Scripts[\\/]main\.lua", RegexOptions.IgnoreCase);
                var tag = Regex.Match(line, @"\[Lua\]\s*\[([^\]]+)\]");
                var entry = loaded.Success ? loaded.Groups[1].Value + loaded.Groups[2].Value
                    : failed.Success ? failed.Groups[1].Value : tag.Groups[1].Value;
                var owner = owners.TryGetValue(entry, out var id) ? id : entry;
                if (loaded.Success && !result.Loaded.Contains(owner)) result.Loaded.Add(owner);
                bool error = failed.Success || (tag.Success && line.Contains("ERROR"));
                // Lua traceback lines belong to the immediately preceding error, until another timestamped event.
                if (previous != null && !Regex.IsMatch(line, @"^\[\d") && !loaded.Success && !tag.Success && !failed.Success)
                {
                    previous.Message += Environment.NewLine + line;
                    continue;
                }
                var item = new LogEntry {
                    Time = stamp.Groups[1].Value, Mod = owner,
                    Level = error ? "error" : line.IndexOf("WARN", StringComparison.OrdinalIgnoreCase) >= 0 ? "warn" : "info",
                    Message = line
                };
                result.Lines.Add(item);
                if (error && !result.Failures.ContainsKey(owner)) result.Failures[owner] = line;
                previous = error ? item : null;
            }
            return result;
        }
        public string Failure(ModInfo mod)
        {
            if (DateTime.TryParse(mod.Changed, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var changed)
                && changed.ToUniversalTime() > Started) return "";
            return Failures.TryGetValue(mod.Id, out var text) ? text : "";
        }
    }

    public sealed partial class ManagerService
    {
        public string RuntimeLog => Path.Combine(ModsRoot, "..", "UE4SS.log");
        void Log(string action, string level, string mod, string message)
        {
            Directory.CreateDirectory(DataRoot);
            var item = new LogEntry { Time = DateTime.UtcNow.ToString("o"), Mod = mod,
                Action = action, Level = level, Message = message };
            // Update checks log from a background thread while an install may be appending too.
            var line = JsonData.Serialize(item.Data()) + Environment.NewLine;
            lock (sync) File.AppendAllText(LogPath, line, new UTF8Encoding(false));
        }
        public static string Tail(string path, int bytes = 5 * 1024 * 1024)
        {
            if (!File.Exists(path)) return "";
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                bool partial = stream.Length > bytes;
                if (partial) stream.Seek(-bytes, SeekOrigin.End);
                using (var reader = new StreamReader(stream, Encoding.UTF8, true))
                {
                    if (partial) reader.ReadLine();
                    return reader.ReadToEnd();
                }
            }
        }
        public LaunchLog ReadLaunch(IEnumerable<ModInfo> mods)
        {
            var launch = LaunchLog.Parse(Tail(RuntimeLog), mods,
                File.Exists(RuntimeLog) ? File.GetLastWriteTimeUtc(RuntimeLog) : DateTime.MinValue);
            var manifest = Path.GetFullPath(Path.Combine(GameRoot, "../../appmanifest_5090080.acf"));
            if (File.Exists(manifest))
                launch.GameVersion = Regex.Match(File.ReadAllText(manifest), "\"buildid\"\\s+\"([^\"]+)\"").Groups[1].Value;
            return launch;
        }
        public List<LogEntry> ReadManagerLog()
        {
            var result = new List<LogEntry>();
            foreach (var line in Tail(LogPath).Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                object x;
                // A line cut off by a crash should not hide the rest of the log.
                try { x = JsonData.Parse(line); }
                catch (Exception e) when (e is ArgumentException || e is InvalidOperationException) { continue; }
                result.Add(new LogEntry {
                    Time = JsonData.Text(JsonData.Get(x, "time")), Level = JsonData.Text(JsonData.Get(x, "level")),
                    Mod = JsonData.Text(JsonData.Get(x, "mod")), Action = JsonData.Text(JsonData.Get(x, "action")),
                    Message = JsonData.Text(JsonData.Get(x, "message"))
                });
            }
            return result;
        }
        public IEnumerable<string> ModLogs(ModInfo mod) => mod.Entries.Select(e => Target(NativeMods + e))
            .Where(Directory.Exists).SelectMany(dir => Directory.GetFiles(dir, "*.log", SearchOption.AllDirectories));
        public List<LogEntry> ReadModLogs(ModInfo mod, LaunchLog launch)
        {
            var result = launch.Lines.Where(l => l.Mod.Equals(mod.Id, StringComparison.OrdinalIgnoreCase)).ToList();
            foreach (var file in ModLogs(mod)) foreach (var line in Tail(file).Split('\n'))
                if (line.Length > 0) result.Add(new LogEntry { Mod = mod.Id, Message = line,
                    Level = line.Contains("ERROR") ? "error" : "info" });
            return result;
        }
        string Redact(string text)
        {
            foreach (var path in new[] { GameRoot, Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) })
            {
                if (path.Length == 0) continue;
                var replacement = path == GameRoot ? "<GAME>" : "<USER>";
                foreach (var spelling in new[] { path, path.Replace("\\", "\\\\"), path.Replace('\\', '/') })
                    text = Regex.Replace(text, Regex.Escape(spelling), replacement, RegexOptions.IgnoreCase);
            }
            return text;
        }
        public void ExportLogs(string zip, IEnumerable<string> selectedIds = null)
        {
            var mods = ListMods();
            var launch = ReadLaunch(mods);
            var selected = new HashSet<string>(selectedIds ?? new string[0], StringComparer.OrdinalIgnoreCase);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(zip)));
            using (var archive = new ZipArchive(File.Create(zip), ZipArchiveMode.Create))
            {
                Action<string, string> add = (name, text) => {
                    using (var writer = new StreamWriter(archive.CreateEntry(name).Open(), new UTF8Encoding(false)))
                        writer.Write(Redact(text));
                };
                add("summary.json", JsonData.Serialize(new {
                    game = launch.GameVersion, engine = launch.EngineVersion, ue4ss = launch.LoaderVersion, loaded = launch.Loaded,
                    mods = mods.Select(m => new { id = m.Id, version = m.Version, enabled = m.Enabled,
                        failure = launch.Failure(m) })
                }));
                add("log.jsonl", Tail(LogPath));
                add("UE4SS.log", Tail(RuntimeLog));
                foreach (var mod in mods.Where(m => selected.Contains(m.Id))) foreach (var file in ModLogs(mod))
                    add("mods/" + FileOps.Relative(ModsRoot, file), Tail(file));
            }
            Log("export", "info", "manager", "Diagnostic ZIP exported.");
        }
    }
}

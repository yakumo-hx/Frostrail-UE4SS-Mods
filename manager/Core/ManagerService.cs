using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

namespace Frostrail.ModManager
{
    public sealed partial class ManagerService
    {
        public const string NativeMods = "Frostrail/Binaries/Win64/ue4ss/Mods/";
        const string Begin = "; FrostrailModManager begin", End = "; FrostrailModManager end";
        readonly object sync = new object();
        readonly StateStore store;
        public string GameRoot { get; }
        public string DataRoot { get; }
        public string ModsRoot => Path.Combine(GameRoot, NativeMods.Replace('/', Path.DirectorySeparatorChar));
        public string LogPath => Path.Combine(DataRoot, "log.jsonl");
        public string WorkRoot => Path.Combine(DataRoot, "work");
        public bool GameRunning { get; private set; }
        public string LastResult { get; private set; } = "";
        public ManagerService(string gameRoot)
        {
            GameRoot = NormalizeGameRoot(gameRoot);
            DataRoot = Path.Combine(GameRoot, "FrostrailModData");
            store = new StateStore(DataRoot);
            RefreshGameRunning();
            if (File.Exists(LogPath))
                File.WriteAllLines(LogPath, File.ReadLines(LogPath).Reverse().Take(2000).Reverse().ToArray());
        }
        public static string NormalizeGameRoot(string value)
        {
            var path = Path.GetFullPath(value.Trim().Trim('"'));
            if (File.Exists(path)) path = Path.GetDirectoryName(path);
            for (; path != null; path = Path.GetDirectoryName(path))
                if (File.Exists(Path.Combine(path, "Frostrail/Binaries/Win64/Frostrail-Win64-Shipping.exe")))
                    return path.TrimEnd('\\', '/');
            throw new DirectoryNotFoundException(UiText.T("这里找不到 Frostrail。请选择游戏目录或游戏 EXE。",
                "Frostrail was not found here. Select the game directory or executable."));
        }
        public static List<string> DiscoverGames()
        {
            var libraries = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))
            {
                var steam = Convert.ToString(key?.GetValue("SteamPath"));
                if (!string.IsNullOrEmpty(steam)) libraries.Add(steam);
            }
            libraries.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam"));
            foreach (var root in libraries.ToArray())
            {
                var file = Path.Combine(root, "steamapps/libraryfolders.vdf");
                if (!File.Exists(file)) continue;
                foreach (Match match in Regex.Matches(File.ReadAllText(file), "\"path\"\\s+\"([^\"]+)\""))
                    libraries.Add(match.Groups[1].Value.Replace("\\\\", "\\"));
            }
            var result = new List<string>();
            foreach (var root in libraries)
            {
                var apps = Path.Combine(root, "steamapps");
                if (!Directory.Exists(apps)) continue;
                foreach (var file in Directory.GetFiles(apps, "appmanifest_*.acf"))
                {
                    var match = Regex.Match(File.ReadAllText(file), "\"installdir\"\\s+\"([^\"]+)\"");
                    if (!match.Success || match.Groups[1].Value.IndexOf("Frostrail", StringComparison.OrdinalIgnoreCase) < 0)
                        continue;
                    try { result.Add(NormalizeGameRoot(Path.Combine(apps, "common", match.Groups[1].Value))); }
                    catch (DirectoryNotFoundException) { }
                }
            }
            return result.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        }
        public void RefreshGameRunning()
        {
            GameRunning = false;
            foreach (var process in Process.GetProcessesByName("Frostrail-Win64-Shipping")) using (process)
            {
                try
                {
                    var selected = Path.Combine(GameRoot, "Frostrail/Binaries/Win64/Frostrail-Win64-Shipping.exe");
                    if (ResolvedFile(process.MainModule.FileName).Equals(ResolvedFile(selected), StringComparison.OrdinalIgnoreCase))
                        GameRunning = true;
                }
                catch (System.ComponentModel.Win32Exception) { GameRunning = true; }
                catch (IOException) { GameRunning = true; }
                catch (UnauthorizedAccessException) { GameRunning = true; }
                catch (InvalidOperationException) { }
            }
        }
        // Compare the actual executable through junctions without rejecting or restricting those paths.
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint length, uint flags);
        static string ResolvedFile(string path)
        {
            using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                var text = new StringBuilder(32768);
                return GetFinalPathNameByHandle(file.SafeFileHandle, text, (uint)text.Capacity, 0) > 0
                    ? text.ToString() : Path.GetFullPath(path);
            }
        }
        void RequireStopped()
        {
            if (GameRunning) throw new InvalidOperationException(UiText.T("游戏正在运行。请先退出游戏，再改动 Mod 或设置。",
                "The game is running. Close it before changing mods or settings."));
        }
        string Target(string relative) => FileOps.Under(GameRoot, relative);
        string Cache(string id) => FileOps.Under(Path.Combine(DataRoot, "packages"), id + ".zip");
        string Original(string id, string file) => FileOps.Under(
            FileOps.Under(Path.Combine(DataRoot, "originals"), id), file);
        static bool Contains(IEnumerable<string> items, string value) => items.Contains(value, StringComparer.OrdinalIgnoreCase);
        static ModInfo Find(ManagerState state, string id) => state.Mods.TryGetValue(id, out var mod)
            ? mod : throw new InvalidOperationException(UiText.T("没有安装 " + id + "，请先安装它。",
                id + " is not installed. Install it first."));
        static List<ModInfo> Ordered(ManagerState state) => state.Order.Where(state.Mods.ContainsKey)
            .Select(id => state.Mods[id]).OrderBy(m => m.Entries.Count == 0 ? 1 : 0).ToList();
        public List<ModInfo> ListMods() { lock (sync) return Ordered(store.Read()); }
        public List<string> Missing(ModInfo mod) => Missing(mod, store.Read());
        static List<string> Missing(ModInfo mod, ManagerState state) =>
            mod.Manifest.Requires.Where(id => !state.Mods.ContainsKey(id)).ToList();
        public Package InspectPackage(string source) => new Package(source, GameRoot, WorkRoot);

        public List<ModInfo> InstallMany(IEnumerable<string> sources, Func<Manifest, bool> enable = null)
        {
            var packages = new List<Package>();
            try
            {
                foreach (var path in sources) packages.Add(InspectPackage(path));
                return DependencyOrder(packages).Select(p => Install(p, enable == null || enable(p.Manifest), "")).ToList();
            }
            finally { foreach (var package in packages) package.Dispose(); }
        }
        // Prerequisites in the same batch come before the packages that require them.
        static List<Package> DependencyOrder(List<Package> packages)
        {
            var sorted = new List<Package>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            Action<Package> visit = null;
            visit = p => {
                if (!seen.Add(p.Manifest.Id)) return;
                foreach (var dependency in p.Manifest.Requires)
                {
                    var found = packages.FirstOrDefault(x => x.Manifest.Id.Equals(dependency, StringComparison.OrdinalIgnoreCase));
                    if (found != null) visit(found);
                }
                sorted.Add(p);
            };
            foreach (var package in packages) visit(package);
            return sorted;
        }
        public ModInfo InstallPackage(string source, bool enable = true, string origin = "")
        {
            using (var package = InspectPackage(source)) return Install(package, enable, origin);
        }
        ModInfo Install(Package package, bool enable, string origin)
        {
            lock (sync)
            {
                RequireStopped();
                var state = store.Read();
                state.Mods.TryGetValue(package.Manifest.Id, out var old);
                var oldOrder = state.Order.ToList();
                var desired = package.Files.Keys.ToList();
                var owners = state.Mods.Values
                    .Where(m => m.Id != package.Manifest.Id && m.Files.Any(f => Contains(desired, f))).ToArray();
                if (owners.Length > 0)
                {
                    var files = owners.SelectMany(m => m.Files).Where(f => Contains(desired, f)).Distinct().Take(5);
                    throw new IOException(UiText.T("和已装的 ", "Shares files with installed ")
                        + string.Join(", ", owners.Select(m => m.Id))
                        + UiText.T(" 有相同的文件，没有安装：", "; nothing was installed: ") + string.Join(", ", files));
                }
                var now = DateTime.UtcNow.ToString("o");
                var mod = new ModInfo {
                    Manifest = package.Manifest, Entries = package.Entries, Installed = old?.Installed ?? now,
                    Changed = now, Source = origin.Length > 0 ? origin : old?.Source ?? "",
                    Enabled = old?.Enabled ?? enable,
                    Originals = old?.Originals.ToList() ?? new List<string>()
                };
                if (Missing(mod, state).Count > 0 || mod.Manifest.Requires.Any(id => !Find(state, id).Enabled))
                    mod.Enabled = false;
                var disabled = old?.Enabled == true && !mod.Enabled
                    ? ToggleGroup(state, old.Id, false).Where(m => m != old).ToList() : new List<ModInfo>();
                var withdrawn = new List<ModInfo>();
                var written = new List<string>();
                var cacheTemp = Cache(mod.Id) + ".tmp";
                try
                {
                    foreach (var dependent in disabled)
                    {
                        withdrawn.Add(dependent);
                        Withdraw(dependent);
                    }
                    if (old?.Enabled == true)
                    {
                        withdrawn.Add(old);
                        Withdraw(old);
                    }
                    PlanFiles(package, mod);
                    if (mod.Enabled) Deploy(package, mod, written);
                    FileOps.Copy(package.Zip, cacheTemp);
                    state.Mods[mod.Id] = mod;
                    foreach (var dependent in disabled)
                    {
                        var stopped = ModInfo.From(JsonData.Clone(dependent.Data()));
                        stopped.Enabled = false;
                        stopped.Changed = now;
                        state.Mods[stopped.Id] = stopped;
                    }
                    if (!Contains(state.Order, mod.Id)) state.Order.Add(mod.Id);
                    Save(state);
                    if (File.Exists(Cache(mod.Id))) File.Replace(cacheTemp, Cache(mod.Id), null);
                    else File.Move(cacheTemp, Cache(mod.Id));
                }
                catch (Exception failure)
                {
                    var failures = new List<Exception> { failure };
                    void Restore(Action action)
                    {
                        try { action(); }
                        catch (Exception rollbackError) { failures.Add(rollbackError); }
                    }
                    try
                    {
                        Restore(() => Retract(written, mod));
                        if (old != null)
                        {
                            state.Mods[old.Id] = old;
                        }
                        else
                        {
                            Restore(() => {
                                var originals = Path.Combine(DataRoot, "originals", mod.Id);
                                if (Directory.Exists(originals)) Directory.Delete(originals, true);
                            });
                            state.Mods.Remove(mod.Id);
                        }
                        // Include the package whose withdrawal failed; untouched packages need no deployment.
                        foreach (var previousMod in withdrawn.AsEnumerable().Reverse())
                        {
                            Restore(() => {
                                using (var previous = InspectPackage(Cache(previousMod.Id)))
                                    Deploy(previous, previousMod, new List<string>(), false);
                            });
                        }
                        foreach (var dependent in disabled) state.Mods[dependent.Id] = dependent;
                        state.Order = oldOrder;
                        Restore(() => store.Write(state));
                        if (failures.Count > 1) throw new AggregateException(failures);
                        throw;
                    }
                    finally { WriteLoader(store.Read(), mod.Entries); }
                }
                finally { if (File.Exists(cacheTemp)) File.Delete(cacheTemp); }
                LastResult = mod.Id + UiText.T(
                    "：部署了 " + mod.Files.Count + " 个文件，" + package.Documents + " 个说明文件留在包里。",
                    ": " + mod.Files.Count + " files deployed, " + package.Documents + " documents kept in package.");
                Log("install", "info", mod.Id, LastResult);
                return mod;
            }
        }
        void PlanFiles(Package package, ModInfo mod)
        {
            foreach (var file in package.Files.Keys)
            {
                if (Contains(mod.Manifest.KeepExisting, file) && File.Exists(Target(file))) continue;
                mod.Files.Add(file);
            }
        }
        void Deploy(Package package, ModInfo mod, List<string> written, bool captureOriginals = true)
        {
            foreach (var file in mod.Files)
            {
                if (!package.Files.TryGetValue(file, out var source)) continue;
                var target = Target(file);
                if (Path.GetFileName(file).Equals("config.json", StringComparison.OrdinalIgnoreCase) && File.Exists(target))
                    continue;
                if (captureOriginals && File.Exists(target) && !Contains(mod.Originals, file))
                {
                    FileOps.Copy(target, Original(mod.Id, file));
                    mod.Originals.Add(file);
                }
                FileOps.Copy(source, target);
                written.Add(file);
            }
        }
        void Retract(IEnumerable<string> files, ModInfo mod)
        {
            foreach (var file in files)
            {
                if (Path.GetFileName(file).Equals("config.json", StringComparison.OrdinalIgnoreCase)) continue;
                var target = Target(file);
                if (Contains(mod.Originals, file) && File.Exists(Original(mod.Id, file)))
                    FileOps.Copy(Original(mod.Id, file), target);
                else if (File.Exists(target)) File.Delete(target);
                FileOps.Prune(Path.GetDirectoryName(target), GameRoot);
            }
        }
        void Withdraw(ModInfo mod) => Retract(mod.Files, mod);
        public List<ModInfo> ToggleGroup(string id, bool enabled)
        {
            lock (sync) return ToggleGroup(store.Read(), id, enabled);
        }
        static List<ModInfo> ToggleGroup(ManagerState state, string id, bool enabled)
        {
            var result = new List<ModInfo>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            Action<string> visit = null;
            visit = key => {
                if (!seen.Add(key)) return;
                var mod = Find(state, key);
                if (enabled) foreach (var dependency in mod.Manifest.Requires) visit(dependency);
                else foreach (var child in state.Mods.Values.Where(m => m.Enabled && Contains(m.Manifest.Requires, key)))
                    visit(child.Id);
                if (mod.Enabled != enabled) result.Add(mod);
            };
            visit(id);
            return result;
        }
        public void SetEnabled(string id, bool enabled)
        {
            lock (sync)
            {
                RequireStopped();
                var state = store.Read();
                var changed = new List<ModInfo>();
                try
                {
                    foreach (var mod in ToggleGroup(state, id, enabled))
                    {
                        changed.Add(mod);
                        if (enabled)
                        {
                            using (var package = InspectPackage(Cache(mod.Id)))
                            {
                                var written = new List<string>();
                                try { Deploy(package, mod, written); }
                                catch { Retract(written, mod); throw; }
                            }
                        }
                        else Withdraw(mod);
                        mod.Enabled = enabled;
                        mod.Changed = DateTime.UtcNow.ToString("o");
                    }
                    Save(state);
                }
                catch (Exception failure)
                {
                    var failures = new List<Exception> { failure };
                    foreach (var mod in changed.AsEnumerable().Reverse())
                    {
                        try
                        {
                            if (enabled) Withdraw(mod);
                            else using (var package = InspectPackage(Cache(mod.Id)))
                                Deploy(package, mod, new List<string>(), false);
                        }
                        catch (Exception rollbackError) { failures.Add(rollbackError); }
                    }
                    WriteLoader(store.Read());
                    if (failures.Count > 1) throw new AggregateException(failures);
                    throw;
                }
                Log(enabled ? "enable" : "disable", "info", id, string.Join(", ", changed.Select(m => m.Id)));
            }
        }
        public void Move(string id, int offset)
        {
            lock (sync)
            {
                RequireStopped();
                var state = store.Read();
                var native = Ordered(state).Where(m => m.Entries.Count > 0).Select(m => m.Id).ToList();
                var index = native.FindIndex(x => x.Equals(id, StringComparison.OrdinalIgnoreCase));
                if (index < 0 || index + offset < 0 || index + offset >= native.Count) return;
                native.RemoveAt(index);
                native.Insert(index + offset, id);
                state.Order = native.Concat(Ordered(state).Where(m => m.Entries.Count == 0).Select(m => m.Id)).ToList();
                Save(state);
            }
        }
        void Save(ManagerState state, IEnumerable<string> removed = null)
        {
            try
            {
                WriteLoader(state, removed);
                store.Write(state);
            }
            catch
            {
                WriteLoader(store.Read(), removed);
                throw;
            }
        }
        void WriteLoader(ManagerState state, IEnumerable<string> removed = null)
        {
            var file = Path.Combine(ModsRoot, "mods.txt");
            var lines = File.Exists(file) ? File.ReadAllLines(file).ToList() : new List<string>();
            var names = state.Mods.Values.SelectMany(m => m.Entries).Concat(removed ?? new string[0]).ToList();
            var kept = new List<string>();
            bool managed = false;
            foreach (var line in lines)
            {
                if (line == Begin) { managed = true; continue; }
                if (line == End) { managed = false; continue; }
                if (managed) continue;
                var name = Regex.Match(line, @"^\s*([^;:]+?)\s*:").Groups[1].Value;
                if (!Contains(names, name)) kept.Add(line);
            }
            var block = new List<string> { Begin };
            foreach (var mod in Ordered(state)) foreach (var entry in mod.Entries)
                block.Add(entry + " : " + (mod.Enabled ? "1" : "0"));
            block.Add(End);
            var index = kept.FindIndex(l => Regex.IsMatch(l, @"^\s*Keybinds\s*:", RegexOptions.IgnoreCase));
            kept.InsertRange(index < 0 ? kept.Count : index, block);
            Directory.CreateDirectory(ModsRoot);
            File.WriteAllLines(file, kept, new UTF8Encoding(false));
        }
        public void Uninstall(string id, bool keepConfig = false)
        {
            lock (sync)
            {
                RequireStopped();
                var state = store.Read();
                var mod = Find(state, id);
                foreach (var item in ToggleGroup(state, id, false))
                {
                    if (item.Id != id) Withdraw(item);
                    item.Enabled = false;
                    item.Changed = DateTime.UtcNow.ToString("o");
                }
                var protectedFiles = new HashSet<string>(mod.Originals.Concat(mod.Manifest.KeepExisting)
                    .Concat(state.Mods.Values.Where(m => m.Id != id).SelectMany(m => m.Files)), StringComparer.OrdinalIgnoreCase);
                if (keepConfig) foreach (var entry in mod.Entries)
                    protectedFiles.Add(NativeMods + entry + "/config.json");
                var candidates = new HashSet<string>(mod.Files, StringComparer.OrdinalIgnoreCase);
                var roots = mod.Entries.Select(e => NativeMods + e).Concat(mod.Manifest.DataPaths).ToList();
                foreach (var relative in roots)
                {
                    var path = Target(relative);
                    if (Directory.Exists(path)) foreach (var f in Directory.GetFiles(path, "*", SearchOption.AllDirectories))
                        candidates.Add(FileOps.Relative(GameRoot, f));
                    else if (File.Exists(path)) candidates.Add(relative);
                }
                foreach (var file in candidates.Where(f => !protectedFiles.Contains(f)))
                {
                    var path = Target(file);
                    if (File.Exists(path)) File.Delete(path);
                    FileOps.Prune(Path.GetDirectoryName(path), GameRoot);
                }
                foreach (var file in mod.Originals)
                    if (File.Exists(Original(id, file))) FileOps.Copy(Original(id, file), Target(file));
                foreach (var relative in roots) FileOps.EmptyDirectories(Target(relative));
                File.Delete(Cache(id));
                var originalRoot = FileOps.Under(Path.Combine(DataRoot, "originals"), id);
                if (Directory.Exists(originalRoot)) Directory.Delete(originalRoot, true);
                state.Mods.Remove(id);
                state.Order.RemoveAll(x => x.Equals(id, StringComparison.OrdinalIgnoreCase));
                Save(state, mod.Entries);
                Log("uninstall", "info", id, "Removed package; preserved original and other packages' files.");
            }
        }
        public List<SettingsPage> ReadSettings(ModInfo mod)
        {
            var pages = new List<SettingsPage>();
            foreach (var entry in mod.Entries)
            {
                var dir = Target(NativeMods + entry);
                var fields = JsonData.List(JsonData.Read(Path.Combine(dir, "settings.json")))
                    .Select(SettingField.From).ToList();
                if (fields.Count == 0) continue;
                pages.Add(new SettingsPage {
                    ConfigPath = Path.Combine(dir, "config.json"), Fields = fields,
                    Defaults = JsonData.Load(Path.Combine(dir, "defaults.json")),
                    Values = JsonData.Load(Path.Combine(dir, "config.json"))
                });
            }
            return pages;
        }
        public void WriteSetting(SettingsPage page, string key, object value)
        {
            lock (sync)
            {
                RequireStopped();
                var values = JsonData.Load(page.ConfigPath);
                JsonData.SetAt(values, key, value);
                JsonData.Save(page.ConfigPath, values);
                page.Values = values;
            }
        }
        public void ResetSettings(SettingsPage page)
        {
            lock (sync)
            {
                RequireStopped();
                var values = JsonData.Load(page.ConfigPath);
                foreach (var field in page.Fields)
                    JsonData.SetAt(values, field.Key, JsonData.At(page.Defaults, field.Key));
                JsonData.Save(page.ConfigPath, values);
                page.Values = values;
            }
        }
        // Read README from the cached ZIP directly; extracting the whole package on every selection is slow.
        public string Readme(ModInfo mod)
        {
            var cache = Cache(mod.Id);
            if (!File.Exists(cache)) return "";
            using (var archive = ZipFile.OpenRead(cache))
            {
                var entry = archive.Entries
                    .Where(e => Path.GetFileNameWithoutExtension(e.Name)
                        .Equals("README", StringComparison.OrdinalIgnoreCase))
                    .OrderBy(e => e.FullName.Count(c => c == '/')).FirstOrDefault();
                if (entry == null) return "";
                using (var reader = new StreamReader(entry.Open(), Encoding.UTF8, true)) return reader.ReadToEnd();
            }
        }
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.RegularExpressions;

namespace Frostrail.ModManager
{
    public static class FileOps
    {
        public static string Under(string root, string relative)
        {
            var prefix = Path.GetFullPath(root).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
            var path = Path.GetFullPath(Path.Combine(prefix, relative.Replace('/', Path.DirectorySeparatorChar)));
            if (!path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                throw new IOException("Path escapes its directory: " + relative);
            return path;
        }
        public static string Relative(string root, string path) =>
            Path.GetFullPath(path).Substring(Path.GetFullPath(root).TrimEnd('\\', '/').Length + 1).Replace('\\', '/');
        public static void Copy(string from, string to)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(to));
            File.Copy(from, to, true);
        }
        public static void Extract(string zip, string target)
        {
            Directory.CreateDirectory(target);
            using (var archive = ZipFile.OpenRead(zip)) foreach (var entry in archive.Entries)
            {
                if (entry.Name.Length == 0) continue;
                var path = Under(target, entry.FullName);
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                entry.ExtractToFile(path, true);
            }
        }
        public static void Prune(string path, string boundary)
        {
            while (path != null && path.Length > boundary.Length && Directory.Exists(path)
                && !Directory.EnumerateFileSystemEntries(path).Any())
            {
                Directory.Delete(path);
                path = Path.GetDirectoryName(path);
            }
        }
        public static void EmptyDirectories(string root)
        {
            if (!Directory.Exists(root)) return;
            foreach (var dir in Directory.GetDirectories(root)) EmptyDirectories(dir);
            if (!Directory.EnumerateFileSystemEntries(root).Any()) Directory.Delete(root);
        }
    }

    public sealed class Package : IDisposable
    {
        readonly string scratch;
        public string Root, Zip, Readme = "";
        public Manifest Manifest;
        public List<string> Entries = new List<string>();
        public Dictionary<string, string> Files = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public int Documents;
        public bool DeclaredId;
        public static bool Native(string dir) => File.Exists(Path.Combine(dir, "Scripts", "main.lua"))
            || File.Exists(Path.Combine(dir, "dlls", "main.dll"));
        public Package(string source, string gameRoot, string workRoot)
        {
            scratch = Path.Combine(workRoot, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(scratch);
            try
            {
                Zip = Path.Combine(scratch, "package.zip");
                // Keep the dropped folder itself, so "MyMod/" with Scripts/main.lua inside is the mod,
                // and a package folder with mod.json is unwrapped by rule 1 below.
                if (Directory.Exists(source))
                    ZipFile.CreateFromDirectory(source.TrimEnd('\\', '/'), Zip, CompressionLevel.Optimal, true);
                else File.Copy(source, Zip);
                Root = Path.Combine(scratch, "contents");
                FileOps.Extract(Zip, Root);
                while (true)
                {
                    var items = Directory.GetFileSystemEntries(Root);
                    if (items.Length != 1 || !Directory.Exists(items[0]) || Native(items[0])
                        || Directory.Exists(Path.Combine(gameRoot, Path.GetFileName(items[0])))) break;
                    Root = items[0];
                }
                Manifest = Manifest.From(JsonData.Read(Path.Combine(Root, "mod.json")));
                var readme = Directory.GetFiles(Root).FirstOrDefault(p =>
                    Path.GetFileNameWithoutExtension(p).Equals("README", StringComparison.OrdinalIgnoreCase));
                if (readme != null) Readme = File.ReadAllText(readme);
                foreach (var item in Directory.GetFileSystemEntries(Root))
                {
                    var name = Path.GetFileName(item);
                    if (File.Exists(item))
                    {
                        if (new[] { ".pak", ".utoc", ".ucas" }.Contains(Path.GetExtension(item).ToLowerInvariant()))
                            Files["Frostrail/Content/Paks/~mods/" + name] = item;
                        else Documents++;
                        continue;
                    }
                    string prefix;
                    if (Directory.Exists(Path.Combine(gameRoot, name))) prefix = name + "/";
                    else if (Native(item)) prefix = ManagerService.NativeMods + name + "/";
                    else throw new InvalidDataException("Cannot determine deployment location: " + name);
                    foreach (var file in Directory.GetFiles(item, "*", SearchOption.AllDirectories))
                        Files[prefix + FileOps.Relative(item, file)] = file;
                }
                foreach (var path in Files.Keys)
                {
                    var match = Regex.Match(path, "^" + Regex.Escape(ManagerService.NativeMods)
                        + @"([^/]+)/(?:Scripts/main\.lua|dlls/main\.dll)$", RegexOptions.IgnoreCase);
                    if (match.Success && !Entries.Contains(match.Groups[1].Value)) Entries.Add(match.Groups[1].Value);
                }
                DeclaredId = Manifest.Id.Length > 0;
                if (!DeclaredId)
                {
                    var paks = Files.Keys.Where(p => p.EndsWith(".pak", StringComparison.OrdinalIgnoreCase)).ToList();
                    Manifest.Id = Entries.Count == 1 ? Entries[0] : paks.Count == 1
                        ? Path.GetFileNameWithoutExtension(paks[0]) : Path.GetFileNameWithoutExtension(source.TrimEnd('\\', '/'));
                }
                if (Manifest.Name == null) Manifest.Name = Manifest.Id;
                if (Manifest.Description == null)
                {
                    // First paragraph of the README, without Markdown heading lines.
                    var body = Regex.Replace(Readme, @"^\s*#.*$", "", RegexOptions.Multiline);
                    Manifest.Description = Regex.Split(body, @"\r?\n\s*\r?\n").Select(p => p.Trim())
                        .FirstOrDefault(p => p.Length > 0) ?? "";
                }
            }
            catch { Dispose(); throw; }
        }
        public void Dispose()
        {
            if (Directory.Exists(scratch)) Directory.Delete(scratch, true);
            FileOps.Prune(Path.GetDirectoryName(scratch), Path.GetDirectoryName(Path.GetDirectoryName(scratch)));
        }
    }
}

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace Frostrail.ModManager
{
    public static class JsonData
    {
        static JavaScriptSerializer Serializer() => new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        public static object Parse(string text) => Serializer().DeserializeObject(text.TrimStart('\uFEFF'));
        public static string Serialize(object value) => Serializer().Serialize(value);
        public static object Read(string path) => File.Exists(path) ? Parse(File.ReadAllText(path)) : null;
        public static Dictionary<string, object> Load(string path) => Map(Read(path));
        public static void Save(string path, object value)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));
            File.WriteAllText(path, Serialize(value), new UTF8Encoding(false));
        }
        public static Dictionary<string, object> Map(object value) =>
            value as Dictionary<string, object> ?? new Dictionary<string, object>();
        public static object Get(object map, string key, object fallback = null) =>
            Map(map).TryGetValue(key, out var value) ? value : fallback;
        public static List<object> List(object value) =>
            value is IEnumerable items && !(value is string) && !(value is IDictionary)
                ? items.Cast<object>().ToList() : new List<object>();
        public static string Text(object value) => Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
        public static List<string> Strings(object value) => List(value).Select(Text).ToList();
        public static bool Bool(object value) => value is bool flag && flag;
        public static string Local(object value, string language)
        {
            if (!(value is Dictionary<string, object> map)) return Text(value);
            return Text(Get(map, language, Get(map, language.StartsWith("zh") ? "zh" : "en",
                Get(map, "en", map.Values.FirstOrDefault()))));
        }
        public static object At(object value, string key)
        {
            foreach (var part in key.Split('.')) value = Get(value, part);
            return value;
        }
        public static void SetAt(Dictionary<string, object> map, string key, object value)
        {
            var parts = key.Split('.');
            foreach (var part in parts.Take(parts.Length - 1))
            {
                var child = Map(Get(map, part));
                map[part] = child;
                map = child;
            }
            map[parts.Last()] = value;
        }
        public static object Clone(object value) => Parse(Serialize(value));
        public static bool IsNumber(object v) => v is int || v is long || v is decimal || v is double || v is float;
    }

    public sealed class Manifest
    {
        public string Id = "", Version = "", Author = "", Update = "";
        public object Name, Description;
        public List<string> Requires = new List<string>();
        public List<string> KeepExisting = new List<string>();
        public List<string> DataPaths = new List<string>();
        public Dictionary<string, object> Notices = new Dictionary<string, object>();
        public static Manifest From(object value)
        {
            return new Manifest {
                Id = JsonData.Text(JsonData.Get(value, "id")),
                Version = JsonData.Text(JsonData.Get(value, "version")),
                Author = JsonData.Text(JsonData.Get(value, "author")),
                Update = JsonData.Text(JsonData.Get(value, "update")),
                Name = JsonData.Get(value, "name"), Description = JsonData.Get(value, "description"),
                Requires = JsonData.Strings(JsonData.Get(value, "requires")),
                KeepExisting = JsonData.Strings(JsonData.Get(value, "keep_existing")),
                DataPaths = JsonData.Strings(JsonData.Get(value, "data_paths")),
                Notices = JsonData.Map(JsonData.Get(value, "notices"))
            };
        }
        public object Data() => new {
            id = Id, version = Version, author = Author, update = Update, name = Name, description = Description,
            requires = Requires, keep_existing = KeepExisting, data_paths = DataPaths, notices = Notices
        };
    }

    public sealed class ModInfo
    {
        public Manifest Manifest = new Manifest();
        public bool Enabled;
        public List<string> Entries = new List<string>();
        public List<string> Files = new List<string>();
        public List<string> Originals = new List<string>();
        public string Source = "", Installed = "", Changed = "";
        public string Id => Manifest.Id;
        public string Version => Manifest.Version;
        public string Name(string language) => JsonData.Local(Manifest.Name ?? Id, language);
        public string Notice(string action, string language) => JsonData.Local(JsonData.Get(Manifest.Notices, action), language);
        public string UpdateSource => string.IsNullOrWhiteSpace(Manifest.Update) ? Source : Manifest.Update;
        public object Data() => new {
            manifest = Manifest.Data(), enabled = Enabled, entries = Entries, files = Files, originals = Originals,
            source = Source, installed = Installed, changed = Changed
        };
        public static ModInfo From(object value) => new ModInfo {
            Manifest = Manifest.From(JsonData.Get(value, "manifest")),
            Enabled = JsonData.Bool(JsonData.Get(value, "enabled")),
            Entries = JsonData.Strings(JsonData.Get(value, "entries")),
            Files = JsonData.Strings(JsonData.Get(value, "files")),
            Originals = JsonData.Strings(JsonData.Get(value, "originals")),
            Source = JsonData.Text(JsonData.Get(value, "source")),
            Installed = JsonData.Text(JsonData.Get(value, "installed")),
            Changed = JsonData.Text(JsonData.Get(value, "changed"))
        };
    }

    public sealed class ManagerState
    {
        public List<string> Order = new List<string>();
        public Dictionary<string, ModInfo> Mods = new Dictionary<string, ModInfo>(StringComparer.OrdinalIgnoreCase);
    }

    // This is the only reader/writer of state.json. Loader files are generated outputs.
    public sealed class StateStore
    {
        readonly string path;
        public StateStore(string root) { path = Path.Combine(root, "state.json"); }
        public ManagerState Read()
        {
            var data = JsonData.Load(path);
            var state = new ManagerState { Order = JsonData.Strings(JsonData.Get(data, "order")) };
            foreach (var pair in JsonData.Map(JsonData.Get(data, "mods"))) state.Mods[pair.Key] = ModInfo.From(pair.Value);
            return state;
        }
        public void Write(ManagerState state)
        {
            var data = new { format = 1, order = state.Order,
                mods = state.Mods.ToDictionary(x => x.Key, x => x.Value.Data()) };
            var temp = path + ".tmp";
            JsonData.Save(temp, data);
            if (File.Exists(path)) File.Replace(temp, path, null);
            else File.Move(temp, path);
        }
    }

    public sealed class SettingField
    {
        public string Key, Type, ValueType;
        public object Label, Group, Help;
        public bool Live, Integer;
        public decimal? Min, Max, Step;
        public List<object> Options = new List<object>();
        public List<SettingField> Columns = new List<SettingField>();
        static decimal? Number(object x) => x == null ? (decimal?)null : Convert.ToDecimal(x, CultureInfo.InvariantCulture);
        public static SettingField From(object x) => new SettingField {
            Key = JsonData.Text(JsonData.Get(x, "key")), Type = JsonData.Text(JsonData.Get(x, "type")),
            ValueType = JsonData.Text(JsonData.Get(x, "value_type")), Label = JsonData.Get(x, "label"),
            Group = JsonData.Get(x, "group"), Help = JsonData.Get(x, "help"),
            Live = JsonData.Bool(JsonData.Get(x, "live")), Integer = JsonData.Bool(JsonData.Get(x, "integer")),
            Min = Number(JsonData.Get(x, "min")), Max = Number(JsonData.Get(x, "max")),
            Step = Number(JsonData.Get(x, "step")), Options = JsonData.List(JsonData.Get(x, "options")),
            Columns = JsonData.List(JsonData.Get(x, "columns")).Select(From).ToList()
        };
        public string Kind(object defaultValue)
        {
            if (Type == "color") return "color";
            if (Options.Count > 0) return "choice";
            if (defaultValue is bool) return "bool";
            if (JsonData.IsNumber(defaultValue)) return "number";
            if (defaultValue is string) return "string";
            if (defaultValue is IDictionary) return "map";
            return "list";
        }
    }
    public sealed class SettingsPage
    {
        public string ConfigPath;
        public List<SettingField> Fields = new List<SettingField>();
        public Dictionary<string, object> Defaults = new Dictionary<string, object>();
        public Dictionary<string, object> Values = new Dictionary<string, object>();
        public object Value(string key) => JsonData.At(Values, key) ?? JsonData.At(Defaults, key);
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace Frostrail.ModManager
{
    public sealed class GitHubSource
    {
        public string Url, Owner, Repo, Branch = "", Directory = "";
        public string Api => "https://api.github.com/repos/" + Uri.EscapeDataString(Owner) + "/" + Uri.EscapeDataString(Repo);
        public static GitHubSource Parse(string url)
        {
            var uri = new Uri(url);
            var parts = uri.AbsolutePath.Trim('/').Split('/').Select(Uri.UnescapeDataString).ToArray();
            // This selects the documented GitHub URL syntax; downloaded asset hosts are not restricted.
            if (!uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase) || parts.Length < 2)
                throw new ArgumentException(UiText.T("请填写 GitHub 仓库链接，或 …/tree/分支/目录 形式的链接。",
                    "Use a GitHub repository link or a …/tree/branch/directory link."));
            var source = new GitHubSource { Url = url, Owner = parts[0], Repo = parts[1] };
            if (parts.Length >= 4 && parts[2] == "tree")
            {
                source.Branch = parts[3];
                source.Directory = string.Join("/", parts.Skip(4));
            }
            return source;
        }
    }
    public sealed class UpdateInfo
    {
        public string Id = "", Version = "", DownloadUrl = "", Source = "", Directory = "", Commit = "", Name = "", Error = "";
        public bool Available;
        // installed is the version on disk now, or null when the mod is gone.
        public void Compare(string installed) =>
            Available = Error.Length == 0 && installed != null && Version != installed;
    }
    public sealed partial class ManagerService
    {
        public HttpClient Network { get; set; } = CreateHttpClient();
        static HttpClient CreateHttpClient()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            return new HttpClient { Timeout = TimeSpan.FromMinutes(3) };
        }
        async Task<HttpResponseMessage> Request(string url, CancellationToken token = default(CancellationToken))
        {
            var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("User-Agent",
                "Frostrail-Mod-Manager/" + typeof(ManagerService).Assembly.GetName().Version.ToString(3));
            HttpResponseMessage response;
            try { response = await Network.SendAsync(request, token).ConfigureAwait(false); }
            catch (TaskCanceledException)
            {
                throw new HttpRequestException(UiText.T("连接 GitHub 超时，请稍后再试，或拖入本地 ZIP。",
                    "GitHub did not respond in time; retry later or install a local ZIP."));
            }
            if (!response.IsSuccessStatusCode)
            {
                var code = (int)response.StatusCode;
                response.Dispose();
                throw new HttpRequestException(code == 403 || code == 429
                    ? UiText.T("GitHub 请求次数已达上限，请稍后再试，或拖入本地 ZIP。",
                        "GitHub request limit reached; retry later or install a local ZIP.")
                    : UiText.T("GitHub 返回 HTTP ", "GitHub returned HTTP ") + code);
            }
            return response;
        }
        // API answers are small; a slow or blocked api.github.com should fail fast instead of waiting minutes.
        async Task<object> GetJson(string url)
        {
            using (var limit = new CancellationTokenSource(TimeSpan.FromSeconds(20)))
            using (var response = await Request(url, limit.Token).ConfigureAwait(false))
                return JsonData.Parse(await response.Content.ReadAsStringAsync().ConfigureAwait(false));
        }
        static string PathUrl(string path) => string.Join("/", path.Split('/').Select(Uri.EscapeDataString));
        async Task<UpdateInfo> DirectoryUpdate(GitHubSource source, string id)
        {
            var commit = await GetJson(source.Api + "/commits/" + Uri.EscapeDataString(source.Branch)).ConfigureAwait(false);
            var sha = JsonData.Text(JsonData.Get(commit, "sha"));
            var path = source.Directory.Length == 0 ? "mod.json" : source.Directory + "/mod.json";
            var content = await GetJson(source.Api + "/contents/" + PathUrl(path) + "?ref=" + Uri.EscapeDataString(sha))
                .ConfigureAwait(false);
            var manifest = Manifest.From(JsonData.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(
                JsonData.Text(JsonData.Get(content, "content"))))));
            return new UpdateInfo {
                Id = id, Version = manifest.Version, Source = source.Url, Directory = source.Directory,
                Commit = sha, DownloadUrl = source.Api + "/zipball/" + Uri.EscapeDataString(sha), Name = source.Directory
            };
        }
        static List<object> Releases(object value) => JsonData.List(value)
            .Where(r => !JsonData.Bool(JsonData.Get(r, "draft"))).ToList();
        static List<object> Assets(object release) => JsonData.List(JsonData.Get(release, "assets"))
            .Where(a => JsonData.Text(JsonData.Get(a, "name")).EndsWith(".zip", StringComparison.OrdinalIgnoreCase)).ToList();
        static UpdateInfo Asset(object asset, object release, GitHubSource source, string id)
        {
            var name = JsonData.Text(JsonData.Get(asset, "name"));
            var match = id.Length == 0 ? Match.Empty : Regex.Match(name,
                "(?:^|-)" + Regex.Escape(id) + @"-(.+)\.zip$", RegexOptions.IgnoreCase);
            return new UpdateInfo {
                Id = id, Name = name, Source = source.Url,
                DownloadUrl = JsonData.Text(JsonData.Get(asset, "browser_download_url")),
                Version = match.Success ? match.Groups[1].Value : JsonData.Text(JsonData.Get(release, "tag_name")).TrimStart('v', 'V')
            };
        }
        static UpdateInfo ReleaseUpdate(object data, GitHubSource source, string id)
        {
            var releases = Releases(data);
            foreach (var release in releases) foreach (var asset in Assets(release))
            {
                var name = JsonData.Text(JsonData.Get(asset, "name"));
                if (Regex.IsMatch(name, "(?:^|-)" + Regex.Escape(id) + @"-.+\.zip$", RegexOptions.IgnoreCase))
                    return Asset(asset, release, source, id);
            }
            if (releases.Count > 0 && Assets(releases[0]).Count == 1)
                return Asset(Assets(releases[0])[0], releases[0], source, id);
            return new UpdateInfo { Id = id, Source = source.Url, Error = UiText.T("最近的 Release 里没有找到这个 Mod 的 ZIP。",
                "No ZIP for this mod was found in recent releases.") };
        }
        public async Task<List<UpdateInfo>> CheckUpdatesAsync()
        {
            var result = new List<UpdateInfo>();
            var repos = new Dictionary<string, Task<object>>(StringComparer.OrdinalIgnoreCase);
            foreach (var mod in ListMods().Where(m => m.UpdateSource.Length > 0))
            {
                try
                {
                    var source = GitHubSource.Parse(mod.UpdateSource);
                    UpdateInfo info;
                    if (source.Branch.Length > 0) info = await DirectoryUpdate(source, mod.Id).ConfigureAwait(false);
                    else
                    {
                        if (!repos.TryGetValue(source.Api, out var task)) repos[source.Api] = task = GetJson(source.Api + "/releases");
                        info = ReleaseUpdate(await task.ConfigureAwait(false), source, mod.Id);
                    }
                    info.Compare(mod.Version);
                    result.Add(info);
                }
                catch (Exception e)
                {
                    result.Add(new UpdateInfo { Id = mod.Id, Error = e.Message });
                    Log("update", "error", mod.Id, e.Message);
                }
            }
            return result;
        }
        public async Task<List<UpdateInfo>> GetInstallChoicesAsync(string url)
        {
            var source = GitHubSource.Parse(url);
            if (source.Branch.Length > 0) return new List<UpdateInfo> { await DirectoryUpdate(source, "").ConfigureAwait(false) };
            var releases = Releases(await GetJson(source.Api + "/releases").ConfigureAwait(false));
            return releases.Count == 0 ? new List<UpdateInfo>()
                : Assets(releases[0]).Select(a => Asset(a, releases[0], source, "")).ToList();
        }
        public async Task<ModInfo> InstallRemoteAsync(UpdateInfo info, Func<Manifest, bool> enable = null) =>
            (await InstallRemoteManyAsync(new[] { info }, enable).ConfigureAwait(false)).Single();
        // Downloads everything first, then installs prerequisites before the mods that need them,
        // so picking Assist above Core in one go still leaves both enabled.
        public async Task<List<ModInfo>> InstallRemoteManyAsync(IList<UpdateInfo> infos, Func<Manifest, bool> enable = null)
        {
            RequireStopped();
            var directory = Path.Combine(WorkRoot, Guid.NewGuid().ToString("N"));
            var packages = new List<Package>();
            var sources = new Dictionary<Package, string>();
            try
            {
                for (int i = 0; i < infos.Count; i++)
                {
                    var folder = Path.Combine(directory, i.ToString());
                    var package = await DownloadAsync(infos[i], folder).ConfigureAwait(false);
                    packages.Add(package);
                    sources[package] = infos[i].Source;
                }
                return DependencyOrder(packages)
                    .Select(p => Install(p, enable == null || enable(p.Manifest), sources[p])).ToList();
            }
            finally
            {
                foreach (var package in packages) package.Dispose();
                if (Directory.Exists(directory)) Directory.Delete(directory, true);
            }
        }
        async Task<Package> DownloadAsync(UpdateInfo info, string directory)
        {
            Directory.CreateDirectory(directory);
            var zip = Path.Combine(directory, info.Name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)
                ? Path.GetFileName(info.Name) : "download.zip");
            using (var response = await Request(info.DownloadUrl).ConfigureAwait(false))
            using (var stream = File.Create(zip)) await response.Content.CopyToAsync(stream).ConfigureAwait(false);
            if (info.Commit.Length > 0)
            {
                var extracted = Path.Combine(directory, "snapshot");
                FileOps.Extract(zip, extracted);
                var snapshot = Directory.GetDirectories(extracted).Single();
                return InspectPackage(info.Directory.Length == 0 ? snapshot : FileOps.Under(snapshot, info.Directory));
            }
            var package = InspectPackage(zip);
            try
            {
                // A Release's filename/tag is the published version, including packages without mod.json.
                var assetVersion = Regex.Match(info.Name, "(?:^|-)" + Regex.Escape(package.Manifest.Id) + @"-(.+)\.zip$",
                    RegexOptions.IgnoreCase);
                package.Manifest.Version = assetVersion.Success ? assetVersion.Groups[1].Value : info.Version;
                // The single-ZIP fallback can pick another mod's asset in a multi-mod repository.
                if (info.Id.Length > 0 && package.DeclaredId
                    && !package.Manifest.Id.Equals(info.Id, StringComparison.OrdinalIgnoreCase))
                {
                    var found = package.Manifest.Id;
                    throw new InvalidDataException(info.Name + UiText.T(
                        " 里是 " + found + "，不是 " + info.Id + "，没有安装。",
                        " contains " + found + ", not " + info.Id + "; nothing was installed."));
                }
                if (info.Id.Length > 0) package.Manifest.Id = info.Id;
                return package;
            }
            catch
            {
                package.Dispose();
                throw;
            }
        }
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Frostrail.ModManager
{
    internal static class FileStamp
    {
        // Detect changed, added and removed inputs without rereading their contents on every page switch.
        public static string Read(IEnumerable<string> paths) => JsonData.Serialize(paths
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase).Select(path => {
                var file = new FileInfo(path);
                return new { path, length = file.Exists ? file.Length : -1,
                    written = file.Exists ? file.LastWriteTimeUtc.Ticks : 0 };
            }).ToArray());
    }
}

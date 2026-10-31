using System.Globalization;

namespace Frostrail.ModManager
{
    internal static class UiText
    {
        public static bool Chinese = CultureInfo.CurrentUICulture.Name.StartsWith("zh");
        public static string T(string zh, string en) => Chinese ? zh : en;
    }
}

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Text;

namespace Frostrail.ModManager
{
    // Build formatting in memory; assigning Rtf once avoids a native layout for every colored log entry.
    internal sealed class RichTextDocument
    {
        readonly StringBuilder body = new StringBuilder();
        readonly List<Color> colors = new List<Color>();
        public void Append(string text, Color color)
        {
            int index = colors.IndexOf(color);
            if (index < 0) { index = colors.Count; colors.Add(color); }
            body.Append(@"\cf").Append(index + 1).Append(' ');
            Escape(body, text.Replace("\r\n", "\n").Replace('\r', '\n'));
        }
        public string Build(Font font)
        {
            var rtf = new StringBuilder(@"{\rtf1\ansi\deff0\uc1{\fonttbl{\f0 ");
            Escape(rtf, font.Name);
            rtf.Append(@";}}{\colortbl ;");
            foreach (var color in colors)
                rtf.Append(@"\red").Append(color.R).Append(@"\green").Append(color.G)
                    .Append(@"\blue").Append(color.B).Append(';');
            rtf.Append(@"}\pard\sa0\sb0\f0\fs").Append((int)Math.Round(font.SizeInPoints * 2)).Append(' ');
            // RichEdit consumes the final paragraph marker. Keep it separate from the text's own trailing LF.
            return rtf.Append(body).Append(@"\par}").ToString();
        }
        static void Escape(StringBuilder target, string text)
        {
            foreach (char c in text)
            {
                if (c == '\n') target.Append(@"\par ");
                else if (c == '\t') target.Append(@"\tab ");
                else if (c == '\\' || c == '{' || c == '}') target.Append('\\').Append(c);
                else if (c >= 32 && c <= 126) target.Append(c);
                else target.Append(@"\u").Append(unchecked((short)c)).Append('?');
            }
        }
    }
}

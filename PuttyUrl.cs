// PuttyUrl - launches PuTTY from an ssh:// / telnet:// / rlogin:// URL.
//
// Registered as a Windows URL protocol handler, so this receives untrusted
// input straight from the browser: every field is parsed with an explicit
// regex and re-validated against a character whitelist before it reaches
// PuTTY's command line. Nothing is passed through a shell.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class PuttyUrl
{
    private const string SessionsKey = @"Software\SimonTatham\PuTTY\Sessions";

    private const string Usage =
        "Usage: PuttyUrl.exe <url>\r\n\r\n" +
        "  ssh://[user@]host[:port]\r\n" +
        "  telnet://[user@]host[:port]\r\n" +
        "  rlogin://[user@]host[:port]";

    // scheme://[userinfo@]host[:port][/...]
    private static readonly Regex UrlRe = new Regex(
        @"^(?<scheme>[A-Za-z][A-Za-z0-9+.\-]*)://(?:(?<userinfo>[^/?#]*)@)?(?<hostport>[^/?#@]*)(?:[/?#].*)?$",
        RegexOptions.Singleline);

    private static readonly Regex HostPortRe = new Regex(
        @"^(?:\[(?<host>[0-9A-Fa-f:.]{2,45})\]|(?<host>[^:\[\]]+))(?::(?<port>[0-9]{1,5}))?$");

    // Deliberately strict. Anything odder than this is a job for PuTTY itself.
    private static readonly Regex HostOk = new Regex(@"^[A-Za-z0-9][A-Za-z0-9._\-:]{0,253}$");
    private static readonly Regex UserOk = new Regex(@"^[A-Za-z0-9][A-Za-z0-9._\-$@]{0,63}$");

    [STAThread]
    private static int Main(string[] argv)
    {
        try
        {
            return Run(argv);
        }
        catch (Exception ex)
        {
            return Fail("Unexpected error:\r\n\r\n" + ex.Message);
        }
    }

    private static int Run(string[] argv)
    {
        if (argv.Length < 1 || argv[0].Trim().Length == 0)
            return Fail("No URL was supplied.\r\n\r\n" + Usage);

        string raw = argv[0].Trim();
        Match m = UrlRe.Match(raw);
        if (!m.Success)
            return Fail("Not a URL this handler understands:\r\n\r\n" + raw + "\r\n\r\n" + Usage);

        string protocolFlag;
        switch (m.Groups["scheme"].Value.ToLowerInvariant())
        {
            case "ssh": protocolFlag = "-ssh"; break;
            // Chromium silently drops some safelisted schemes; putty:// is an unclaimed alias for ssh.
            case "putty": protocolFlag = "-ssh"; break;
            case "telnet": protocolFlag = "-telnet"; break;
            case "rlogin": protocolFlag = "-rlogin"; break;
            default:
                return Fail("Unsupported scheme \"" + m.Groups["scheme"].Value + "\".\r\n\r\n" + Usage);
        }

        Match hp = HostPortRe.Match(m.Groups["hostport"].Value);
        if (!hp.Success)
            return Fail("Could not read a host out of:\r\n\r\n" + raw);

        string host = Unescape(hp.Groups["host"].Value);
        if (!HostOk.IsMatch(host))
            return Fail("Refusing to connect: \"" + host + "\" is not a valid host name or address.");

        string port = null;
        if (hp.Groups["port"].Success)
        {
            int p;
            if (!int.TryParse(hp.Groups["port"].Value, out p) || p < 1 || p > 65535)
                return Fail("Refusing to connect: \"" + hp.Groups["port"].Value + "\" is not a valid port.");
            port = p.ToString();
        }

        // A password in the URL is ignored on purpose: PuTTY's -pw puts it in
        // this machine's process list for anyone to read.
        string user = null;
        if (m.Groups["userinfo"].Success)
        {
            string ui = m.Groups["userinfo"].Value;
            int colon = ui.IndexOf(':');
            if (colon >= 0) ui = ui.Substring(0, colon);
            ui = Unescape(ui);
            if (ui.Length > 0)
            {
                if (!UserOk.IsMatch(ui))
                    return Fail("Refusing to connect: \"" + ui + "\" is not a valid user name.");
                user = ui;
            }
        }

        string putty = FindPutty();
        if (putty == null)
            return Fail("Could not find putty.exe.\r\n\r\n" +
                        "Looked next to this program, in the PuTTY folder under Program Files, and on PATH. " +
                        "Set the PUTTY_PATH environment variable to its full path.");

        // A saved session wins when one matches: it carries the key, user and port,
        // which a bare ssh:// URL cannot. Anything explicit in the URL still overrides it.
        string session = FindSession(host, port);

        var args = new StringBuilder();
        if (session != null)
        {
            Append(args, "-load");
            Append(args, session);
            if (user != null) { Append(args, "-l"); Append(args, user); }
            if (port != null) { Append(args, "-P"); Append(args, port); }
        }
        else
        {
            Append(args, protocolFlag);
            if (user != null) { Append(args, "-l"); Append(args, user); }
            if (port != null) { Append(args, "-P"); Append(args, port); }
            Append(args, host);
        }

        var psi = new ProcessStartInfo(putty, args.ToString());
        psi.UseShellExecute = false;
        psi.WorkingDirectory = Path.GetDirectoryName(putty);
        Process.Start(psi);
        return 0;
    }

    private static void Append(StringBuilder sb, string arg)
    {
        if (sb.Length > 0) sb.Append(' ');
        sb.Append('"').Append(arg).Append('"');
    }

    private static string Unescape(string s)
    {
        try { return Uri.UnescapeDataString(s); }
        catch (UriFormatException) { return s; }
    }

    // Saved sessions live in the registry with their names percent-escaped.
    // Matched in order: the session's own name (putty://iotgate), HostName plus
    // port where the URL gave one, HostName alone, then the name without .local.
    // The port step matters when several sessions share a host and differ only by
    // port, as a set of tunnelled sessions on one gateway does.
    private static string FindSession(string host, string port)
    {
        try
        {
            using (RegistryKey root = Registry.CurrentUser.OpenSubKey(SessionsKey))
            {
                if (root == null) return null;

                string bare = host.EndsWith(".local", StringComparison.OrdinalIgnoreCase)
                    ? host.Substring(0, host.Length - ".local".Length)
                    : host;

                string byHostAndPort = null, byHostName = null, byBareName = null;

                foreach (string raw in root.GetSubKeyNames())
                {
                    string name = Unescape(raw);

                    // These names reach a command line, so skip any that could read as a switch.
                    if (name.Length == 0 || name[0] == '-' || name.IndexOf('"') >= 0) continue;

                    if (string.Equals(name, host, StringComparison.OrdinalIgnoreCase))
                        return name;

                    if (byBareName == null && string.Equals(name, bare, StringComparison.OrdinalIgnoreCase))
                        byBareName = name;

                    using (RegistryKey s = root.OpenSubKey(raw))
                    {
                        if (s == null) continue;
                        if (!string.Equals(s.GetValue("HostName") as string, host,
                                           StringComparison.OrdinalIgnoreCase)) continue;

                        if (byHostName == null) byHostName = name;

                        if (byHostAndPort == null && port != null)
                        {
                            object pn = s.GetValue("PortNumber");
                            if (pn != null && Convert.ToInt32(pn).ToString() == port)
                                byHostAndPort = name;
                        }
                    }
                }

                return byHostAndPort ?? byHostName ?? byBareName;
            }
        }
        catch (Exception)
        {
            return null;   // no sessions, or no access: fall back to a plain connection
        }
    }

    private static string FindPutty()
    {
        string env = Environment.GetEnvironmentVariable("PUTTY_PATH");
        if (!string.IsNullOrEmpty(env) && File.Exists(env)) return env;

        string here = Path.GetDirectoryName(Application.ExecutablePath);
        foreach (string dir in new[]
                 {
                     here,
                     Environment.GetEnvironmentVariable("ProgramW6432"),
                     Environment.GetEnvironmentVariable("ProgramFiles"),
                     Environment.GetEnvironmentVariable("ProgramFiles(x86)"),
                     Environment.GetEnvironmentVariable("LOCALAPPDATA")
                 })
        {
            if (string.IsNullOrEmpty(dir)) continue;
            foreach (string candidate in new[]
                     {
                         Path.Combine(dir, "putty.exe"),
                         Path.Combine(dir, @"PuTTY\putty.exe"),
                         Path.Combine(dir, @"Programs\PuTTY\putty.exe")
                     })
            {
                if (File.Exists(candidate)) return candidate;
            }
        }

        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (string dir in path.Split(Path.PathSeparator))
        {
            if (dir.Trim().Length == 0) continue;
            try
            {
                string candidate = Path.Combine(dir.Trim(), "putty.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch (ArgumentException) { }
        }
        return null;
    }

    private static int Fail(string message)
    {
        MessageBox.Show(message, "PuTTY URL handler",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
        return 1;
    }
}

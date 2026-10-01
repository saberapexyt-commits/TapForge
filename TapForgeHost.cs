using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;

// TapForge.exe - single-file launcher.
// AutoClicker.ps1, the logo, the icon and VERSION are embedded as resources and
// unpacked to %LOCALAPPDATA%\TapForge\App on start, so friends only need this exe.
// Developer copy: if a file named "TapForge.dev" sits beside the exe, the loose
// AutoClicker.ps1 next to it is used instead, so edits apply without rebuilding.
internal static class TapForgeHost
{
    static readonly string[] Payload = { "AutoClicker.ps1", "TapForgeLogo.png", "TapForge.ico", "VERSION" };

    [STAThread]
    private static int Main()
    {
        bool created;
        using (Mutex mutex = new Mutex(true, "Local\\TapForge.SingleInstance", out created))
        {
            if (!created)
            {
                MessageBox.Show("TapForge is already running. Look for it on your taskbar or in the notification area.", "TapForge", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 0;
            }
            try { return Run(); }
            finally { mutex.ReleaseMutex(); }
        }
    }

    private static int Run()
    {
        string exePath = Application.ExecutablePath;
        string exeDir = Path.GetDirectoryName(exePath);
        string appDir;
        if (File.Exists(Path.Combine(exeDir, "TapForge.dev")) && File.Exists(Path.Combine(exeDir, "AutoClicker.ps1")))
        {
            appDir = exeDir;
        }
        else
        {
            appDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TapForge", "App");
            string error = Extract(appDir);
            if (error != null)
            {
                MessageBox.Show(error, "TapForge", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        string scriptPath = Path.Combine(appDir, "AutoClicker.ps1");
        try
        {
            InitialSessionState state = InitialSessionState.CreateDefault();
            state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace runspace = RunspaceFactory.CreateRunspace(state))
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                runspace.Open();
                // Event handlers created from PowerShell run on this thread; give
                // them the runspace that started the script.
                Runspace.DefaultRunspace = runspace;
                runspace.SessionStateProxy.SetVariable("TapForgeExePath", exePath);
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript("& '" + scriptPath.Replace("'", "''") + "'");
                    shell.Invoke();
                    bool appReady = object.Equals(runspace.SessionStateProxy.GetVariable("TapForgeReady"), true);
                    if (shell.HadErrors && !appReady)
                    {
                        string message = "TapForge could not start.\r\n\r\n" + shell.Streams.Error[0].ToString();
                        MessageBox.Show(message, "TapForge", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return 1;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("TapForge could not start.\r\n\r\n" + ex.Message, "TapForge", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }

    private static string Extract(string dir)
    {
        try
        {
            Directory.CreateDirectory(dir);
            Assembly asm = Assembly.GetExecutingAssembly();
            foreach (string name in Payload)
            {
                using (Stream s = asm.GetManifestResourceStream("TapForge." + name))
                {
                    if (s == null) return "This TapForge.exe is incomplete (" + name + " is missing). Please download it again.";
                    byte[] data = new byte[s.Length];
                    int read = 0;
                    while (read < data.Length)
                    {
                        int n = s.Read(data, read, data.Length - read);
                        if (n <= 0) break;
                        read += n;
                    }
                    string target = Path.Combine(dir, name);
                    if (File.Exists(target) && SameBytes(File.ReadAllBytes(target), data)) continue;
                    File.WriteAllBytes(target, data);
                }
            }
            return null;
        }
        catch (Exception ex)
        {
            return "TapForge could not unpack its files.\r\n\r\n" + ex.Message;
        }
    }

    private static bool SameBytes(byte[] a, byte[] b)
    {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
        return true;
    }
}

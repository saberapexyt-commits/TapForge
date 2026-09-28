using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;

internal static class TapForgeHost
{
    [STAThread]
    private static int Main()
    {
        string scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "AutoClicker.ps1");
        if (!File.Exists(scriptPath))
        {
            MessageBox.Show("AutoClicker.ps1 must be beside TapForge.exe.", "TapForge", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        try
        {
            InitialSessionState state = InitialSessionState.CreateDefault();
            state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace runspace = RunspaceFactory.CreateRunspace(state))
            {
                runspace.ApartmentState = System.Threading.ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                runspace.Open();
                // WinForms event handlers created from PowerShell run on this
                // thread. Give those callbacks the same runspace used to start
                // the script so tray actions can safely invoke scriptblocks.
                Runspace.DefaultRunspace = runspace;
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript("& '" + scriptPath.Replace("'", "''") + "'");
                    shell.Invoke();
                    // Errors raised by already-running WinForms event handlers
                    // can remain in this invocation's stream after the window
                    // closes. Only treat errors as a startup failure if the UI
                    // never reached its ready state.
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
}

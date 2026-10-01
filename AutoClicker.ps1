# TapForge 4 - generated from source parts. Edit the parts, not this header.
$engineSource = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;
using System.Diagnostics;
using System.Threading;
using System.Runtime.InteropServices;
public static class ClickNative {
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("uxtheme.dll", CharSet=CharSet.Unicode)] static extern int SetWindowTheme(IntPtr hwnd, string appName, string idList);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    [DllImport("user32.dll")] public static extern bool ShowScrollBar(IntPtr hwnd,int bar,bool show);
    public static void ApplyDarkControl(IntPtr hwnd) { if(hwnd==IntPtr.Zero)return; SetWindowTheme(hwnd,"DarkMode_Explorer",null); }
    public static void ApplyDarkTitle(IntPtr hwnd) { if(hwnd==IntPtr.Zero)return; int value=1; DwmSetWindowAttribute(hwnd,20,ref value,4); DwmSetWindowAttribute(hwnd,19,ref value,4); }
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint period);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint period);
    static Thread worker;
    static volatile bool active;
    static bool periodSet;
    static long sent;
    static uint down, up;
    static int randomPct, holdPct, maxClicks, maxSeconds, cornerPx, edgePx, keyCode, clicksPerPoint=1;
    static bool useCorner, useEdge, keyboard, doubleClick;
    static int[] points=new int[0];
    static int pointRadius;
    static Random rng=new Random();
    public static int TargetProcessId;
    static void HoldFor(int ms) { long end=Stopwatch.GetTimestamp()+(long)(Stopwatch.Frequency*ms/1000.0); while(active && Stopwatch.GetTimestamp()<end) Thread.Sleep(1); }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X,Y; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk,byte scan,uint flags,UIntPtr extra);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint processId);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateWaitableTimerExW(IntPtr attributes,string name,uint flags,uint access);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetWaitableTimer(IntPtr timer,ref long dueTime,int period,IntPtr callback,IntPtr arg,bool resume);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint ms);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [StructLayout(LayoutKind.Sequential)] struct PowerThrottlingState { public uint Version,ControlMask,StateMask; }
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetProcessInformation(IntPtr process,int infoClass,ref PowerThrottlingState info,int size);
    static bool throttlingDisabled;
    // Windows 11 ignores 1 ms timer requests from apps whose window is hidden or
    // minimized (e.g. while a game is in front), which capped speed near 64 CPS.
    // Opt this process out of that throttling and of EcoQoS.
    static void DisablePowerThrottling(){ if(throttlingDisabled)return; throttlingDisabled=true; try{ PowerThrottlingState st=new PowerThrottlingState(); st.Version=1; st.ControlMask=0x1|0x4; st.StateMask=0; SetProcessInformation(GetCurrentProcess(),4,ref st,Marshal.SizeOf(typeof(PowerThrottlingState))); }catch(Exception){} }
    // Waits until the stopwatch reaches target using a high-resolution waitable
    // timer (sub-millisecond on Windows 10 1803+), finishing with a short spin.
    static void WaitUntil(long target,IntPtr timer,long frequency){
        while(active){
            long remaining=target-Stopwatch.GetTimestamp();
            if(remaining<=0) return;
            double ms=remaining*1000.0/frequency;
            if(ms>1.0){
                double chunk=Math.Min(ms-0.5,50.0);
                if(timer!=IntPtr.Zero){ long due=-(long)(chunk*10000.0); if(SetWaitableTimer(timer,ref due,0,IntPtr.Zero,IntPtr.Zero,false)){ WaitForSingleObject(timer,100); continue; } }
                Thread.Sleep(ms>2.0?1:0);
            } else Thread.Yield();
        }
    }
    public static void Configure(int random,int hold,int clicks,int seconds,bool corner,int cornerSize,bool edge,int edgeSize,bool keyMode,int key,bool dbl,int[] clickPoints,int radius,int pointClicks) {
        randomPct=random;holdPct=hold;maxClicks=clicks;maxSeconds=seconds;useCorner=corner;cornerPx=cornerSize;useEdge=edge;edgePx=edgeSize;
        keyboard=keyMode;keyCode=key;doubleClick=dbl;points=clickPoints??new int[0];pointRadius=Math.Max(0,radius);clicksPerPoint=Math.Max(1,pointClicks);
    }
    public static long Count { get { return Interlocked.Read(ref sent); } }
    public static bool Active { get { return active; } }
    public static int[] Cursor { get { POINT p; GetCursorPos(out p); return new int[]{p.X,p.Y}; } }
    public static void Start(uint downFlag, uint upFlag, double intervalMs) {
        Stop(); DisablePowerThrottling(); periodSet=(timeBeginPeriod(1)==0); if(intervalMs<0.1) intervalMs=0.1; down=downFlag; up=upFlag; Interlocked.Exchange(ref sent,0); active=true;
        worker=new Thread(() => {
            long frequency=Stopwatch.Frequency;
            double period=Math.Max(1.0, frequency * (intervalMs / 1000.0));
            long started=Stopwatch.GetTimestamp(); double next=started; int pointIndex=0,clicksAtPoint=0;
            IntPtr timer=CreateWaitableTimerExW(IntPtr.Zero,null,0x2,0x1F0003);
            if(timer==IntPtr.Zero) timer=CreateWaitableTimerExW(IntPtr.Zero,null,0,0x1F0003);
            try {
            while(active) {
                if(maxSeconds>0 && (Stopwatch.GetTimestamp()-started)/((double)frequency)>=maxSeconds) { active=false; break; }
                if(TargetProcessId>0) { uint foregroundPid; GetWindowThreadProcessId(GetForegroundWindow(),out foregroundPid); if(foregroundPid!=(uint)TargetProcessId) { Thread.Sleep(1); continue; } }
                POINT pos; GetCursorPos(out pos);
                System.Drawing.Rectangle bounds=System.Windows.Forms.SystemInformation.VirtualScreen;
                if(useCorner && ((pos.X<bounds.Left+cornerPx&&pos.Y<bounds.Top+cornerPx)||(pos.X<bounds.Left+cornerPx&&pos.Y>=bounds.Bottom-cornerPx)||(pos.X>=bounds.Right-cornerPx&&pos.Y<bounds.Top+cornerPx)||(pos.X>=bounds.Right-cornerPx&&pos.Y>=bounds.Bottom-cornerPx))) { active=false; break; }
                if(useEdge && (pos.X<bounds.Left+edgePx||pos.Y<bounds.Top+edgePx||pos.X>=bounds.Right-edgePx||pos.Y>=bounds.Bottom-edgePx)) { active=false; break; }
                if(!active) break;
                if(points.Length>=2 && clicksAtPoint==0) { int px=points[pointIndex],py=points[pointIndex+1];if(pointRadius>0){double a=rng.NextDouble()*Math.PI*2,r=Math.Sqrt(rng.NextDouble())*pointRadius;px+=(int)Math.Round(Math.Cos(a)*r);py+=(int)Math.Round(Math.Sin(a)*r);}if(px!=pos.X||py!=pos.Y) SetCursorPos(px,py); }
                int repeats=doubleClick?2:1;
                for(int n=0;n<repeats && active;n++) {
                    if(keyboard) { keybd_event((byte)keyCode,0,0,UIntPtr.Zero); if(holdPct>0) HoldFor((int)Math.Max(1,intervalMs*holdPct/100.0)); keybd_event((byte)keyCode,0,2,UIntPtr.Zero); }
                    else { mouse_event(down,0,0,0,UIntPtr.Zero); if(holdPct>0) HoldFor((int)Math.Max(1,intervalMs*holdPct/100.0)); mouse_event(up,0,0,0,UIntPtr.Zero); }
                    Interlocked.Increment(ref sent);
                    if(points.Length>=2 && ++clicksAtPoint>=clicksPerPoint){clicksAtPoint=0;pointIndex=(pointIndex+2)%points.Length;}
                    if(maxClicks>0 && Count>=maxClicks) { active=false; break; }
                }
                int variation=randomPct==0?0:rng.Next(-randomPct,randomPct+1);
                next += Math.Max(1.0,period*(100+variation)/100.0);
                // After a stall (PC lag, window drag), resync instead of firing a catch-up burst.
                long now=Stopwatch.GetTimestamp();
                if(next < now - frequency/20) next=now;
                WaitUntil((long)next,timer,frequency);
            }
            } finally { if(timer!=IntPtr.Zero) CloseHandle(timer); }
        }); worker.IsBackground=true; worker.Priority=ThreadPriority.Highest; worker.Start();
    }
    public static void Stop() { active=false; if(worker!=null && worker.IsAlive) worker.Join(100); worker=null; if(periodSet){timeEndPeriod(1);periodSet=false;} }
}

public static class LogoColorizer {
    static Color HsvToColor(double h,double s,double v,int alpha){double c=v*s,x=c*(1-Math.Abs((h/60.0%2)-1)),m=v-c,r=0,g=0,b=0;if(h<60){r=c;g=x;}else if(h<120){r=x;g=c;}else if(h<180){g=c;b=x;}else if(h<240){g=x;b=c;}else if(h<300){r=x;b=c;}else{r=c;b=x;}return Color.FromArgb(alpha,(int)Math.Round((r+m)*255),(int)Math.Round((g+m)*255),(int)Math.Round((b+m)*255));}
    public static Bitmap Tint(Bitmap source,Color accent){Bitmap normalized=new Bitmap(source.Width,source.Height,PixelFormat.Format32bppArgb);using(Graphics g=Graphics.FromImage(normalized)){g.DrawImage(source,0,0,source.Width,source.Height);}Bitmap result=new Bitmap(source.Width,source.Height,PixelFormat.Format32bppArgb);Rectangle area=new Rectangle(0,0,source.Width,source.Height);BitmapData input=normalized.LockBits(area,ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);BitmapData output=result.LockBits(area,ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);byte[] row=new byte[source.Width*4];for(int y=0;y<source.Height;y++){Marshal.Copy(IntPtr.Add(input.Scan0,y*input.Stride),row,0,row.Length);for(int x=0;x<source.Width;x++){int i=x*4,b=row[i],g=row[i+1],r=row[i+2],a=row[i+3];int max=Math.Max(r,Math.Max(g,b)),min=Math.Min(r,Math.Min(g,b)),delta=max-min;double h=0,s=max==0?0:delta/(double)max,v=max/255.0;if(delta>0){if(max==r)h=60.0*(((g-b)/(double)delta)%6);else if(max==g)h=60.0*(((b-r)/(double)delta)+2);else h=60.0*(((r-g)/(double)delta)+4);if(h<0)h+=360;}if(a>0&&h>=245&&h<=325&&s>=0.24&&v>=0.26){row[i]=(byte)Math.Round(accent.B*v);row[i+1]=(byte)Math.Round(accent.G*v);row[i+2]=(byte)Math.Round(accent.R*v);}}Marshal.Copy(row,0,IntPtr.Add(output.Scan0,y*output.Stride),row.Length);}normalized.UnlockBits(input);result.UnlockBits(output);normalized.Dispose();return result;}
    public static Icon MakeIcon(Bitmap bitmap){using(Bitmap small=new Bitmap(64,64,PixelFormat.Format32bppArgb)){using(Graphics g=Graphics.FromImage(small)){g.Clear(Color.Transparent);g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.SmoothingMode=SmoothingMode.HighQuality;g.PixelOffsetMode=PixelOffsetMode.HighQuality;g.DrawImage(bitmap,0,0,64,64);}IntPtr handle=small.GetHicon();try{using(Icon icon=Icon.FromHandle(handle)){return (Icon)icon.Clone();}}finally{ClickNative.DestroyIcon(handle);}}}
}

public static class TapForgeShell {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    // Render crisply on high-DPI screens instead of being bitmap-stretched by Windows.
    public static void EnableDpiAwareness() { try { SetProcessDPIAware(); } catch (Exception) { } }
    // Windows 11 rounded corners + dark frame for a borderless window. Harmless on Windows 10.
    public static void StyleWindow(IntPtr hwnd, bool dark) {
        if (hwnd == IntPtr.Zero) return;
        try {
            int round = 2; DwmSetWindowAttribute(hwnd, 33, ref round, 4);
            int d = dark ? 1 : 0; DwmSetWindowAttribute(hwnd, 20, ref d, 4); DwmSetWindowAttribute(hwnd, 19, ref d, 4);
        } catch (Exception) { }
    }
}

// Small background HTTP helper so update checks and downloads never freeze the window.
// PowerShell polls Done from a UI timer.
public sealed class TapForgeRequest {
    public volatile bool Done;
    public string Text;
    public string Error;
    public long Received;
    public long Total = -1;
    public static TapForgeRequest GetText(string url) {
        TapForgeRequest r = new TapForgeRequest();
        Thread t = new Thread(delegate() { r.Run(url, null); });
        t.IsBackground = true; t.Start(); return r;
    }
    public static TapForgeRequest Download(string url, string path) {
        TapForgeRequest r = new TapForgeRequest();
        Thread t = new Thread(delegate() { r.Run(url, path); });
        t.IsBackground = true; t.Start(); return r;
    }
    void Run(string url, string path) {
        try {
            System.Net.ServicePointManager.SecurityProtocol = System.Net.SecurityProtocolType.Tls12;
            System.Net.HttpWebRequest req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url);
            req.Method = "GET"; req.UserAgent = "TapForge-Updater"; req.Accept = "application/vnd.github+json";
            req.Timeout = path == null ? 8000 : 30000; req.ReadWriteTimeout = path == null ? 8000 : 30000;
            using (System.Net.WebResponse resp = req.GetResponse())
            using (System.IO.Stream input = resp.GetResponseStream()) {
                Total = resp.ContentLength;
                if (path == null) {
                    using (System.IO.StreamReader reader = new System.IO.StreamReader(input)) { Text = reader.ReadToEnd(); }
                } else {
                    using (System.IO.FileStream file = System.IO.File.Create(path)) {
                        byte[] buffer = new byte[65536]; int n;
                        while ((n = input.Read(buffer, 0, buffer.Length)) > 0) { file.Write(buffer, 0, n); Received += n; }
                    }
                }
            }
        } catch (Exception ex) { Error = ex.Message; }
        Done = true;
    }
}
'@
$uiSource = @'
using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace TapForgeUI {
    // Themed numeric input (WPF has none built in): text field + up/down arrows,
    // mouse wheel while focused, arrow keys, and press-and-hold repeat.
    public class NumberBox : Border {
        readonly TextBox box = new TextBox();
        readonly DispatcherTimer repeat = new DispatcherTimer();
        int repeatDir;
        double val;
        double min;
        double max = 100;
        double inc = 1;
        int decimals;
        bool suppress;
        public event EventHandler ValueChanged;

        public NumberBox() {
            CornerRadius = new CornerRadius(8);
            BorderThickness = new Thickness(1);
            Height = 34;
            SnapsToDevicePixels = true;
            SetResourceReference(BackgroundProperty, "Input");
            SetResourceReference(BorderBrushProperty, "InputBorder");

            Grid grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            ColumnDefinition spinCol = new ColumnDefinition();
            spinCol.Width = new GridLength(24);
            grid.ColumnDefinitions.Add(spinCol);

            box.Style = new Style(typeof(TextBox));
            box.Background = Brushes.Transparent;
            box.BorderThickness = new Thickness(0);
            box.VerticalContentAlignment = VerticalAlignment.Center;
            box.Padding = new Thickness(8, 0, 2, 0);
            box.FontSize = 13;
            box.SetResourceReference(Control.ForegroundProperty, "Text");
            box.SetResourceReference(TextBoxBase.CaretBrushProperty, "Text");
            box.SetResourceReference(TextBoxBase.SelectionBrushProperty, "Accent");
            box.KeyDown += OnKey;
            box.GotKeyboardFocus += delegate(object s, KeyboardFocusChangedEventArgs e) { SetResourceReference(BorderBrushProperty, "Accent"); };
            box.LostKeyboardFocus += delegate(object s, KeyboardFocusChangedEventArgs e) { SetResourceReference(BorderBrushProperty, "InputBorder"); Commit(); };
            grid.Children.Add(box);

            StackPanel spin = new StackPanel();
            spin.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(spin, 1);
            spin.Children.Add(MakeArrow(1));
            spin.Children.Add(MakeArrow(-1));
            grid.Children.Add(spin);
            Child = grid;

            repeat.Tick += delegate(object s, EventArgs e) { repeat.Interval = TimeSpan.FromMilliseconds(45); Step(repeatDir); };
            PreviewMouseWheel += delegate(object s, MouseWheelEventArgs e) {
                if (IsEnabled && box.IsKeyboardFocusWithin) { Step(e.Delta > 0 ? 1 : -1); e.Handled = true; }
            };
            IsEnabledChanged += delegate(object s, DependencyPropertyChangedEventArgs e) { Opacity = IsEnabled ? 1.0 : 0.45; };
            UpdateText();
        }

        FrameworkElement MakeArrow(int dir) {
            Border b = new Border();
            b.Width = 20; b.Height = 14;
            b.CornerRadius = new CornerRadius(4);
            b.Background = Brushes.Transparent;
            b.Cursor = Cursors.Hand;
            Path p = new Path();
            p.Data = Geometry.Parse(dir > 0 ? "M0,4 L4,0 L8,4" : "M0,0 L4,4 L8,0");
            p.StrokeThickness = 1.6;
            p.HorizontalAlignment = HorizontalAlignment.Center;
            p.VerticalAlignment = VerticalAlignment.Center;
            p.SetResourceReference(Shape.StrokeProperty, "Muted");
            b.Child = p;
            b.MouseEnter += delegate(object s, MouseEventArgs e) { b.SetResourceReference(Border.BackgroundProperty, "Hover"); p.SetResourceReference(Shape.StrokeProperty, "Accent"); };
            b.MouseLeave += delegate(object s, MouseEventArgs e) { b.Background = Brushes.Transparent; p.SetResourceReference(Shape.StrokeProperty, "Muted"); };
            b.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e) {
                if (!IsEnabled) return;
                Commit(); Step(dir); repeatDir = dir;
                repeat.Interval = TimeSpan.FromMilliseconds(400); repeat.Start();
                b.CaptureMouse(); e.Handled = true;
            };
            b.MouseLeftButtonUp += delegate(object s, MouseButtonEventArgs e) { repeat.Stop(); b.ReleaseMouseCapture(); e.Handled = true; };
            b.LostMouseCapture += delegate(object s, MouseEventArgs e) { repeat.Stop(); };
            return b;
        }

        void OnKey(object sender, KeyEventArgs e) {
            if (e.Key == Key.Enter) { Commit(); box.SelectAll(); e.Handled = true; }
            else if (e.Key == Key.Up) { Commit(); Step(1); e.Handled = true; }
            else if (e.Key == Key.Down) { Commit(); Step(-1); e.Handled = true; }
        }

        void Step(int dir) { Value = val + dir * inc; }

        void Commit() {
            double parsed;
            string t = box.Text.Trim();
            if (double.TryParse(t, NumberStyles.Float, CultureInfo.InvariantCulture, out parsed) ||
                double.TryParse(t, NumberStyles.Any, CultureInfo.CurrentCulture, out parsed)) {
                Value = parsed;
            } else {
                UpdateText();
            }
        }

        double Clamp(double v) {
            if (double.IsNaN(v) || double.IsInfinity(v)) v = min;
            if (v < min) v = min;
            if (v > max) v = max;
            return Math.Round(v, decimals);
        }

        void UpdateText() { box.Text = val.ToString("F" + decimals, CultureInfo.InvariantCulture); }

        public double Value {
            get { return val; }
            set {
                double v = Clamp(value);
                bool changed = v != val;
                val = v;
                UpdateText();
                if (changed && !suppress && ValueChanged != null) ValueChanged(this, EventArgs.Empty);
            }
        }
        public double Minimum { get { return min; } set { min = value; if (val < min) Value = min; } }
        public double Maximum { get { return max; } set { max = value; if (val > max) Value = max; } }
        public int Decimals { get { return decimals; } set { decimals = Math.Max(0, Math.Min(6, value)); Value = val; UpdateText(); } }
        public double Increment { get { return inc; } set { inc = value; } }

        // Change limits/format and value without raising ValueChanged.
        public void Configure(double minimum, double maximum, int places, double increment, double value) {
            min = minimum; max = maximum; decimals = Math.Max(0, Math.Min(6, places)); inc = increment;
            val = Clamp(value); UpdateText();
        }
        public void SetQuiet(double v) { suppress = true; try { Value = v; } finally { suppress = false; } }
    }
}
'@
$resourcesXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

  <!-- Theme colors. These brushes are replaced at runtime by Apply-Theme / Set-Accent. -->
  <SolidColorBrush x:Key="Bg" Color="#0E0E10"/>
  <SolidColorBrush x:Key="Chrome" Color="#151517"/>
  <SolidColorBrush x:Key="Card" Color="#1A1A1D"/>
  <SolidColorBrush x:Key="CardBorder" Color="#2A2A2F"/>
  <SolidColorBrush x:Key="Input" Color="#222226"/>
  <SolidColorBrush x:Key="InputBorder" Color="#34343B"/>
  <SolidColorBrush x:Key="Hover" Color="#28282D"/>
  <SolidColorBrush x:Key="Text" Color="#F2F2F5"/>
  <SolidColorBrush x:Key="Muted" Color="#9A9AA5"/>
  <SolidColorBrush x:Key="SwitchOff" Color="#3A3A42"/>
  <SolidColorBrush x:Key="ScrollThumb" Color="#3A3A42"/>
  <SolidColorBrush x:Key="Accent" Color="#7B61FF"/>
  <SolidColorBrush x:Key="AccentSoft" Color="#337B61FF"/>
  <SolidColorBrush x:Key="OnAccent" Color="#FFFFFF"/>
  <SolidColorBrush x:Key="Good" Color="#5FD39B"/>
  <SolidColorBrush x:Key="Warn" Color="#FFC45F"/>
  <SolidColorBrush x:Key="Danger" Color="#FF6B6B"/>

  <FontFamily x:Key="IconFont">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>

  <!-- Text styles -->
  <Style x:Key="Glyph" TargetType="TextBlock">
    <Setter Property="FontFamily" Value="{StaticResource IconFont}"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
  </Style>
  <Style x:Key="PageTitle" TargetType="TextBlock">
    <Setter Property="FontSize" Value="20"/>
    <Setter Property="FontWeight" Value="Bold"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Margin" Value="2,0,0,12"/>
  </Style>
  <Style x:Key="CardTitle" TargetType="TextBlock">
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
  </Style>
  <Style x:Key="CardSub" TargetType="TextBlock">
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
    <Setter Property="Margin" Value="0,2,0,0"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
  </Style>
  <Style x:Key="RowTitle" TargetType="TextBlock">
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
  </Style>
  <Style x:Key="RowSub" TargetType="TextBlock">
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
    <Setter Property="Margin" Value="0,2,12,0"/>
  </Style>
  <Style x:Key="FieldLabel" TargetType="TextBlock">
    <Setter Property="FontSize" Value="11"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
    <Setter Property="Margin" Value="0,0,0,6"/>
  </Style>
  <Style x:Key="StatValue" TargetType="TextBlock">
    <Setter Property="FontSize" Value="20"/>
    <Setter Property="FontWeight" Value="Bold"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
  </Style>

  <!-- Surfaces -->
  <Style x:Key="Panel" TargetType="Border">
    <Setter Property="Background" Value="{DynamicResource Card}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="CornerRadius" Value="12"/>
    <Setter Property="Padding" Value="16,14"/>
    <Setter Property="Margin" Value="0,0,0,12"/>
    <Setter Property="SnapsToDevicePixels" Value="True"/>
  </Style>
  <Style x:Key="Divider" TargetType="Border">
    <Setter Property="Height" Value="1"/>
    <Setter Property="Background" Value="{DynamicResource CardBorder}"/>
    <Setter Property="Margin" Value="0,12"/>
  </Style>

  <!-- Buttons -->
  <Style TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Background" Value="{DynamicResource Input}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="14,0"/>
    <Setter Property="Height" Value="34"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="SnapsToDevicePixels" Value="True"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Bd" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="Bd" Property="Opacity" Value="0.75"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.45"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="{DynamicResource Hover}"/>
      </Trigger>
    </Style.Triggers>
  </Style>
  <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="Background" Value="{DynamicResource Accent}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
    <Setter Property="Foreground" Value="{DynamicResource OnAccent}"/>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="{DynamicResource Accent}"/>
        <Setter Property="Opacity" Value="0.88"/>
      </Trigger>
    </Style.Triggers>
  </Style>
  <Style x:Key="TitleButton" TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Width" Value="36"/>
    <Setter Property="Height" Value="32"/>
    <Setter Property="FontFamily" Value="{StaticResource IconFont}"/>
    <Setter Property="FontSize" Value="15"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Margin" Value="1,0"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Bd" CornerRadius="7" Background="{TemplateBinding Background}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="Bd" Property="Opacity" Value="0.7"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="{DynamicResource Hover}"/>
        <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      </Trigger>
    </Style.Triggers>
  </Style>
  <Style x:Key="CaptionButton" TargetType="Button" BasedOn="{StaticResource TitleButton}">
    <Setter Property="FontSize" Value="10"/>
    <Setter Property="Width" Value="40"/>
  </Style>
  <Style x:Key="CloseButton" TargetType="Button" BasedOn="{StaticResource CaptionButton}">
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="#E5484D"/>
        <Setter Property="Foreground" Value="White"/>
      </Trigger>
    </Style.Triggers>
  </Style>

  <!-- Sidebar entries -->
  <Style x:Key="SideItem" TargetType="RadioButton">
    <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
    <Setter Property="Height" Value="36"/>
    <Setter Property="Margin" Value="0,0,0,3"/>
    <Setter Property="FontSize" Value="13.5"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="GroupName" Value="SideNav"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Grid>
            <Border x:Name="Bd" CornerRadius="8" Background="Transparent"/>
            <Border x:Name="Ind" Width="3" Height="16" CornerRadius="2" HorizontalAlignment="Left" Background="{DynamicResource Accent}" Visibility="Collapsed"/>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,8,0">
              <TextBlock Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" FontFamily="{StaticResource IconFont}"
                         FontSize="15" Width="24" VerticalAlignment="Center" Foreground="{TemplateBinding Foreground}"/>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Hover}"/>
              <Setter Property="Foreground" Value="{DynamicResource Text}"/>
            </Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Hover}"/>
              <Setter TargetName="Ind" Property="Visibility" Value="Visible"/>
              <Setter Property="Foreground" Value="{DynamicResource Text}"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Toggle switch (CheckBox) -->
  <Style x:Key="Switch" TargetType="CheckBox">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Grid Width="42" Height="24" Background="Transparent">
            <Border x:Name="Track" CornerRadius="12" Background="{DynamicResource SwitchOff}"/>
            <Ellipse x:Name="Thumb" Width="16" Height="16" Fill="White" HorizontalAlignment="Left" Margin="4,0,0,0"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="Track" Property="Background" Value="{DynamicResource Accent}"/>
              <Setter TargetName="Thumb" Property="Margin" Value="22,0,0,0"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.45"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Text input -->
  <Style TargetType="TextBox">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="CaretBrush" Value="{DynamicResource Text}"/>
    <Setter Property="SelectionBrush" Value="{DynamicResource Accent}"/>
    <Setter Property="Background" Value="{DynamicResource Input}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Height" Value="34"/>
    <Setter Property="Padding" Value="10,0"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="TextBox">
          <Border x:Name="Bd" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" Focusable="False"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsKeyboardFocused" Value="True">
              <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.45"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Drop-downs -->
  <Style TargetType="ComboBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBoxItem">
          <Border x:Name="Bd" CornerRadius="6" Padding="10,7" Background="Transparent">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentSoft}"/>
            </Trigger>
            <Trigger Property="IsHighlighted" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Hover}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="ComboBox">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Height" Value="34"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="MaxDropDownHeight" Value="300"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBox">
          <Grid>
            <ToggleButton x:Name="Toggle" Focusable="False" ClickMode="Press"
                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
              <ToggleButton.Template>
                <ControlTemplate TargetType="ToggleButton">
                  <Border x:Name="Bd" CornerRadius="8" Background="{DynamicResource Input}" BorderBrush="{DynamicResource InputBorder}" BorderThickness="1">
                    <Path x:Name="Arrow" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,1,12,0" Data="M0,0 L4.5,4.5 L9,0"
                          Stroke="{DynamicResource Muted}" StrokeThickness="1.6"/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                      <Setter TargetName="Arrow" Property="Stroke" Value="{DynamicResource Accent}"/>
                    </Trigger>
                    <Trigger Property="IsChecked" Value="True">
                      <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                      <Setter TargetName="Arrow" Property="Stroke" Value="{DynamicResource Accent}"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </ToggleButton.Template>
            </ToggleButton>
            <ContentPresenter IsHitTestVisible="False" Margin="11,0,30,0" VerticalAlignment="Center" HorizontalAlignment="Left"
                              Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
            <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True"
                   Focusable="False" PopupAnimation="Fade">
              <Border Margin="0,4,0,0" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                      MaxHeight="{TemplateBinding MaxDropDownHeight}" Background="{DynamicResource Card}"
                      BorderBrush="{DynamicResource InputBorder}" BorderThickness="1" CornerRadius="8" Padding="4">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                  <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/>
                </ScrollViewer>
              </Border>
            </Popup>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.45"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Lists -->
  <Style TargetType="ListBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Border x:Name="Bd" CornerRadius="6" Padding="10,7" Margin="0,0,0,2" Background="Transparent">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Hover}"/>
            </Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentSoft}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="ListBox">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBox">
          <Border CornerRadius="8" Background="{DynamicResource Input}" BorderBrush="{DynamicResource InputBorder}" BorderThickness="1" Padding="4">
            <ScrollViewer Focusable="False" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto">
              <ItemsPresenter/>
            </ScrollViewer>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Thin scrollbars -->
  <Style TargetType="ScrollBar">
    <Setter Property="Width" Value="8"/>
    <Setter Property="MinWidth" Value="8"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Grid Background="Transparent">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border CornerRadius="4" Margin="1,2" Background="{DynamicResource ScrollThumb}"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ToolTip">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Background" Value="{DynamicResource Card}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ToolTip">
          <Border CornerRadius="6" Padding="9,5" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
            <ContentPresenter/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Color picker sliders -->
  <Style x:Key="ColorSlider" TargetType="Slider">
    <Setter Property="Height" Value="24"/>
    <Setter Property="IsMoveToPointEnabled" Value="True"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Slider">
          <Grid Background="Transparent">
            <Border Height="10" CornerRadius="5" VerticalAlignment="Center" Margin="9,0" Background="{TemplateBinding Background}"
                    BorderBrush="{DynamicResource InputBorder}" BorderThickness="1"/>
            <Track x:Name="PART_Track">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Ellipse Width="18" Height="18" Fill="White" Stroke="#55000000" StrokeThickness="1"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</ResourceDictionary>
'@
$mainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TapForge" Width="940" Height="680" MinWidth="800" MinHeight="580"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource Chrome}"
        Foreground="{DynamicResource Text}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        UseLayoutRounding="True" SnapsToDevicePixels="True" TextOptions.TextFormattingMode="Display">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="44" ResizeBorderThickness="6" CornerRadius="0" GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>

  <Border x:Name="root" Background="{DynamicResource Chrome}">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="44"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- ===== Title bar ===== -->
      <Grid x:Name="titleBar" Grid.Row="0" Background="Transparent">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="8,0,0,0">
          <Button x:Name="navSettings" Style="{StaticResource TitleButton}" Content="&#xE713;" ToolTip="Settings"/>
          <Button x:Name="navClicking" Style="{StaticResource TitleButton}" Content="&#xE962;" ToolTip="Clicking"/>
          <Button x:Name="navMore" Style="{StaticResource TitleButton}" Content="&#xE81E;" ToolTip="More control"/>
          <Button x:Name="navPoints" Style="{StaticResource TitleButton}" Content="&#xE707;" ToolTip="Click points"/>
        </StackPanel>

        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" IsHitTestVisible="False">
          <Image x:Name="brandLogo" Width="24" Height="24" Margin="0,0,8,0" RenderOptions.BitmapScalingMode="HighQuality"/>
          <TextBlock x:Name="brandTitle" Text="TapForge" FontSize="16" FontWeight="Bold" VerticalAlignment="Center" FontFamily="Segoe UI Variable Display, Segoe UI"/>
        </StackPanel>

        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,4,0">
          <Border x:Name="statusPill" CornerRadius="11" Padding="10,4" Margin="0,0,10,0" Background="{DynamicResource Hover}" VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal">
              <Ellipse x:Name="statusDot" Width="7" Height="7" Fill="{DynamicResource Good}" VerticalAlignment="Center"/>
              <TextBlock x:Name="statusText" Text="READY" FontSize="10.5" FontWeight="Bold" Margin="6,0,0,0" Foreground="{DynamicResource Good}" VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
          <Button x:Name="compactButton" Style="{StaticResource TitleButton}" Content="&#xE73F;" ToolTip="Compact mode"/>
          <Button x:Name="pinButton" Style="{StaticResource TitleButton}" Content="&#xE718;" ToolTip="Keep on top"/>
          <Button x:Name="minButton" Style="{StaticResource CaptionButton}" Content="&#xE921;" ToolTip="Minimize"/>
          <Button x:Name="maxButton" Style="{StaticResource CaptionButton}" Content="&#xE922;" ToolTip="Maximize"/>
          <Button x:Name="closeButton" Style="{StaticResource CloseButton}" Content="&#xE8BB;" ToolTip="Close"/>
        </StackPanel>
      </Grid>

      <!-- ===== Body ===== -->
      <Grid x:Name="body" Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Settings sidebar -->
        <Grid x:Name="sidebar" Grid.Column="0" Width="184" Visibility="Collapsed">
          <StackPanel Margin="10,6,10,0">
            <RadioButton x:Name="sideGeneral" Style="{StaticResource SideItem}" Tag="&#xE946;" Content="General"/>
            <RadioButton x:Name="sideBehavior" Style="{StaticResource SideItem}" Tag="&#xE9E9;" Content="Behavior"/>
            <RadioButton x:Name="sideAppearance" Style="{StaticResource SideItem}" Tag="&#xE790;" Content="Appearance"/>
            <RadioButton x:Name="sideKeybinds" Style="{StaticResource SideItem}" Tag="&#xE765;" Content="Keybinds"/>
            <RadioButton x:Name="sideProcess" Style="{StaticResource SideItem}" Tag="&#xE71D;" Content="Process List"/>
            <RadioButton x:Name="sidePresets" Style="{StaticResource SideItem}" Tag="&#xE74E;" Content="Presets"/>
            <RadioButton x:Name="sideMaintenance" Style="{StaticResource SideItem}" Tag="&#xE90F;" Content="Maintenance"/>
          </StackPanel>
          <Border VerticalAlignment="Bottom" Margin="12,0,12,14" CornerRadius="12" Padding="12,10" Background="{DynamicResource Card}"
                  BorderBrush="{DynamicResource CardBorder}" BorderThickness="1">
            <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Image x:Name="sideLogo" Width="22" Height="22" RenderOptions.BitmapScalingMode="HighQuality"/>
                <TextBlock Text="TapForge" FontWeight="Bold" FontSize="13.5" Margin="8,0,0,0" VerticalAlignment="Center"/>
              </StackPanel>
              <TextBlock x:Name="sideVersion" Text="v4.0.0" Style="{StaticResource CardSub}" Margin="0,6,0,0"/>
              <Button x:Name="sideGithub" Content="View on GitHub" Margin="0,10,0,0" Height="30" FontSize="12"/>
            </StackPanel>
          </Border>
        </Grid>

        <!-- Content area with the accent edge -->
        <Border x:Name="contentFrame" Grid.Column="1" CornerRadius="14,0,0,0" BorderThickness="1.5,1.5,0,0"
                BorderBrush="{DynamicResource Accent}" Background="{DynamicResource Bg}">
          <Grid x:Name="pages">

            <!-- Clicking -->
            <ScrollViewer x:Name="pageClicking" VerticalScrollBarVisibility="Auto" Padding="16,14,16,4">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="1.2*"/>
                  <ColumnDefinition Width="12"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Border Style="{StaticResource Panel}" Margin="0">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Click settings"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Set your click pattern and when to stop."/>

                    <Grid Margin="0,16,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="12"/>
                        <ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource FieldLabel}" Text="MOUSE BUTTON"/>
                        <ComboBox x:Name="buttonPick"/>
                      </StackPanel>
                      <StackPanel Grid.Column="2">
                        <TextBlock Style="{StaticResource FieldLabel}" Text="CLICK TYPE"/>
                        <ComboBox x:Name="clickTypePick"/>
                      </StackPanel>
                    </Grid>

                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="12"/>
                        <ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource FieldLabel}" Text="SPEED MODE"/>
                        <ComboBox x:Name="speedMode"/>
                      </StackPanel>
                      <StackPanel Grid.Column="2">
                        <TextBlock x:Name="speedValueLabel" Style="{StaticResource FieldLabel}" Text="INTERVAL"/>
                        <Grid x:Name="intervalRow">
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                          </Grid.ColumnDefinitions>
                          <ContentControl x:Name="intervalHost" Focusable="False"/>
                          <ComboBox x:Name="intervalUnit" Grid.Column="1" Width="78" Margin="8,0,0,0"/>
                        </Grid>
                        <ContentControl x:Name="rateHost" Focusable="False" Visibility="Collapsed"/>
                      </StackPanel>
                    </Grid>
                    <TextBlock x:Name="speedHint" FontSize="12" Foreground="{DynamicResource Accent}" Margin="0,8,0,0" TextWrapping="Wrap"/>

                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="12"/>
                        <ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource FieldLabel}" Text="STOP AFTER"/>
                        <ComboBox x:Name="modePick"/>
                      </StackPanel>
                      <StackPanel Grid.Column="2">
                        <TextBlock Style="{StaticResource FieldLabel}" Text="LIMIT"/>
                        <Grid>
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                          </Grid.ColumnDefinitions>
                          <ContentControl x:Name="limitHost" Focusable="False"/>
                          <TextBlock x:Name="limitUnit" Grid.Column="1" Text="clicks" Foreground="{DynamicResource Muted}" VerticalAlignment="Center" Margin="8,0,0,0" MinWidth="50"/>
                        </Grid>
                      </StackPanel>
                    </Grid>

                    <Border Style="{StaticResource Divider}" Margin="0,16,0,12"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Style="{StaticResource Glyph}" Text="&#xE765;" Foreground="{DynamicResource Muted}" FontSize="14"/>
                        <TextBlock x:Name="hotkeyCaption" Text="F6 start / stop  ·  F7 emergency stop" Foreground="{DynamicResource Muted}" Margin="8,0,0,0" VerticalAlignment="Center" FontSize="12"/>
                      </StackPanel>
                      <Button x:Name="editKeysButton" Grid.Column="1" Content="Change keys" Height="28" FontSize="12" Padding="10,0"/>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border Grid.Column="2" Style="{StaticResource Panel}" Margin="0">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Live monitor"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Updates while clicking."/>
                    <TextBlock Style="{StaticResource FieldLabel}" Text="CLICKS SENT" Margin="0,18,0,2"/>
                    <TextBlock x:Name="countLabel" Text="0" FontSize="40" FontWeight="Bold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
                    <Grid Margin="0,12,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource FieldLabel}" Text="ELAPSED"/>
                        <TextBlock x:Name="elapsedLabel" Style="{StaticResource StatValue}" Text="00:00:00"/>
                      </StackPanel>
                      <StackPanel Grid.Column="1">
                        <TextBlock Style="{StaticResource FieldLabel}" Text="ACTUAL SPEED"/>
                        <TextBlock x:Name="rateLabel" Style="{StaticResource StatValue}" Text="0.0 cps" Foreground="{DynamicResource Accent}"/>
                      </StackPanel>
                    </Grid>
                    <TextBlock Style="{StaticResource FieldLabel}" Text="CURRENT MODE" Margin="0,16,0,6"/>
                    <TextBlock x:Name="modeLabel" Text="Continuous" FontSize="14" FontWeight="SemiBold"/>
                    <TextBlock x:Name="messageLabel" Text="Ready when you are." Style="{StaticResource CardSub}" Margin="0,14,0,0"/>
                  </StackPanel>
                </Border>

                <Grid Grid.Row="1" Grid.ColumnSpan="3" Margin="0,12,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="1.2*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <Button x:Name="startButton" Style="{StaticResource AccentButton}" Height="50" FontSize="14.5">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock x:Name="startGlyph" Style="{StaticResource Glyph}" Text="&#xE768;" FontSize="14"/>
                      <TextBlock x:Name="startText" Text="Start clicking" Margin="10,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                  </Button>
                  <Button x:Name="stopButton" Grid.Column="2" Height="50" FontSize="14.5">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Style="{StaticResource Glyph}" Text="&#xE71A;" FontSize="13"/>
                      <TextBlock Text="Stop" Margin="10,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                  </Button>
                </Grid>
              </Grid>
            </ScrollViewer>

            <!-- More control -->
            <ScrollViewer x:Name="pageMore" VerticalScrollBarVisibility="Auto" Padding="16,14,16,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Input"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="What gets pressed and how the hotkey behaves."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Send a keyboard key"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Press a key instead of clicking the mouse."/>
                      </StackPanel>
                      <ComboBox x:Name="keyCodePick" Grid.Column="1" Width="120" Margin="0,0,14,0" VerticalAlignment="Center"/>
                      <CheckBox x:Name="keyboardMode" Grid.Column="2" Style="{StaticResource Switch}"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Hotkey behavior"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Toggle starts and stops with one press. Hold clicks only while the key is held."/>
                      </StackPanel>
                      <ComboBox x:Name="hotkeyMode" Grid.Column="1" Width="176" VerticalAlignment="Center"/>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Timing"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Fine-tune each press."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="110"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Button hold (duty cycle)"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="How long each press is held, as a percent of the interval. 0 = instant tap."/>
                      </StackPanel>
                      <ContentControl x:Name="dutyHost" Grid.Column="1" Focusable="False" VerticalAlignment="Center"/>
                      <TextBlock Grid.Column="2" Text="%" Foreground="{DynamicResource Muted}" VerticalAlignment="Center" Margin="8,0,0,0" Width="22"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="110"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Speed randomization"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Varies each interval by up to this percent so the rhythm is less robotic."/>
                      </StackPanel>
                      <ContentControl x:Name="randomHost" Grid.Column="1" Focusable="False" VerticalAlignment="Center"/>
                      <TextBlock Grid.Column="2" Text="%" Foreground="{DynamicResource Muted}" VerticalAlignment="Center" Margin="8,0,0,0" Width="22"/>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Screen safety"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Fling the mouse to a corner or edge to stop instantly."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="110"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Stop at screen corners"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Corner zone size in pixels."/>
                      </StackPanel>
                      <ContentControl x:Name="cornerSizeHost" Grid.Column="1" Focusable="False" VerticalAlignment="Center"/>
                      <TextBlock Grid.Column="2" Text="px" Foreground="{DynamicResource Muted}" VerticalAlignment="Center" Margin="8,0,14,0" Width="22"/>
                      <CheckBox x:Name="cornerStop" Grid.Column="3" Style="{StaticResource Switch}"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="110"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Stop at screen edges"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Edge zone size in pixels."/>
                      </StackPanel>
                      <ContentControl x:Name="edgeSizeHost" Grid.Column="1" Focusable="False" VerticalAlignment="Center"/>
                      <TextBlock Grid.Column="2" Text="px" Foreground="{DynamicResource Muted}" VerticalAlignment="Center" Margin="8,0,14,0" Width="22"/>
                      <CheckBox x:Name="edgeStop" Grid.Column="3" Style="{StaticResource Switch}"/>
                    </Grid>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>

            <!-- Click points -->
            <ScrollViewer x:Name="pagePoints" VerticalScrollBarVisibility="Auto" Padding="16,14,16,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Click points"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Pick screen locations to click in sequence. Each point uses your click settings."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Use click points"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="When off, TapForge clicks wherever your cursor is."/>
                      </StackPanel>
                      <CheckBox x:Name="pointsEnabled" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Stop when complete"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Stop after every point has been clicked once through."/>
                      </StackPanel>
                      <CheckBox x:Name="stopWhenPointsDone" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border Style="{StaticResource Panel}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="12"/>
                      <ColumnDefinition Width="160"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.ColumnSpan="3" Margin="0,0,0,12">
                      <TextBlock Style="{StaticResource CardTitle}" Text="Points"/>
                      <TextBlock x:Name="pointsSummary" Style="{StaticResource CardSub}" Text="No points yet."/>
                    </StackPanel>
                    <ListBox x:Name="pointList" Grid.Row="1" Height="210"/>
                    <StackPanel Grid.Row="1" Grid.Column="2">
                      <Button x:Name="pickPoint" Style="{StaticResource AccentButton}">
                        <StackPanel Orientation="Horizontal">
                          <TextBlock Style="{StaticResource Glyph}" Text="&#xE710;" FontSize="12"/>
                          <TextBlock Text="Pick point" Margin="8,0,0,0"/>
                        </StackPanel>
                      </Button>
                      <Button x:Name="removePoint" Content="Remove selected" Margin="0,8,0,0"/>
                      <Button x:Name="clearPoints" Content="Clear all" Margin="0,8,0,0"/>
                    </StackPanel>
                  </Grid>
                </Border>

                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Point defaults"/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="110"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Clicks per point"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="How many clicks land on a point before moving to the next."/>
                      </StackPanel>
                      <ContentControl x:Name="pointClicksHost" Grid.Column="1" Focusable="False" VerticalAlignment="Center"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="110"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Randomization radius"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Lands each click at a random spot within this many pixels of the point."/>
                      </StackPanel>
                      <ContentControl x:Name="pointRadiusHost" Grid.Column="1" Focusable="False" VerticalAlignment="Center"/>
                    </Grid>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>

            <!-- Settings: General -->
            <ScrollViewer x:Name="pageGeneral" VerticalScrollBarVisibility="Auto" Padding="14,14,14,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="About"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Version and project links."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel Orientation="Horizontal">
                        <Image x:Name="aboutLogo" Width="40" Height="40" RenderOptions.BitmapScalingMode="HighQuality"/>
                        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
                          <TextBlock Text="TapForge" FontSize="16" FontWeight="Bold"/>
                          <TextBlock Text="Precision auto-clicker for Windows" Style="{StaticResource CardSub}"/>
                        </StackPanel>
                      </StackPanel>
                      <Button x:Name="githubButton" Grid.Column="1" VerticalAlignment="Center" Padding="12,0">
                        <StackPanel Orientation="Horizontal">
                          <TextBlock Style="{StaticResource Glyph}" Text="&#xE8A7;" FontSize="12"/>
                          <TextBlock Text="GitHub" Margin="8,0,0,0"/>
                        </StackPanel>
                      </Button>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Style="{StaticResource RowTitle}" Text="Version"/>
                        <TextBlock x:Name="versionLabel" Text="v4.0.0" FontSize="13" Foreground="{DynamicResource Muted}" Margin="10,0,0,0" VerticalAlignment="Center"/>
                      </StackPanel>
                      <Button x:Name="changesButton" Grid.Column="1" Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal">
                          <TextBlock Style="{StaticResource Glyph}" Text="&#xE76C;" FontSize="10"/>
                          <TextBlock Text="Show changes" Margin="8,0,0,0"/>
                        </StackPanel>
                      </Button>
                      <Button x:Name="checkUpdateButton" Grid.Column="2" Content="Check for update"/>
                    </Grid>
                    <TextBlock x:Name="updateStatus" Style="{StaticResource CardSub}" Margin="0,10,0,0" Text=""/>
                  </StackPanel>
                </Border>

                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Usage"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Clicking statistics for all sessions (only stored on this PC)."/>
                    <TextBlock x:Name="usageEmpty" Text="No session data yet." Foreground="{DynamicResource Muted}" HorizontalAlignment="Center" Margin="0,18,0,8"/>
                    <Grid x:Name="usageGrid" Margin="0,16,0,2" Visibility="Collapsed">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource FieldLabel}" Text="TOTAL CLICKS"/>
                        <TextBlock x:Name="usageClicks" Style="{StaticResource StatValue}" Text="0"/>
                      </StackPanel>
                      <StackPanel Grid.Column="1">
                        <TextBlock Style="{StaticResource FieldLabel}" Text="SESSIONS"/>
                        <TextBlock x:Name="usageSessions" Style="{StaticResource StatValue}" Text="0"/>
                      </StackPanel>
                      <StackPanel Grid.Column="2">
                        <TextBlock Style="{StaticResource FieldLabel}" Text="TIME CLICKING"/>
                        <TextBlock x:Name="usageTime" Style="{StaticResource StatValue}" Text="0m"/>
                      </StackPanel>
                      <StackPanel Grid.Column="3">
                        <TextBlock Style="{StaticResource FieldLabel}" Text="LAST SESSION"/>
                        <TextBlock x:Name="usageLast" Style="{StaticResource StatValue}" FontSize="14" Text="-" TextWrapping="Wrap"/>
                      </StackPanel>
                    </Grid>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>

            <!-- Settings: Behavior -->
            <ScrollViewer x:Name="pageBehavior" VerticalScrollBarVisibility="Auto" Padding="14,14,14,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Clicking"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="How TapForge behaves while it runs."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Always on top"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Keep TapForge above other windows."/>
                      </StackPanel>
                      <CheckBox x:Name="alwaysTop" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Stop reason alert"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Show a notification when a limit or safety stop ends clicking."/>
                      </StackPanel>
                      <CheckBox x:Name="stopAlert" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="True"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Strict hotkey modifiers"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Ignore the start key while Ctrl, Shift, Alt or Windows is held."/>
                      </StackPanel>
                      <CheckBox x:Name="strictHotkey" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Stop on Alt+Tab"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Stop clicking when you switch to another window."/>
                      </StackPanel>
                      <CheckBox x:Name="stopAltTab" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Extended speed limit"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Allow up to 1000 clicks per second. The game or app may not keep up."/>
                      </StackPanel>
                      <CheckBox x:Name="extendedSpeed" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Startup"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Window and sign-in options."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Minimize to tray"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Minimizing or closing hides TapForge in the notification area instead of exiting."/>
                      </StackPanel>
                      <CheckBox x:Name="minimizeTray" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Remember window position"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Reopen where you left it, at the same size."/>
                      </StackPanel>
                      <CheckBox x:Name="rememberPosition" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="True"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Run on startup"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Start TapForge when you sign in to Windows."/>
                      </StackPanel>
                      <CheckBox x:Name="runOnStartup" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>

            <!-- Settings: Appearance -->
            <ScrollViewer x:Name="pageAppearance" VerticalScrollBarVisibility="Auto" Padding="14,14,14,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Theme"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Light or dark, and what shows at the bottom."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Theme"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Colors for the whole app."/>
                      </StackPanel>
                      <ComboBox x:Name="themePick" Grid.Column="1" Width="170" VerticalAlignment="Center"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Status footer"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Show the active preset and version along the bottom."/>
                      </StackPanel>
                      <CheckBox x:Name="footerToggle" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="True"/>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Accent color"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Used for the window edge, buttons, switches and the logo."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Accent mode"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="One color everywhere, or a different color for each page."/>
                      </StackPanel>
                      <ComboBox x:Name="appearanceModePick" Grid.Column="1" Width="170" VerticalAlignment="Center"/>
                    </Grid>
                    <Grid x:Name="accentTargetRow" Margin="0,12,0,0" Visibility="Collapsed">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Page to edit"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="The color below applies to this page."/>
                      </StackPanel>
                      <ComboBox x:Name="accentTarget" Grid.Column="1" Width="170" VerticalAlignment="Center"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <Border x:Name="accentSwatch" Width="36" Height="36" CornerRadius="10" Background="{DynamicResource Accent}" BorderBrush="{DynamicResource InputBorder}" BorderThickness="1"/>
                      <StackPanel Grid.Column="1" Margin="12,0,0,0" VerticalAlignment="Center">
                        <TextBlock x:Name="accentHex" Text="#7B61FF" FontSize="14" FontWeight="SemiBold"/>
                        <TextBlock Text="Current color" Style="{StaticResource CardSub}"/>
                      </StackPanel>
                      <Button x:Name="hueButton" Grid.Column="2" Style="{StaticResource AccentButton}" Content="Custom color..." VerticalAlignment="Center"/>
                    </Grid>
                    <WrapPanel x:Name="swatchPanel" Margin="0,14,0,0"/>
                  </StackPanel>
                </Border>

                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Icon"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Taskbar and tray icon."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Show active state"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Add a green dot to the taskbar icon while clicking."/>
                      </StackPanel>
                      <CheckBox x:Name="activeIcon" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="True"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Icon background"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Put the logo on a dark or light tile so it stands out on your taskbar."/>
                      </StackPanel>
                      <ComboBox x:Name="iconTheme" Grid.Column="1" Width="170" VerticalAlignment="Center"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Logo color"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Tint the logo with your accent color, or keep its original colors."/>
                      </StackPanel>
                      <ComboBox x:Name="iconColor" Grid.Column="1" Width="170" VerticalAlignment="Center"/>
                    </Grid>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>

            <!-- Settings: Keybinds -->
            <ScrollViewer x:Name="pageKeybinds" VerticalScrollBarVisibility="Auto" Padding="14,14,14,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Keybinds"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Global shortcuts. They work while TapForge is minimized or a game is in front."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Start / stop clicking"/>
                        <TextBlock x:Name="startKeyHint" Style="{StaticResource RowSub}" Text="Press once to start, again to stop (or hold, if set on More control)."/>
                      </StackPanel>
                      <ComboBox x:Name="keyPick" Grid.Column="1" Width="170" VerticalAlignment="Center"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Emergency stop"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Always stops the click engine immediately."/>
                      </StackPanel>
                      <ComboBox x:Name="emergencyKey" Grid.Column="1" Width="170" VerticalAlignment="Center"/>
                    </Grid>
                    <TextBlock x:Name="keyWarning" Style="{StaticResource CardSub}" Foreground="{DynamicResource Warn}" Margin="0,12,0,0" Visibility="Collapsed"/>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Panel}">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Style="{StaticResource Glyph}" Text="&#xE946;" Foreground="{DynamicResource Accent}" FontSize="15" VerticalAlignment="Top" Margin="0,1,0,0"/>
                    <TextBlock Style="{StaticResource CardSub}" Margin="10,0,0,0" MaxWidth="560"
                               Text="Mouse 4 and Mouse 5 (the side buttons) work as hotkeys too. Choose Toggle or Hold behavior on the More control page."/>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>

            <!-- Settings: Process list -->
            <ScrollViewer x:Name="pageProcess" VerticalScrollBarVisibility="Auto" Padding="14,14,14,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Process list"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Optionally restrict clicks to one app. Clicking pauses whenever another window is in front."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Only click in the selected app"/>
                        <TextBlock x:Name="processSelectedLabel" Style="{StaticResource RowSub}" Text="No app selected."/>
                      </StackPanel>
                      <CheckBox x:Name="filterProcess" Grid.Column="1" Style="{StaticResource Switch}"/>
                    </Grid>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Panel}">
                  <Grid>
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <Grid Margin="0,0,0,12">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource CardTitle}" Text="Open windows"/>
                        <TextBlock Style="{StaticResource CardSub}" Text="Select the app TapForge should click in."/>
                      </StackPanel>
                      <Button x:Name="refreshProcesses" Grid.Column="1" VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal">
                          <TextBlock Style="{StaticResource Glyph}" Text="&#xE72C;" FontSize="12"/>
                          <TextBlock Text="Refresh" Margin="8,0,0,0"/>
                        </StackPanel>
                      </Button>
                    </Grid>
                    <ListBox x:Name="processList" Grid.Row="1" Height="290"/>
                  </Grid>
                </Border>
              </StackPanel>
            </ScrollViewer>

            <!-- Settings: Presets -->
            <ScrollViewer x:Name="pagePresets" VerticalScrollBarVisibility="Auto" Padding="14,14,14,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Save a preset"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Stores your click, speed, input and safety settings under a name."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <TextBox x:Name="presetName"/>
                      <Button x:Name="presetSave" Grid.Column="1" Style="{StaticResource AccentButton}" Content="Save current" Margin="10,0,0,0"/>
                    </Grid>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Panel}">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <StackPanel Grid.ColumnSpan="3" Margin="0,0,0,12">
                      <TextBlock Style="{StaticResource CardTitle}" Text="Your presets"/>
                      <TextBlock x:Name="presetSummary" Style="{StaticResource CardSub}" Text="Double-click a preset to load it."/>
                    </StackPanel>
                    <ListBox x:Name="presetList" Grid.Row="1" Height="240"/>
                    <StackPanel Grid.Row="1" Grid.Column="2">
                      <Button x:Name="presetLoad" Style="{StaticResource AccentButton}" Content="Load selected"/>
                      <Button x:Name="presetDelete" Content="Delete selected" Margin="0,8,0,0"/>
                    </StackPanel>
                  </Grid>
                </Border>
              </StackPanel>
            </ScrollViewer>

            <!-- Settings: Maintenance -->
            <ScrollViewer x:Name="pageMaintenance" VerticalScrollBarVisibility="Auto" Padding="14,14,14,4" Visibility="Collapsed">
              <StackPanel>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Updates"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="TapForge checks GitHub for new releases when it opens."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Check for updates"/>
                        <TextBlock x:Name="maintUpdateStatus" Style="{StaticResource RowSub}" Text=""/>
                      </StackPanel>
                      <Button x:Name="publishUpdateButton" Grid.Column="1" Content="Publish update" Margin="0,0,8,0" VerticalAlignment="Center" Visibility="Collapsed"/>
                      <Button x:Name="maintCheckButton" Grid.Column="2" Style="{StaticResource AccentButton}" Content="Check now" VerticalAlignment="Center"/>
                    </Grid>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Panel}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource CardTitle}" Text="Settings and data"/>
                    <TextBlock Style="{StaticResource CardSub}" Text="Everything is stored locally in your AppData folder."/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Reset all settings"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Return every option to its default. Presets are kept."/>
                      </StackPanel>
                      <Button x:Name="resetSettings" Grid.Column="1" Content="Reset settings" VerticalAlignment="Center"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Reset usage data"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Clear the statistics shown on the General page."/>
                      </StackPanel>
                      <Button x:Name="resetUsage" Grid.Column="1" Content="Reset usage" VerticalAlignment="Center"/>
                    </Grid>
                    <Border Style="{StaticResource Divider}"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Style="{StaticResource RowTitle}" Text="Diagnostics"/>
                        <TextBlock Style="{StaticResource RowSub}" Text="Error log and a system report for troubleshooting."/>
                      </StackPanel>
                      <Button x:Name="openDiagnostics" Grid.Column="1" Content="Open folder" Margin="0,0,8,0" VerticalAlignment="Center"/>
                      <Button x:Name="exportDiagnostics" Grid.Column="2" Content="Export report" VerticalAlignment="Center"/>
                    </Grid>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>
          </Grid>
        </Border>

        <!-- Compact mode -->
        <Border x:Name="compactPanel" Grid.ColumnSpan="2" Visibility="Collapsed" Background="{DynamicResource Bg}"
                CornerRadius="14,0,0,0" BorderThickness="1.5,1.5,0,0" BorderBrush="{DynamicResource Accent}" Padding="14,12">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="110"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="10"/>
              <ColumnDefinition Width="110"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Text="CPS" Style="{StaticResource FieldLabel}" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <ContentControl x:Name="quickRateHost" Grid.Column="1" Focusable="False"/>
            <Button x:Name="quickStart" Grid.Column="2" Style="{StaticResource AccentButton}" Margin="10,0,0,0" Height="36">
              <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="quickGlyph" Style="{StaticResource Glyph}" Text="&#xE768;" FontSize="12"/>
                <TextBlock x:Name="quickText" Text="Start" Margin="8,0,0,0"/>
              </StackPanel>
            </Button>
            <Button x:Name="quickStop" Grid.Column="4" Height="36">
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Glyph}" Text="&#xE71A;" FontSize="11"/>
                <TextBlock Text="Stop" Margin="8,0,0,0"/>
              </StackPanel>
            </Button>
            <Grid Grid.Row="1" Grid.ColumnSpan="5" Margin="0,10,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBlock x:Name="quickHotkey" Text="F6 start / stop  ·  F7 emergency stop" Foreground="{DynamicResource Muted}" FontSize="12"/>
              <TextBlock x:Name="quickCount" Grid.Column="1" Text="0 clicks" Foreground="{DynamicResource Muted}" FontSize="12"/>
            </Grid>
          </Grid>
        </Border>
      </Grid>

      <!-- ===== Footer ===== -->
      <Grid x:Name="footer" Grid.Row="2" Height="28">
        <TextBlock x:Name="footerLeft" Text="No preset active" Foreground="{DynamicResource Muted}" FontSize="11.5" VerticalAlignment="Center" Margin="14,0,0,0"/>
        <TextBlock x:Name="footerRight" Text="v4.0.0" Foreground="{DynamicResource Muted}" FontSize="11.5" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,14,0"/>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
$dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TapForge" Width="420" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" WindowStartupLocation="CenterOwner"
        Foreground="{DynamicResource Text}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Border Margin="14" CornerRadius="12" Background="{DynamicResource Card}" BorderBrush="{DynamicResource InputBorder}" BorderThickness="1" Padding="20,18">
    <Border.Effect>
      <DropShadowEffect BlurRadius="18" ShadowDepth="2" Opacity="0.45" Color="Black"/>
    </Border.Effect>
    <StackPanel>
      <StackPanel Orientation="Horizontal">
        <Border Width="3" Height="16" CornerRadius="2" Background="{DynamicResource Accent}" VerticalAlignment="Center"/>
        <TextBlock x:Name="dlgTitle" Text="TapForge" FontSize="15" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock x:Name="dlgMessage" Margin="0,12,0,0" TextWrapping="Wrap" Foreground="{DynamicResource Muted}" LineHeight="19"/>
      <TextBox x:Name="dlgInput" Margin="0,14,0,0" Visibility="Collapsed"/>
      <StackPanel x:Name="dlgButtons" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@
$colorXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Accent color" Width="400" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" WindowStartupLocation="CenterOwner"
        Foreground="{DynamicResource Text}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Border Margin="14" CornerRadius="12" Background="{DynamicResource Card}" BorderBrush="{DynamicResource InputBorder}" BorderThickness="1" Padding="20,18">
    <Border.Effect>
      <DropShadowEffect BlurRadius="18" ShadowDepth="2" Opacity="0.45" Color="Black"/>
    </Border.Effect>
    <StackPanel>
      <TextBlock Text="Choose accent color" FontSize="15" FontWeight="SemiBold"/>
      <Grid Margin="0,14,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="cpPreview" Width="56" Height="56" CornerRadius="12" BorderBrush="{DynamicResource InputBorder}" BorderThickness="1"/>
        <StackPanel Grid.Column="1" Margin="14,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="HEX" Style="{StaticResource FieldLabel}"/>
          <TextBox x:Name="cpHex" Width="130" HorizontalAlignment="Left"/>
        </StackPanel>
      </Grid>
      <TextBlock Text="HUE" Style="{StaticResource FieldLabel}" Margin="0,16,0,2"/>
      <Slider x:Name="cpHue" Style="{StaticResource ColorSlider}" Minimum="0" Maximum="360">
        <Slider.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#FF0000" Offset="0"/>
            <GradientStop Color="#FFFF00" Offset="0.1667"/>
            <GradientStop Color="#00FF00" Offset="0.3333"/>
            <GradientStop Color="#00FFFF" Offset="0.5"/>
            <GradientStop Color="#0000FF" Offset="0.6667"/>
            <GradientStop Color="#FF00FF" Offset="0.8333"/>
            <GradientStop Color="#FF0000" Offset="1"/>
          </LinearGradientBrush>
        </Slider.Background>
      </Slider>
      <TextBlock Text="SATURATION" Style="{StaticResource FieldLabel}" Margin="0,12,0,2"/>
      <Slider x:Name="cpSat" Style="{StaticResource ColorSlider}" Minimum="0" Maximum="100"/>
      <TextBlock Text="BRIGHTNESS" Style="{StaticResource FieldLabel}" Margin="0,12,0,2"/>
      <Slider x:Name="cpVal" Style="{StaticResource ColorSlider}" Minimum="0" Maximum="100"/>
      <WrapPanel x:Name="cpSwatches" Margin="0,14,0,0"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
        <Button x:Name="cpCancel" Content="Cancel" Width="100"/>
        <Button x:Name="cpApply" Style="{StaticResource AccentButton}" Content="Apply" Width="100" Margin="8,0,0,0"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

# ---------------------------------------------------------------------------
# TapForge 4 - WPF interface
# Loaded by TapForge.exe (or: powershell -STA -File AutoClicker.ps1).
# Settings, presets and usage data live in %LOCALAPPDATA%\TapForge.
# ---------------------------------------------------------------------------

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing

$script:dataDir = Join-Path $env:LOCALAPPDATA 'TapForge'
$script:diagDir = Join-Path $script:dataDir 'Diagnostics'
$script:presetDirectory = Join-Path $script:dataDir 'Presets'
foreach ($d in @($script:dataDir, $script:diagDir, $script:presetDirectory)) { [void](New-Item -ItemType Directory -Force -Path $d -ErrorAction SilentlyContinue) }
$script:logFile = Join-Path $script:diagDir 'tapforge.log'
$script:settingsFile = Join-Path $script:dataDir 'settings.json'
$script:windowStateFile = Join-Path $script:dataDir 'window.json'
$script:usageFile = Join-Path $script:dataDir 'usage.json'
function Write-TFLog([string]$message) {
    try { Add-Content -LiteralPath $script:logFile -Value ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $message) -Encoding UTF8 } catch { }
}

$script:mid = [string][char]0x00B7
$script:ell = [string][char]0x2026

try {
# ===== Native code =========================================================
if (-not ('ClickNative' -as [type])) {
    Add-Type -TypeDefinition $engineSource -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.Drawing.dll')
}
if (-not ('TapForgeUI.NumberBox' -as [type])) {
    $wpfRefs = @(
        [System.Windows.Window].Assembly.Location,
        [System.Windows.Media.Brush].Assembly.Location,
        [System.Windows.DependencyObject].Assembly.Location,
        [System.Xaml.XamlReader].Assembly.Location
    )
    Add-Type -TypeDefinition $uiSource -ReferencedAssemblies $wpfRefs
}
[TapForgeShell]::EnableDpiAwareness()

# ===== Application + theme resources =======================================
$script:app = [System.Windows.Application]::Current
if (-not $script:app) {
    $script:app = [System.Windows.Application]::new()
    $script:app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
}
$script:app.Resources = [System.Windows.Markup.XamlReader]::Parse($resourcesXaml)
$script:app.Add_DispatcherUnhandledException({
    param($s, $e)
    Write-TFLog ('UI error: ' + $e.Exception.ToString())
    $e.Handled = $true
})

function ConvertTo-MediaColor([string]$hex) {
    try { return [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }
    catch { return [System.Windows.Media.Color]::FromRgb(123, 97, 255) }
}
function ConvertTo-Hex([System.Windows.Media.Color]$c) { '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B }
function Test-Hex([string]$hex) { $hex -match '^#[0-9A-Fa-f]{6}$' }
function Set-Brush([string]$key, [System.Windows.Media.Color]$color) {
    $b = [System.Windows.Media.SolidColorBrush]::new($color); $b.Freeze()
    $script:app.Resources[$key] = $b
}
function New-Brush([string]$hex) { $b = [System.Windows.Media.SolidColorBrush]::new((ConvertTo-MediaColor $hex)); $b.Freeze(); $b }

$script:palettes = @{
    Dark  = @{ Bg = '#0E0E10'; Chrome = '#151517'; Card = '#1A1A1D'; CardBorder = '#2A2A2F'; Input = '#222226'; InputBorder = '#34343B'; Hover = '#28282D'; Text = '#F2F2F5'; Muted = '#9A9AA5'; SwitchOff = '#3A3A42'; ScrollThumb = '#3A3A42' }
    Light = @{ Bg = '#F4F5F8'; Chrome = '#E8EAEF'; Card = '#FFFFFF'; CardBorder = '#DDE0E7'; Input = '#F6F7F9'; InputBorder = '#CDD1DA'; Hover = '#E7E9EF'; Text = '#1B1F29'; Muted = '#5F6675'; SwitchOff = '#C5CAD4'; ScrollThumb = '#C5CAD4' }
}
$script:swatches = @('#7B61FF', '#A855F7', '#D946EF', '#EC4899', '#F43F5E', '#F97316', '#EAB308', '#22C55E', '#14B8A6', '#0EA5E9', '#3B82F6', '#94A3B8')

# ===== Window ==============================================================
$script:window = [System.Windows.Markup.XamlReader]::Parse($mainXaml)
$window = $script:window
$script:ui = @{}
foreach ($m in [regex]::Matches($mainXaml, 'x:Name="([^"]+)"')) { $script:ui[$m.Groups[1].Value] = $window.FindName($m.Groups[1].Value) }
$ui = $script:ui

# TapForge.exe passes its own path in. The script itself may live in
# %LOCALAPPDATA%\TapForge\App (single-file build) or beside the exe (dev copy).
$script:exePath = if ($global:TapForgeExePath -and (Test-Path -LiteralPath ([string]$global:TapForgeExePath))) { [string]$global:TapForgeExePath } else { Join-Path $PSScriptRoot 'TapForge.exe' }
$script:exeDir = Split-Path -Parent $script:exePath
$script:versionFile = Join-Path $PSScriptRoot 'VERSION'
$script:appVersion = '4.0.0'
if (Test-Path -LiteralPath $script:versionFile) { try { $script:appVersion = (Get-Content -LiteralPath $script:versionFile -Raw).Trim() } catch { } }
foreach ($n in @('versionLabel', 'sideVersion', 'footerRight')) { $ui[$n].Text = 'v' + $script:appVersion }
$script:repoUrl = 'https://github.com/saberapexyt-commits/TapForge'

function Set-Items($combo, [string[]]$items) {
    $combo.Items.Clear()
    foreach ($i in $items) { [void]$combo.Items.Add($i) }
    if ($combo.Items.Count -gt 0) { $combo.SelectedIndex = 0 }
}
function Set-Index($combo, $index) {
    $i = 0; try { $i = [int]$index } catch { }
    $combo.SelectedIndex = [Math]::Max(0, [Math]::Min($combo.Items.Count - 1, $i))
}
function On-Toggle($checkBox, [scriptblock]$action) { $checkBox.Add_Checked($action); $checkBox.Add_Unchecked($action) }
function Is-On($checkBox) { $checkBox.IsChecked -eq $true }

$script:keyMap = [ordered]@{
    F1 = 0x70; F2 = 0x71; F3 = 0x72; F4 = 0x73; F5 = 0x74; F6 = 0x75; F7 = 0x76; F8 = 0x77; F9 = 0x78; F10 = 0x79; F11 = 0x7A; F12 = 0x7B
    'Mouse 4' = 0x05; 'Mouse 5' = 0x06; Insert = 0x2D; Home = 0x24; End = 0x23; 'Page Up' = 0x21; 'Page Down' = 0x22
    Pause = 0x13; 'Scroll Lock' = 0x91; 'Tilde (~)' = 0xC0
}
$script:keyNames = [string[]]@($script:keyMap.Keys)
$script:sendKeys = [ordered]@{ Space = 0x20; Enter = 0x0D; A = 0x41; F = 0x46; E = 0x45; Q = 0x51; R = 0x52; W = 0x57; S = 0x53; D = 0x44; '1' = 0x31; '2' = 0x32; '3' = 0x33 }
$script:accentPages = @('Clicking', 'More control', 'Click Points', 'General', 'Behavior', 'Appearance', 'Keybinds', 'Process List', 'Presets', 'Maintenance')
$script:pageAccentKey = @{ Clicking = 'Clicking'; More = 'More control'; Points = 'Click Points'; General = 'General'; Behavior = 'Behavior'; Appearance = 'Appearance'; Keybinds = 'Keybinds'; Process = 'Process List'; Presets = 'Presets'; Maintenance = 'Maintenance' }

Set-Items $ui.buttonPick @('Left click', 'Right click', 'Middle click')
Set-Items $ui.clickTypePick @('Single click', 'Double click')
Set-Items $ui.speedMode @('Interval', 'Clicks per second')
Set-Items $ui.intervalUnit @('ms', 'sec', 'min')
Set-Items $ui.modePick @('Until stopped', 'Number of clicks', 'Time limit')
Set-Items $ui.keyCodePick ([string[]]@($script:sendKeys.Keys))
Set-Items $ui.hotkeyMode @('Toggle', 'Hold while pressed')
Set-Items $ui.themePick @('Dark', 'Light')
Set-Items $ui.appearanceModePick @('One color', 'Per page')
Set-Items $ui.accentTarget $script:accentPages
Set-Items $ui.iconTheme @('No tile', 'Dark tile', 'Light tile')
Set-Items $ui.iconColor @('Match accent', 'Original colors')
Set-Items $ui.keyPick $script:keyNames
Set-Items $ui.emergencyKey $script:keyNames
$ui.keyPick.SelectedItem = 'F6'; $ui.emergencyKey.SelectedItem = 'F7'

function New-NumberBox($target, [double]$min, [double]$max, [int]$places, [double]$step, [double]$value) {
    $nb = [TapForgeUI.NumberBox]::new()
    $nb.Configure($min, $max, $places, $step, $value)
    $target.Content = $nb
    $nb
}
$script:interval = New-NumberBox $ui.intervalHost 1 3600000 0 10 100
$script:rate = New-NumberBox $ui.rateHost 0.1 500 1 1 10
$script:limit = New-NumberBox $ui.limitHost 1 10000000 0 10 100
$script:duty = New-NumberBox $ui.dutyHost 0 100 0 5 0
$script:randomize = New-NumberBox $ui.randomHost 0 90 0 5 0
$script:cornerSize = New-NumberBox $ui.cornerSizeHost 10 500 0 5 50
$script:edgeSize = New-NumberBox $ui.edgeSizeHost 5 300 0 5 40
$script:pointClicks = New-NumberBox $ui.pointClicksHost 1 9999 0 1 1
$script:pointRadius = New-NumberBox $ui.pointRadiusHost 0 1000 0 1 0
$script:quickRate = New-NumberBox $ui.quickRateHost 0.1 500 1 1 10
$interval = $script:interval; $rate = $script:rate; $limit = $script:limit; $duty = $script:duty; $randomize = $script:randomize
$cornerSize = $script:cornerSize; $edgeSize = $script:edgeSize; $pointClicks = $script:pointClicks; $pointRadius = $script:pointRadius; $quickRate = $script:quickRate

# ===== Logo + icons ========================================================
$script:logoBase = $null
try {
    $logoPath = Join-Path $PSScriptRoot 'TapForgeLogo.png'
    if (Test-Path -LiteralPath $logoPath) {
        $raw = [System.Drawing.Bitmap]::FromFile($logoPath)
        try {
            $script:logoBase = [System.Drawing.Bitmap]::new(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($script:logoBase)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $scale = [Math]::Min(256.0 / $raw.Width, 256.0 / $raw.Height)
            $w = [int]($raw.Width * $scale); $h = [int]($raw.Height * $scale)
            $g.DrawImage($raw, [int]((256 - $w) / 2), [int]((256 - $h) / 2), $w, $h)
            $g.Dispose()
        } finally { $raw.Dispose() }
    }
} catch { Write-TFLog ('Logo load failed: ' + $_.Exception.Message) }

function ConvertTo-ImageSource([System.Drawing.Bitmap]$bitmap) {
    $ms = [System.IO.MemoryStream]::new()
    $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $ms.Position = 0
    $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
    $bi.BeginInit(); $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bi.StreamSource = $ms; $bi.EndInit(); $bi.Freeze()
    $ms.Dispose()
    $bi
}
function New-PlatedLogo([System.Drawing.Bitmap]$logo, [bool]$light) {
    $out = [System.Drawing.Bitmap]::new(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new(); $d = 72
    $path.AddArc(0, 0, $d, $d, 180, 90); $path.AddArc(255 - $d, 0, $d, $d, 270, 90)
    $path.AddArc(255 - $d, 255 - $d, $d, $d, 0, 90); $path.AddArc(0, 255 - $d, $d, $d, 90, 90); $path.CloseFigure()
    $fill = if ($light) { [System.Drawing.Color]::FromArgb(243, 244, 247) } else { [System.Drawing.Color]::FromArgb(24, 24, 27) }
    $brush = [System.Drawing.SolidBrush]::new($fill)
    $g.FillPath($brush, $path)
    $g.DrawImage($logo, 30, 30, 196, 196)
    $brush.Dispose(); $path.Dispose(); $g.Dispose()
    $out
}
$script:activeOverlay = $null
try {
    $dot = [System.Windows.Media.GeometryDrawing]::new((New-Brush '#22C55E'), [System.Windows.Media.Pen]::new((New-Brush '#FFFFFF'), 1.5), [System.Windows.Media.EllipseGeometry]::new([System.Windows.Point]::new(8, 8), 6.5, 6.5))
    $script:activeOverlay = [System.Windows.Media.DrawingImage]::new($dot); $script:activeOverlay.Freeze()
    $window.TaskbarItemInfo = [System.Windows.Shell.TaskbarItemInfo]::new()
} catch { }

function Update-Icons {
    if (-not $script:logoBase) { return }
    try {
        $mc = ConvertTo-MediaColor (Get-CurrentAccentHex)
        $tinted = if ($ui.iconColor.SelectedIndex -eq 1) { $script:logoBase.Clone() } else { [LogoColorizer]::Tint($script:logoBase, [System.Drawing.Color]::FromArgb($mc.R, $mc.G, $mc.B)) }
        $src = ConvertTo-ImageSource $tinted
        foreach ($n in @('brandLogo', 'sideLogo', 'aboutLogo')) { $ui[$n].Source = $src }
        $plate = $ui.iconTheme.SelectedIndex
        $iconBitmap = if ($plate -le 0) { $tinted } else { New-PlatedLogo $tinted ($plate -eq 2) }
        $window.Icon = ConvertTo-ImageSource $iconBitmap
        $newIcon = [LogoColorizer]::MakeIcon($iconBitmap)
        $oldIcon = $script:trayIconImage; $script:trayIconImage = $newIcon
        if ($script:trayIcon) { $script:trayIcon.Icon = $newIcon }
        if ($oldIcon) { $oldIcon.Dispose() }
        if (-not [object]::ReferenceEquals($iconBitmap, $tinted)) { $iconBitmap.Dispose() }
        $tinted.Dispose()
    } catch { Write-TFLog ('Icon update failed: ' + $_.Exception.Message) }
}
function Update-ActiveOverlay {
    if (-not $window.TaskbarItemInfo) { return }
    $window.TaskbarItemInfo.Overlay = if ($script:running -and (Is-On $ui.activeIcon)) { $script:activeOverlay } else { $null }
}

# ===== Theme + accent ======================================================
$script:globalAccent = '#7B61FF'
$script:pageAccents = @{}
foreach ($p in $script:accentPages) { $script:pageAccents[$p] = '#7B61FF' }
$script:appliedAccent = $null
$script:lightTheme = $false
$script:currentPage = 'Clicking'
$script:lastSettingsPage = 'General'

function Get-CurrentAccentHex {
    if ($ui.appearanceModePick.SelectedIndex -eq 1) {
        $k = $script:pageAccentKey[$script:currentPage]
        if ($k -and $script:pageAccents[$k]) { return $script:pageAccents[$k] }
    }
    $script:globalAccent
}
function Get-EditedAccent {
    if ($ui.appearanceModePick.SelectedIndex -eq 1 -and $ui.accentTarget.SelectedItem) { return $script:pageAccents[[string]$ui.accentTarget.SelectedItem] }
    $script:globalAccent
}
function Update-AccentUi {
    $hex = Get-EditedAccent
    $ui.accentHex.Text = $hex.ToUpper()
    $ui.accentSwatch.Background = New-Brush $hex
    $ui.accentTargetRow.Visibility = if ($ui.appearanceModePick.SelectedIndex -eq 1) { 'Visible' } else { 'Collapsed' }
}
function Apply-Accent([switch]$Force) {
    $hex = Get-CurrentAccentHex
    Update-AccentUi
    if (-not $Force -and $hex -eq $script:appliedAccent) { return }
    $script:appliedAccent = $hex
    $c = ConvertTo-MediaColor $hex
    Set-Brush 'Accent' $c
    Set-Brush 'AccentSoft' ([System.Windows.Media.Color]::FromArgb(0x38, $c.R, $c.G, $c.B))
    $lum = (0.2126 * $c.R + 0.7152 * $c.G + 0.0722 * $c.B) / 255
    Set-Brush 'OnAccent' $(if ($lum -gt 0.7) { ConvertTo-MediaColor '#111114' } else { [System.Windows.Media.Colors]::White })
    Update-Icons
}
function Set-EditedAccent([string]$hex) {
    if (-not (Test-Hex $hex)) { return }
    $hex = $hex.ToUpper()
    if ($ui.appearanceModePick.SelectedIndex -eq 1 -and $ui.accentTarget.SelectedItem) {
        $script:pageAccents[[string]$ui.accentTarget.SelectedItem] = $hex
    } else {
        $script:globalAccent = $hex
        foreach ($k in @($script:pageAccents.Keys)) { $script:pageAccents[$k] = $hex }
    }
    Apply-Accent -Force
}
function Apply-Theme {
    $name = if ($ui.themePick.SelectedIndex -eq 1) { 'Light' } else { 'Dark' }
    $script:lightTheme = ($name -eq 'Light')
    $p = $script:palettes[$name]
    foreach ($k in $p.Keys) { Set-Brush $k (ConvertTo-MediaColor $p[$k]) }
    if ($script:hwnd) { [TapForgeShell]::StyleWindow($script:hwnd, -not $script:lightTheme) }
}

foreach ($hex in $script:swatches) {
    $sw = [System.Windows.Controls.Border]::new()
    $sw.Width = 28; $sw.Height = 28; $sw.CornerRadius = [System.Windows.CornerRadius]::new(14)
    $sw.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8); $sw.Background = New-Brush $hex
    $sw.Cursor = [System.Windows.Input.Cursors]::Hand; $sw.Tag = $hex; $sw.ToolTip = $hex
    $sw.Add_MouseLeftButtonUp({ param($s, $e) Set-EditedAccent ([string]$s.Tag) })
    [void]$ui.swatchPanel.Children.Add($sw)
}

# ===== Speed + limits ======================================================
$script:intervalMs = 100.0
$script:unitFactors = @(1.0, 1000.0, 60000.0)
$script:unitConfigs = @(@(1, 3600000, 0, 10), @(0.001, 3600, 3, 0.1), @(0.00002, 60, 5, 0.1))
$script:syncingSpeed = $false

function Show-IntervalInUnit {
    $i = [Math]::Max(0, $ui.intervalUnit.SelectedIndex); $c = $script:unitConfigs[$i]
    $interval.Configure($c[0], $c[1], $c[2], $c[3], $script:intervalMs / $script:unitFactors[$i])
}
function Get-ClickPeriodMs {
    if ($ui.speedMode.SelectedIndex -eq 1 -and $rate.Value -gt 0) { return 1000.0 / $rate.Value }
    [Math]::Max(1.0, $script:intervalMs)
}
function Get-IntervalMilliseconds { [long][Math]::Max(1, [Math]::Round($script:intervalMs)) }
function Format-Number([double]$v) {
    if ($v -ge 100) { return $v.ToString('N0') }
    if ($v -ge 10) { return $v.ToString('0.#') }
    $v.ToString('0.##')
}
function Update-SpeedUi {
    $cps = ($ui.speedMode.SelectedIndex -eq 1)
    $ui.intervalRow.Visibility = if ($cps) { 'Collapsed' } else { 'Visible' }
    $ui.rateHost.Visibility = if ($cps) { 'Visible' } else { 'Collapsed' }
    $ui.speedValueLabel.Text = if ($cps) { 'CLICKS PER SECOND' } else { 'INTERVAL' }
    $ms = Get-ClickPeriodMs
    $hint = if ($cps) { '= ' + (Format-Number $ms) + ' ms between clicks' } else { '= ' + (Format-Number (1000.0 / $ms)) + ' clicks per second' }
    if ($cps -and $rate.Value -ge $rate.Maximum -and -not (Is-On $ui.extendedSpeed)) { $hint += "   $($script:mid)   Turn on Extended speed limit (Settings > Behavior) for up to 1000" }
    $ui.speedHint.Text = $hint
    if (-not $script:syncingSpeed) {
        $script:syncingSpeed = $true
        $quickRate.SetQuiet([Math]::Round(1000.0 / $ms, 1))
        $script:syncingSpeed = $false
    }
}
function Update-RateLimit {
    $max = if (Is-On $ui.extendedSpeed) { 1000 } else { 500 }
    $rate.Maximum = $max; $quickRate.Maximum = $max
    Update-SpeedUi
}
function Get-ModeText {
    switch ($ui.modePick.SelectedIndex) {
        1 { return ('Stop after {0:N0} clicks' -f $limit.Value) }
        2 { return ('Stop after {0:N0} seconds' -f $limit.Value) }
        default { return 'Continuous' }
    }
}
function Update-ModeUi {
    $i = $ui.modePick.SelectedIndex
    $ui.limitUnit.Text = @('', 'clicks', 'seconds')[[Math]::Max(0, $i)]
    $limit.IsEnabled = ($i -gt 0)
    if (-not $script:running) { $ui.modeLabel.Text = Get-ModeText }
}

$interval.add_ValueChanged({
    $i = [Math]::Max(0, $ui.intervalUnit.SelectedIndex)
    $script:intervalMs = [Math]::Max(1.0, $interval.Value * $script:unitFactors[$i])
    Update-SpeedUi
})
$ui.intervalUnit.Add_SelectionChanged({ Show-IntervalInUnit; Update-SpeedUi })
$ui.speedMode.Add_SelectionChanged({ Update-SpeedUi })
$rate.add_ValueChanged({ Update-SpeedUi })
$quickRate.add_ValueChanged({
    if ($script:syncingSpeed) { return }
    $script:syncingSpeed = $true
    $ui.speedMode.SelectedIndex = 1
    $rate.Value = $quickRate.Value
    $script:syncingSpeed = $false
    Update-SpeedUi
})
$ui.modePick.Add_SelectionChanged({ Update-ModeUi })
$limit.add_ValueChanged({ Update-ModeUi })
On-Toggle $ui.extendedSpeed { Update-RateLimit }

# ===== Click engine ========================================================
$script:running = $false
$script:stopwatch = [System.Diagnostics.Stopwatch]::new()
$script:samples = [System.Collections.Queue]::new()
$script:points = [System.Collections.ArrayList]::new()
$script:processIds = [System.Collections.Generic.List[int]]::new()
$script:selectedProcessTitle = ''
$script:stopReason = $null
$script:startedByHold = $false

function Set-Message([string]$text, [string]$brushKey = 'Muted') {
    $ui.messageLabel.Text = $text
    $ui.messageLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $brushKey)
}
function Set-RunningUi([bool]$on) {
    $start = [string]$ui.keyPick.SelectedItem
    if ($on) {
        $ui.statusText.Text = 'ACTIVE'
        $ui.statusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Warn')
        $ui.statusDot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, 'Warn')
        $ui.startText.Text = "Clicking$($script:ell)  ($start to stop)"
        $ui.startGlyph.Text = [string][char]0xE769
        $ui.quickText.Text = "Clicking$($script:ell)"; $ui.quickGlyph.Text = [string][char]0xE769
        $window.Title = 'TapForge - clicking'
    } else {
        $ui.statusText.Text = 'READY'
        $ui.statusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Good')
        $ui.statusDot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, 'Good')
        $ui.startText.Text = 'Start clicking'; $ui.startGlyph.Text = [string][char]0xE768
        $ui.quickText.Text = 'Start'; $ui.quickGlyph.Text = [string][char]0xE768
        $window.Title = 'TapForge'
    }
    if ($script:trayIcon) { $script:trayIcon.Text = if ($on) { 'TapForge - clicking' } else { 'TapForge' } }
    Update-ActiveOverlay
}
function Update-Readout {
    $count = [ClickNative]::Count
    $ui.countLabel.Text = $count.ToString('N0')
    $ui.elapsedLabel.Text = $script:stopwatch.Elapsed.ToString('hh\:mm\:ss')
    $ui.quickCount.Text = $count.ToString('N0') + ' clicks'
}

function Start-Clicking {
    if ($script:running) { return }
    if ((Is-On $ui.pointsEnabled) -and $script:points.Count -eq 0) {
        Show-Page 'Points'
        [void](Show-TFDialog 'No click points' 'Pick at least one screen location on the Click points page, or turn click points off.')
        return
    }
    if (Is-On $ui.filterProcess) {
        $idx = $ui.processList.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:processIds.Count) {
            Show-Page 'Process'
            [void](Show-TFDialog 'Choose an app' 'Select the app TapForge should click in, or turn off "Only click in the selected app".')
            return
        }
        [ClickNative]::TargetProcessId = $script:processIds[$idx]
    } else { [ClickNative]::TargetProcessId = 0 }

    $mode = $ui.modePick.SelectedIndex
    $maxClicks = if ($mode -eq 1) { [int]$limit.Value } else { 0 }
    $maxSeconds = if ($mode -eq 2) { [int]$limit.Value } else { 0 }
    $perPoint = if (Is-On $ui.pointsEnabled) { [int]$pointClicks.Value } else { 1 }
    if ((Is-On $ui.pointsEnabled) -and (Is-On $ui.stopWhenPointsDone) -and $script:points.Count -gt 0) {
        $maxClicks = $script:points.Count * $perPoint; $maxSeconds = 0
    }
    $vk = [int]$script:sendKeys[[string]$ui.keyCodePick.SelectedItem]
    $flat = [System.Collections.Generic.List[int]]::new()
    if (Is-On $ui.pointsEnabled) { foreach ($p in $script:points) { $flat.Add([int]$p.X); $flat.Add([int]$p.Y) } }
    $downFlags = @(0x0002, 0x0008, 0x0020); $upFlags = @(0x0004, 0x0010, 0x0040)
    $which = [Math]::Max(0, $ui.buttonPick.SelectedIndex)

    [ClickNative]::Configure([int]$randomize.Value, [int]$duty.Value, $maxClicks, $maxSeconds,
        (Is-On $ui.cornerStop), [int]$cornerSize.Value, (Is-On $ui.edgeStop), [int]$edgeSize.Value,
        (Is-On $ui.keyboardMode), $vk, ($ui.clickTypePick.SelectedIndex -eq 1), $flat.ToArray(),
        [int]$pointRadius.Value, $perPoint)
    [ClickNative]::Start([uint32]$downFlags[$which], [uint32]$upFlags[$which], [double](Get-ClickPeriodMs))

    $script:running = $true
    $script:stopReason = $null
    $script:stopwatch.Restart()
    $script:samples.Clear()
    $ui.rateLabel.Text = '0.0 cps'
    $ui.modeLabel.Text = Get-ModeText
    $where = if ((Is-On $ui.pointsEnabled)) { "on $($script:points.Count) click point(s)" } elseif (Is-On $ui.keyboardMode) { "pressing $([string]$ui.keyCodePick.SelectedItem)" } else { 'at your cursor' }
    Set-Message "Clicking $where." 'Accent'
    Set-RunningUi $true
    $script:monitorTimer.Start()
}

function Stop-Clicking([string]$reason) {
    [ClickNative]::Stop()
    if (-not $script:running) { return }
    $script:running = $false
    $script:startedByHold = $false
    $script:stopwatch.Stop()
    $script:monitorTimer.Stop()
    Update-Readout
    $count = [long][ClickNative]::Count
    Add-UsageSession $count $script:stopwatch.Elapsed.TotalSeconds
    Set-RunningUi $false
    if ($reason) {
        Set-Message ("$reason  {0:N0} clicks sent." -f $count) 'Muted'
        if ((Is-On $ui.stopAlert) -and $script:trayIcon) {
            $script:trayIcon.BalloonTipTitle = 'TapForge stopped'
            $script:trayIcon.BalloonTipText = $reason
            $wasVisible = $script:trayIcon.Visible
            $script:trayIcon.Visible = $true
            $script:trayIcon.ShowBalloonTip(2500)
            if (-not $wasVisible -and $window.IsVisible) { $script:hideTrayAfterTip = $true }
        }
    } else {
        Set-Message ('Stopped. {0:N0} clicks sent.' -f $count) 'Muted'
    }
    $ui.modeLabel.Text = Get-ModeText
}
function Switch-Clicking { if ($script:running) { Stop-Clicking } else { Start-Clicking } }

$script:monitorTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:monitorTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$script:monitorTimer.Add_Tick({
    if (-not $script:running) { return }
    Update-Readout
    $count = [ClickNative]::Count; $e = $script:stopwatch.Elapsed.TotalSeconds
    $script:samples.Enqueue(@($e, $count))
    while ($script:samples.Count -gt 1 -and ($e - $script:samples.Peek()[0]) -gt 1.0) { [void]$script:samples.Dequeue() }
    $first = $script:samples.Peek(); $dt = $e - $first[0]
    if ($dt -gt 0.2) { $ui.rateLabel.Text = '{0:N1} cps' -f (($count - $first[1]) / $dt) }
    if (-not [ClickNative]::Active) {
        $mode = $ui.modePick.SelectedIndex
        $reason = if ((Is-On $ui.pointsEnabled) -and (Is-On $ui.stopWhenPointsDone)) { 'All click points done.' }
                  elseif ($mode -eq 1) { 'Click limit reached.' }
                  elseif ($mode -eq 2) { 'Time limit reached.' }
                  else { 'Safety stop: the cursor reached a screen corner or edge.' }
        Stop-Clicking $reason
    }
})

$ui.startButton.Add_Click({ Switch-Clicking })
$ui.stopButton.Add_Click({ Stop-Clicking })
$ui.quickStart.Add_Click({ Switch-Clicking })
$ui.quickStop.Add_Click({ Stop-Clicking })

# ===== Global hotkeys ======================================================
$script:lastStart = $false; $script:lastEmergency = $false
function Test-KeyDown([int]$vk) { ([ClickNative]::GetAsyncKeyState($vk) -band 0x8000) -ne 0 }
$script:hotkeyTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:hotkeyTimer.Interval = [TimeSpan]::FromMilliseconds(15)
$script:hotkeyTimer.Add_Tick({
    if ($script:pickingPoint) { return }
    $startDown = Test-KeyDown ([int]$script:keyMap[[string]$ui.keyPick.SelectedItem])
    $emergencyDown = Test-KeyDown ([int]$script:keyMap[[string]$ui.emergencyKey.SelectedItem])
    $mods = $false
    foreach ($m in @(0x10, 0x11, 0x12, 0x5B, 0x5C)) { if (Test-KeyDown $m) { $mods = $true } }
    $allowed = (-not (Is-On $ui.strictHotkey)) -or (-not $mods)
    if ((Is-On $ui.stopAltTab) -and $script:running -and (Test-KeyDown 0x12) -and (Test-KeyDown 0x09)) { Stop-Clicking 'Stopped after switching windows.' }
    if ($ui.hotkeyMode.SelectedIndex -eq 0) {
        if ($startDown -and -not $script:lastStart -and $allowed) { Switch-Clicking }
    } else {
        if ($startDown -and -not $script:running -and $allowed) { Start-Clicking; if ($script:running) { $script:startedByHold = $true } }
        if (-not $startDown -and $script:running -and $script:startedByHold) { Stop-Clicking }
    }
    if ($emergencyDown -and -not $script:lastEmergency -and $script:running) { Stop-Clicking 'Emergency stop.' }
    $script:lastStart = $startDown; $script:lastEmergency = $emergencyDown
})

function Update-HotkeyCaption {
    $s = [string]$ui.keyPick.SelectedItem; $e = [string]$ui.emergencyKey.SelectedItem
    $text = "$s start / stop   $($script:mid)   $e emergency stop"
    $ui.hotkeyCaption.Text = $text; $ui.quickHotkey.Text = $text
}
$script:prevStartKey = 'F6'; $script:prevEmergencyKey = 'F7'
function Confirm-Keys([string]$changed) {
    $s = [string]$ui.keyPick.SelectedItem; $e = [string]$ui.emergencyKey.SelectedItem
    if ($s -and $s -eq $e) {
        if ($changed -eq 'start') { $ui.keyPick.SelectedItem = $script:prevStartKey } else { $ui.emergencyKey.SelectedItem = $script:prevEmergencyKey }
        $ui.keyWarning.Text = "$s is already used for the other shortcut. Pick a different key."
        $ui.keyWarning.Visibility = 'Visible'
        return
    }
    $ui.keyWarning.Visibility = 'Collapsed'
    $script:prevStartKey = $s; $script:prevEmergencyKey = $e
    Update-HotkeyCaption
}
$ui.keyPick.Add_SelectionChanged({ Confirm-Keys 'start' })
$ui.emergencyKey.Add_SelectionChanged({ Confirm-Keys 'emergency' })
$ui.editKeysButton.Add_Click({ Show-Page 'Keybinds' })

# ===== Navigation ==========================================================
$script:pageMap = [ordered]@{ Clicking = 'pageClicking'; More = 'pageMore'; Points = 'pagePoints'; General = 'pageGeneral'; Behavior = 'pageBehavior'; Appearance = 'pageAppearance'; Keybinds = 'pageKeybinds'; Process = 'pageProcess'; Presets = 'pagePresets'; Maintenance = 'pageMaintenance' }
$script:sideMap = @{ General = 'sideGeneral'; Behavior = 'sideBehavior'; Appearance = 'sideAppearance'; Keybinds = 'sideKeybinds'; Process = 'sideProcess'; Presets = 'sidePresets'; Maintenance = 'sideMaintenance' }
$script:navigating = $false

function Set-NavActive([string]$name, [bool]$on) {
    $b = $ui[$name]
    if ($on) {
        $b.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'Accent')
        $b.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'AccentSoft')
    } else {
        $b.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
        $b.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
    }
}
function Show-Page([string]$name) {
    if ($script:navigating) { return }
    if (-not $script:pageMap.Contains($name)) { $name = 'Clicking' }
    if ($script:compactMode) { Set-Compact $false }
    $script:navigating = $true
    try {
        $script:currentPage = $name
        foreach ($k in $script:pageMap.Keys) { $ui[$script:pageMap[$k]].Visibility = if ($k -eq $name) { 'Visible' } else { 'Collapsed' } }
        $isSettings = $script:sideMap.ContainsKey($name)
        $ui.sidebar.Visibility = if ($isSettings) { 'Visible' } else { 'Collapsed' }
        if ($isSettings) { $script:lastSettingsPage = $name; $ui[$script:sideMap[$name]].IsChecked = $true }
        Set-NavActive 'navSettings' $isSettings
        Set-NavActive 'navClicking' ($name -eq 'Clicking')
        Set-NavActive 'navMore' ($name -eq 'More')
        Set-NavActive 'navPoints' ($name -eq 'Points')
    } finally { $script:navigating = $false }
    Apply-Accent
    if ($name -eq 'Process' -and $ui.processList.Items.Count -eq 0) { Update-ProcessList }
    if ($name -eq 'General') { Update-UsageUi }
}
$ui.navSettings.Add_Click({ Show-Page $script:lastSettingsPage })
$ui.navClicking.Add_Click({ Show-Page 'Clicking' })
$ui.navMore.Add_Click({ Show-Page 'More' })
$ui.navPoints.Add_Click({ Show-Page 'Points' })
$ui.sideGeneral.Add_Checked({ Show-Page 'General' })
$ui.sideBehavior.Add_Checked({ Show-Page 'Behavior' })
$ui.sideAppearance.Add_Checked({ Show-Page 'Appearance' })
$ui.sideKeybinds.Add_Checked({ Show-Page 'Keybinds' })
$ui.sideProcess.Add_Checked({ Show-Page 'Process' })
$ui.sidePresets.Add_Checked({ Show-Page 'Presets' })
$ui.sideMaintenance.Add_Checked({ Show-Page 'Maintenance' })
$ui.sideGithub.Add_Click({ Start-Process $script:repoUrl })
$ui.githubButton.Add_Click({ Start-Process $script:repoUrl })
$ui.changesButton.Add_Click({ Start-Process ($script:repoUrl + '/releases') })

# ===== Window chrome =======================================================
$script:compactMode = $false
$script:normalSize = @(940, 680)
function Update-MaxGlyph {
    $max = ($window.WindowState -eq [System.Windows.WindowState]::Maximized)
    $ui.maxButton.Content = if ($max) { [string][char]0xE923 } else { [string][char]0xE922 }
    $ui.maxButton.ToolTip = if ($max) { 'Restore' } else { 'Maximize' }
    $ui.root.Margin = if ($max) { [System.Windows.Thickness]::new(7) } else { [System.Windows.Thickness]::new(0) }
}
function Set-Compact([bool]$on) {
    if ($on -eq $script:compactMode) { return }
    $script:compactMode = $on
    if ($on) {
        if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) { $window.WindowState = [System.Windows.WindowState]::Normal }
        $script:normalSize = @($window.Width, $window.Height)
        $ui.sidebar.Visibility = 'Collapsed'; $ui.contentFrame.Visibility = 'Collapsed'; $ui.compactPanel.Visibility = 'Visible'
        $window.MinWidth = 520; $window.MinHeight = 140
        $window.Width = 600
        $window.Height = if (Is-On $ui.footerToggle) { 178 } else { 150 }
        $ui.compactButton.Content = [string][char]0xE740; $ui.compactButton.ToolTip = 'Full window'
        $ui.brandTitle.Visibility = 'Collapsed'
    } else {
        $ui.compactPanel.Visibility = 'Collapsed'; $ui.contentFrame.Visibility = 'Visible'
        $window.MinWidth = 800; $window.MinHeight = 580
        $window.Width = [Math]::Max(800, $script:normalSize[0]); $window.Height = [Math]::Max(580, $script:normalSize[1])
        $ui.compactButton.Content = [string][char]0xE73F; $ui.compactButton.ToolTip = 'Compact mode'
        $ui.brandTitle.Visibility = 'Visible'
        Show-Page $script:currentPage
    }
}
$ui.compactButton.Add_Click({ Set-Compact (-not $script:compactMode) })
$ui.minButton.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$ui.maxButton.Add_Click({
    $window.WindowState = if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) { [System.Windows.WindowState]::Normal } else { [System.Windows.WindowState]::Maximized }
})
$ui.closeButton.Add_Click({ $window.Close() })
$ui.pinButton.Add_Click({ $ui.alwaysTop.IsChecked = -not (Is-On $ui.alwaysTop) })
On-Toggle $ui.alwaysTop {
    $on = Is-On $ui.alwaysTop
    $window.Topmost = $on
    $ui.pinButton.Content = if ($on) { [string][char]0xE840 } else { [string][char]0xE718 }
    Set-NavActive 'pinButton' $on
}
On-Toggle $ui.footerToggle { $ui.footer.Visibility = if (Is-On $ui.footerToggle) { 'Visible' } else { 'Collapsed' } }
$window.Add_SourceInitialized({
    $script:hwnd = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
    [TapForgeShell]::StyleWindow($script:hwnd, -not $script:lightTheme)
})
$window.Add_StateChanged({
    Update-MaxGlyph
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized -and (Is-On $ui.minimizeTray)) {
        $window.Hide(); $script:trayIcon.Visible = $true
    }
})

# ===== Dialogs =============================================================
function Show-TFDialog([string]$title, [string]$message, [string[]]$buttons = @('OK'), [int]$primary = -1, [switch]$WithInput, [string]$default = '') {
    $d = [System.Windows.Markup.XamlReader]::Parse($dialogXaml)
    $d.FindName('dlgTitle').Text = $title
    $d.FindName('dlgMessage').Text = $message
    $script:dlgInput = $d.FindName('dlgInput')
    if ($WithInput) { $script:dlgInput.Visibility = 'Visible'; $script:dlgInput.Text = $default }
    if ($primary -lt 0) { $primary = $buttons.Count - 1 }
    $panel = $d.FindName('dlgButtons')
    $script:dlgResult = -1; $script:dlgText = $null
    for ($i = 0; $i -lt $buttons.Count; $i++) {
        $b = [System.Windows.Controls.Button]::new()
        $b.Content = $buttons[$i]; $b.MinWidth = 96; $b.Tag = $i
        $b.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        if ($i -eq $primary) { $b.Style = $script:app.Resources['AccentButton']; $b.IsDefault = $true }
        if ($buttons[$i] -in @('Cancel', 'No', 'Not now')) { $b.IsCancel = $true }
        $b.Add_Click({
            param($s, $e)
            $script:dlgResult = [int]$s.Tag
            $script:dlgText = $script:dlgInput.Text
            [System.Windows.Window]::GetWindow($s).Close()
        })
        [void]$panel.Children.Add($b)
    }
    if ($window.IsVisible) { $d.Owner = $window } else { $d.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen; $d.Topmost = $true }
    $d.Add_ContentRendered({ if ($script:dlgInput.Visibility -eq 'Visible') { [void]$script:dlgInput.Focus(); $script:dlgInput.SelectAll() } })
    [void]$d.ShowDialog()
    $script:dlgResult
}

function Convert-HsvToColor([double]$h, [double]$s, [double]$v) {
    $h = (($h % 360) + 360) % 360
    $c = $v * $s; $x = $c * (1 - [Math]::Abs((($h / 60) % 2) - 1)); $m = $v - $c
    if ($h -lt 60) { $r = $c; $g = $x; $b = 0 } elseif ($h -lt 120) { $r = $x; $g = $c; $b = 0 } elseif ($h -lt 180) { $r = 0; $g = $c; $b = $x }
    elseif ($h -lt 240) { $r = 0; $g = $x; $b = $c } elseif ($h -lt 300) { $r = $x; $g = 0; $b = $c } else { $r = $c; $g = 0; $b = $x }
    [System.Windows.Media.Color]::FromRgb([byte][Math]::Round(($r + $m) * 255), [byte][Math]::Round(($g + $m) * 255), [byte][Math]::Round(($b + $m) * 255))
}
function Convert-ColorToHsv([System.Windows.Media.Color]$c) {
    $r = $c.R / 255.0; $g = $c.G / 255.0; $b = $c.B / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b)); $min = [Math]::Min($r, [Math]::Min($g, $b)); $delta = $max - $min
    $h = 0.0
    if ($delta -gt 0) {
        if ($max -eq $r) { $h = 60 * ((($g - $b) / $delta) % 6) } elseif ($max -eq $g) { $h = 60 * ((($b - $r) / $delta) + 2) } else { $h = 60 * ((($r - $g) / $delta) + 4) }
    }
    if ($h -lt 0) { $h += 360 }
    $s = if ($max -eq 0) { 0.0 } else { $delta / $max }
    @($h, $s, $max)
}
function Show-ColorPicker([string]$initialHex) {
    $d = [System.Windows.Markup.XamlReader]::Parse($colorXaml)
    $script:cp = @{}
    foreach ($n in @('cpPreview', 'cpHex', 'cpHue', 'cpSat', 'cpVal', 'cpSwatches', 'cpCancel', 'cpApply')) { $script:cp[$n] = $d.FindName($n) }
    $script:cpResult = $null; $script:cpBusy = $false
    $script:cpSetFromHex = {
        param([string]$hex)
        $hsv = Convert-ColorToHsv (ConvertTo-MediaColor $hex)
        $script:cpBusy = $true
        $script:cp.cpHue.Value = $hsv[0]; $script:cp.cpSat.Value = $hsv[1] * 100; $script:cp.cpVal.Value = $hsv[2] * 100
        $script:cpBusy = $false
        & $script:cpRefresh $true
    }
    $script:cpRefresh = {
        param([bool]$updateHex)
        $c = Convert-HsvToColor $script:cp.cpHue.Value ($script:cp.cpSat.Value / 100) ($script:cp.cpVal.Value / 100)
        $script:cp.cpPreview.Background = [System.Windows.Media.SolidColorBrush]::new($c)
        $pure = Convert-HsvToColor $script:cp.cpHue.Value 1 1
        $script:cp.cpSat.Background = [System.Windows.Media.LinearGradientBrush]::new([System.Windows.Media.Colors]::White, (Convert-HsvToColor $script:cp.cpHue.Value 1 ($script:cp.cpVal.Value / 100)), 0)
        $script:cp.cpVal.Background = [System.Windows.Media.LinearGradientBrush]::new([System.Windows.Media.Colors]::Black, (Convert-HsvToColor $script:cp.cpHue.Value ($script:cp.cpSat.Value / 100) 1), 0)
        if ($updateHex) { $script:cpBusy = $true; $script:cp.cpHex.Text = ConvertTo-Hex $c; $script:cpBusy = $false }
    }
    foreach ($n in @('cpHue', 'cpSat', 'cpVal')) { $script:cp[$n].Add_ValueChanged({ if (-not $script:cpBusy) { & $script:cpRefresh $true } }) }
    $script:cp.cpHex.Add_TextChanged({
        if ($script:cpBusy) { return }
        $t = $script:cp.cpHex.Text.Trim(); if ($t -notmatch '^#') { $t = '#' + $t }
        if (Test-Hex $t) {
            $hsv = Convert-ColorToHsv (ConvertTo-MediaColor $t)
            $script:cpBusy = $true
            $script:cp.cpHue.Value = $hsv[0]; $script:cp.cpSat.Value = $hsv[1] * 100; $script:cp.cpVal.Value = $hsv[2] * 100
            $script:cpBusy = $false
            & $script:cpRefresh $false
        }
    })
    foreach ($hex in $script:swatches) {
        $sw = [System.Windows.Controls.Border]::new()
        $sw.Width = 24; $sw.Height = 24; $sw.CornerRadius = [System.Windows.CornerRadius]::new(12)
        $sw.Margin = [System.Windows.Thickness]::new(0, 0, 7, 7); $sw.Background = New-Brush $hex
        $sw.Cursor = [System.Windows.Input.Cursors]::Hand; $sw.Tag = $hex
        $sw.Add_MouseLeftButtonUp({ param($s, $e) & $script:cpSetFromHex ([string]$s.Tag) })
        [void]$script:cp.cpSwatches.Children.Add($sw)
    }
    $script:cp.cpApply.Add_Click({
        param($s, $e)
        $script:cpResult = ConvertTo-Hex (Convert-HsvToColor $script:cp.cpHue.Value ($script:cp.cpSat.Value / 100) ($script:cp.cpVal.Value / 100))
        [System.Windows.Window]::GetWindow($s).Close()
    })
    $script:cp.cpCancel.IsCancel = $true
    $d.Owner = $window
    & $script:cpSetFromHex $initialHex
    [void]$d.ShowDialog()
    $script:cpResult
}

# ===== Appearance ==========================================================
$ui.themePick.Add_SelectionChanged({ Apply-Theme })
$ui.appearanceModePick.Add_SelectionChanged({ Apply-Accent -Force })
$ui.accentTarget.Add_SelectionChanged({ Update-AccentUi })
$ui.hueButton.Add_Click({ $picked = Show-ColorPicker (Get-EditedAccent); if ($picked) { Set-EditedAccent $picked } })
$ui.iconTheme.Add_SelectionChanged({ Update-Icons })
$ui.iconColor.Add_SelectionChanged({ Update-Icons })
On-Toggle $ui.activeIcon { Update-ActiveOverlay }

# ===== Click points ========================================================
$script:pickingPoint = $false
function Update-PointList {
    $ui.pointList.Items.Clear()
    $i = 0
    foreach ($p in $script:points) { $i++; [void]$ui.pointList.Items.Add(("Point {0}    X {1},  Y {2}" -f $i, $p.X, $p.Y)) }
    $ui.pointsSummary.Text = if ($script:points.Count -eq 0) { 'No points yet. Click "Pick point", then click anywhere on screen.' } else { "$($script:points.Count) point(s), clicked in order." }
}
$ui.pickPoint.Add_Click({
    $script:pickingPoint = $true
    $overlay = [System.Windows.Forms.Form]::new()
    $overlay.FormBorderStyle = 'None'; $overlay.StartPosition = 'Manual'
    $overlay.Bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $overlay.TopMost = $true; $overlay.ShowInTaskbar = $false; $overlay.KeyPreview = $true
    $overlay.BackColor = [System.Drawing.Color]::Black; $overlay.Opacity = 0.35
    $overlay.Cursor = [System.Windows.Forms.Cursors]::Cross
    $tip = [System.Windows.Forms.Label]::new()
    $tip.Text = 'Click where TapForge should click   ' + $script:mid + '   Esc to cancel'
    $tip.ForeColor = [System.Drawing.Color]::White; $tip.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 34)
    $tip.Font = [System.Drawing.Font]::new('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $tip.AutoSize = $true; $tip.Padding = [System.Windows.Forms.Padding]::new(14, 8, 14, 8)
    $primary = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $tip.Location = [System.Drawing.Point]::new($primary.X - $overlay.Bounds.X + 40, $primary.Y - $overlay.Bounds.Y + 40)
    $overlay.Controls.Add($tip)
    $overlay.Add_MouseDown({
        param($s, $e)
        $pos = [System.Windows.Forms.Cursor]::Position
        [void]$script:points.Add([System.Drawing.Point]::new($pos.X, $pos.Y))
        $s.Close()
    })
    $overlay.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $s.Close() } })
    $window.Hide()
    try { [void]$overlay.ShowDialog() } finally {
        $overlay.Dispose()
        $window.Show(); [void]$window.Activate()
        $script:pickingPoint = $false
        Update-PointList
    }
})
$ui.removePoint.Add_Click({
    $i = $ui.pointList.SelectedIndex
    if ($i -ge 0 -and $i -lt $script:points.Count) { $script:points.RemoveAt($i); Update-PointList }
})
$ui.clearPoints.Add_Click({
    if ($script:points.Count -eq 0) { return }
    if ((Show-TFDialog 'Clear all points?' "Remove all $($script:points.Count) click points?" @('Cancel', 'Clear all')) -eq 1) { $script:points.Clear(); Update-PointList }
})

# ===== Process list ========================================================
function Update-ProcessList {
    $ui.processList.Items.Clear(); $script:processIds.Clear()
    $keep = -1
    $procs = [System.Diagnostics.Process]::GetProcesses() | Where-Object { $_.MainWindowTitle -and $_.Id -ne $PID } | Sort-Object MainWindowTitle
    foreach ($p in $procs) {
        [void]$ui.processList.Items.Add(('{0}   (PID {1})' -f $p.MainWindowTitle, $p.Id))
        $script:processIds.Add($p.Id)
        if ($script:selectedProcessTitle -and $p.MainWindowTitle -eq $script:selectedProcessTitle) { $keep = $script:processIds.Count - 1 }
    }
    if ($keep -ge 0) { $ui.processList.SelectedIndex = $keep }
}
$ui.refreshProcesses.Add_Click({ Update-ProcessList })
$ui.processList.Add_SelectionChanged({
    $item = [string]$ui.processList.SelectedItem
    if ($item) {
        $script:selectedProcessTitle = $item -replace '   \(PID \d+\)$', ''
        $ui.processSelectedLabel.Text = 'Selected: ' + $script:selectedProcessTitle
    }
})

# ===== Presets =============================================================
$script:activePreset = $null
function Update-Footer {
    $ui.footerLeft.Text = if ($script:activePreset) { 'Preset: ' + $script:activePreset } else { 'No preset active' }
}
function Update-PresetList {
    $ui.presetList.Items.Clear()
    foreach ($f in (Get-ChildItem -LiteralPath $script:presetDirectory -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        [void]$ui.presetList.Items.Add([System.IO.Path]::GetFileNameWithoutExtension($f.Name))
    }
    $ui.presetSummary.Text = if ($ui.presetList.Items.Count -eq 0) { 'No presets yet.' } else { 'Double-click a preset to load it.' }
}
function Get-PresetData {
    @{
        intervalMs = (Get-IntervalMilliseconds); intervalMsExact = $script:intervalMs; interval = [double]$interval.Value; intervalUnit = $ui.intervalUnit.SelectedIndex
        button = $ui.buttonPick.SelectedIndex; stopMode = $ui.modePick.SelectedIndex; limit = [long]$limit.Value
        speedMode = $ui.speedMode.SelectedIndex; rate = [double]$rate.Value; extended = (Is-On $ui.extendedSpeed)
        hotkey = [string]$ui.keyPick.SelectedItem; hotkeyMode = $ui.hotkeyMode.SelectedIndex
        keyboard = (Is-On $ui.keyboardMode); keyCode = $ui.keyCodePick.SelectedIndex; double = ($ui.clickTypePick.SelectedIndex -eq 1)
        duty = [int]$duty.Value; random = [int]$randomize.Value
        corners = (Is-On $ui.cornerStop); cornerSize = [int]$cornerSize.Value; edges = (Is-On $ui.edgeStop); edgeSize = [int]$edgeSize.Value
    }
}
function Has-Prop($obj, [string]$name) { $null -ne $obj -and $null -ne $obj.PSObject.Properties[$name] }
function Set-IntervalFromData($d) {
    if (Has-Prop $d 'intervalUnit') { Set-Index $ui.intervalUnit $d.intervalUnit }
    if (Has-Prop $d 'intervalMsExact') { $script:intervalMs = [Math]::Max(1.0, [double]$d.intervalMsExact) }
    elseif (Has-Prop $d 'intervalMs') { $script:intervalMs = [Math]::Max(1.0, [double]$d.intervalMs) }
    elseif (Has-Prop $d 'interval') { $script:intervalMs = [Math]::Max(1.0, [double]$d.interval) }
    Show-IntervalInUnit
}
function Apply-PresetData($d) {
    if (Has-Prop $d 'extended') { $ui.extendedSpeed.IsChecked = [bool]$d.extended }
    Update-RateLimit
    Set-IntervalFromData $d
    if (Has-Prop $d 'button') { Set-Index $ui.buttonPick $d.button }
    if (Has-Prop $d 'stopMode') { Set-Index $ui.modePick $d.stopMode }
    if (Has-Prop $d 'limit') { $limit.Value = [double]$d.limit }
    if (Has-Prop $d 'speedMode') { Set-Index $ui.speedMode $d.speedMode }
    if (Has-Prop $d 'rate') { $rate.Value = [double]$d.rate }
    if ((Has-Prop $d 'hotkey') -and $ui.keyPick.Items.Contains([string]$d.hotkey) -and [string]$d.hotkey -ne [string]$ui.emergencyKey.SelectedItem) { $ui.keyPick.SelectedItem = [string]$d.hotkey }
    if (Has-Prop $d 'hotkeyMode') { Set-Index $ui.hotkeyMode $d.hotkeyMode }
    if (Has-Prop $d 'keyboard') { $ui.keyboardMode.IsChecked = [bool]$d.keyboard }
    if (Has-Prop $d 'keyCode') { Set-Index $ui.keyCodePick $d.keyCode }
    if (Has-Prop $d 'double') { $ui.clickTypePick.SelectedIndex = if ([bool]$d.double) { 1 } else { 0 } }
    if (Has-Prop $d 'duty') { $duty.Value = [double]$d.duty }
    if (Has-Prop $d 'random') { $randomize.Value = [double]$d.random }
    if (Has-Prop $d 'corners') { $ui.cornerStop.IsChecked = [bool]$d.corners }
    if (Has-Prop $d 'cornerSize') { $cornerSize.Value = [double]$d.cornerSize }
    if (Has-Prop $d 'edges') { $ui.edgeStop.IsChecked = [bool]$d.edges }
    if (Has-Prop $d 'edgeSize') { $edgeSize.Value = [double]$d.edgeSize }
    Update-SpeedUi; Update-ModeUi
}
function Load-SelectedPreset {
    $name = [string]$ui.presetList.SelectedItem
    if (-not $name) { return }
    try {
        $d = Get-Content -LiteralPath (Join-Path $script:presetDirectory ($name + '.json')) -Raw | ConvertFrom-Json
        Apply-PresetData $d
        $script:activePreset = $name; Update-Footer
        Set-Message "Loaded preset '$name'." 'Accent'
    } catch { [void](Show-TFDialog 'Could not load preset' $_.Exception.Message) }
}
$ui.presetSave.Add_Click({
    $name = ($ui.presetName.Text -replace '[^a-zA-Z0-9 _-]', '').Trim()
    if (-not $name) { [void](Show-TFDialog 'Name your preset' 'Type a name for the preset first (letters, numbers, spaces, - and _).'); return }
    $path = Join-Path $script:presetDirectory ($name + '.json')
    if ((Test-Path -LiteralPath $path) -and (Show-TFDialog 'Replace preset?' "A preset named '$name' already exists. Replace it?" @('Cancel', 'Replace')) -ne 1) { return }
    Get-PresetData | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
    $script:activePreset = $name; Update-Footer; Update-PresetList
    $ui.presetList.SelectedItem = $name; $ui.presetName.Text = ''
})
$ui.presetLoad.Add_Click({ Load-SelectedPreset })
$ui.presetList.Add_MouseDoubleClick({ Load-SelectedPreset })
$ui.presetDelete.Add_Click({
    $name = [string]$ui.presetList.SelectedItem
    if (-not $name) { return }
    if ((Show-TFDialog 'Delete preset?' "Delete the preset '$name'? This can't be undone." @('Cancel', 'Delete')) -ne 1) { return }
    Remove-Item -LiteralPath (Join-Path $script:presetDirectory ($name + '.json')) -Force -ErrorAction SilentlyContinue
    if ($script:activePreset -eq $name) { $script:activePreset = $null; Update-Footer }
    Update-PresetList
})

# ===== Usage statistics ====================================================
$script:usage = @{ clicks = 0L; sessions = 0; seconds = 0.0; last = '' }
try {
    if (Test-Path -LiteralPath $script:usageFile) {
        $u = Get-Content -LiteralPath $script:usageFile -Raw | ConvertFrom-Json
        $script:usage = @{ clicks = [long]$u.clicks; sessions = [int]$u.sessions; seconds = [double]$u.seconds; last = [string]$u.last }
    }
} catch { }
function Save-Usage { try { $script:usage | ConvertTo-Json | Set-Content -LiteralPath $script:usageFile -Encoding UTF8 } catch { } }
function Add-UsageSession([long]$clicks, [double]$seconds) {
    if ($clicks -le 0) { return }
    $script:usage.clicks += $clicks; $script:usage.sessions += 1; $script:usage.seconds += $seconds
    $script:usage.last = (Get-Date).ToString('o')
    Save-Usage
}
function Update-UsageUi {
    $has = $script:usage.sessions -gt 0
    $ui.usageEmpty.Visibility = if ($has) { 'Collapsed' } else { 'Visible' }
    $ui.usageGrid.Visibility = if ($has) { 'Visible' } else { 'Collapsed' }
    if (-not $has) { return }
    $ui.usageClicks.Text = ([long]$script:usage.clicks).ToString('N0')
    $ui.usageSessions.Text = ([int]$script:usage.sessions).ToString('N0')
    $t = [TimeSpan]::FromSeconds([double]$script:usage.seconds)
    $ui.usageTime.Text = if ($t.TotalHours -ge 1) { '{0}h {1}m' -f [int][Math]::Floor($t.TotalHours), $t.Minutes } elseif ($t.TotalMinutes -ge 1) { '{0}m {1}s' -f $t.Minutes, $t.Seconds } else { '{0}s' -f [int]$t.TotalSeconds }
    $ui.usageLast.Text = try { ([datetime]$script:usage.last).ToString('MMM d, h:mm tt') } catch { '-' }
}

# ===== Behavior ============================================================
$script:restoring = $false
On-Toggle $ui.runOnStartup {
    if ($script:restoring) { return }
    try {
        $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', $true)
        if (Is-On $ui.runOnStartup) { $rk.SetValue('TapForge', '"' + $script:exePath + '"') } else { $rk.DeleteValue('TapForge', $false) }
        $rk.Dispose()
    } catch { [void](Show-TFDialog 'Startup setting' 'Could not update the Windows startup setting.') }
}

# ===== Maintenance + updates ===============================================
$script:publisherPath = Join-Path $script:exeDir 'TapForge Publisher.ps1'
$ui.publishUpdateButton.Visibility = if (Test-Path -LiteralPath $script:publisherPath) { 'Visible' } else { 'Collapsed' }
function Set-UpdateStatus([string]$text) { $ui.updateStatus.Text = $text; $ui.maintUpdateStatus.Text = $text }
Set-UpdateStatus "Current version: v$($script:appVersion)"
$ui.openDiagnostics.Add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $script:diagDir + '"') })
$ui.exportDiagnostics.Add_Click({
    $dlg = [Microsoft.Win32.SaveFileDialog]::new(); $dlg.Filter = 'JSON report|*.json'; $dlg.FileName = 'TapForge-diagnostics.json'
    if ($dlg.ShowDialog($window)) {
        $logTail = @(); try { $logTail = @(Get-Content -LiteralPath $script:logFile -Tail 50 -ErrorAction Stop) } catch { }
        [ordered]@{
            app = 'TapForge'; version = $script:appVersion; created = (Get-Date).ToString('o')
            windows = [Environment]::OSVersion.Version.ToString(); powershell = $PSVersionTable.PSVersion.ToString()
            clr = [Environment]::Version.ToString(); clickEngine = 'Native high-resolution worker (waitable timer)'
            usage = $script:usage; log = $logTail
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8
        Set-UpdateStatus ('Report saved to ' + $dlg.FileName)
    }
})
$ui.resetUsage.Add_Click({
    if ((Show-TFDialog 'Reset usage data?' 'Clear all click statistics? This cannot be undone.' @('Cancel', 'Reset')) -ne 1) { return }
    $script:usage = @{ clicks = 0L; sessions = 0; seconds = 0.0; last = '' }; Save-Usage; Update-UsageUi
})

$script:updateRequest = $null; $script:downloadRequest = $null
$script:updateTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:updateTimer.Interval = [TimeSpan]::FromMilliseconds(150)
function Start-UpdateCheck([bool]$automatic) {
    if ($script:updateRequest -or $script:downloadRequest) { return }
    $script:updateAutomatic = $automatic
    Set-UpdateStatus "Checking for updates$($script:ell)"
    $script:updateRequest = [TapForgeRequest]::GetText('https://api.github.com/repos/saberapexyt-commits/TapForge/releases/latest')
    $script:updateTimer.Start()
}
function Install-TapForgeRelease($release) {
    $tag = [string]$release.tag_name
    $updates = Join-Path $script:dataDir 'Updates'; [void](New-Item -ItemType Directory -Force -Path $updates)
    # New releases ship a single TapForge.exe. Older releases only have the portable ZIP.
    $exeAsset = @($release.assets | Where-Object { $_.name -eq 'TapForge.exe' } | Select-Object -First 1)[0]
    if ($exeAsset) {
        $script:pendingUpdate = @{ Mode = 'exe'; Tag = $tag; Asset = $exeAsset; File = (Join-Path $updates "TapForge-$tag.exe") }
    } else {
        $zipName = "TapForge-$tag-Portable.zip"
        $zipAsset = @($release.assets | Where-Object { $_.name -eq $zipName } | Select-Object -First 1)[0]
        if (-not $zipAsset) { [void](Show-TFDialog 'Update' "The $tag release doesn't include a download yet. Try again in a minute."); return }
        $script:pendingUpdate = @{ Mode = 'zip'; Tag = $tag; Asset = $zipAsset; File = (Join-Path $updates $zipName); Stage = (Join-Path $updates ([guid]::NewGuid().ToString('N'))) }
    }
    Set-UpdateStatus "Downloading $tag$($script:ell)"
    $script:downloadRequest = [TapForgeRequest]::Download([string]$script:pendingUpdate.Asset.browser_download_url, $script:pendingUpdate.File)
    $script:updateTimer.Start()
}
function Start-UpdateHelper([string]$helperScript, [string]$argLine) {
    $helper = Join-Path $script:dataDir 'Updates\Apply-TapForgeUpdate.ps1'
    $helperScript | Set-Content -LiteralPath $helper -Encoding UTF8
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$helper`" " + $argLine) -WindowStyle Hidden
    $script:exitRequested = $true; $window.Close()
}
function Complete-TapForgeInstall {
    $u = $script:pendingUpdate; $target = $script:exeDir
    try {
        if ($u.Asset.digest -and ([string]$u.Asset.digest -match '^sha256:([0-9a-fA-F]{64})$')) {
            $expected = $Matches[1]; $actual = (Get-FileHash -LiteralPath $u.File -Algorithm SHA256).Hash
            if ($actual -ne $expected) { throw 'The downloaded update did not pass its SHA-256 check.' }
        }
        $probe = Join-Path $target '.tapforge-update-check'; Set-Content -LiteralPath $probe -Value 'ok' -Encoding ascii; Remove-Item -LiteralPath $probe -Force
        if ($u.Mode -eq 'exe') {
            $bytes = [System.IO.File]::ReadAllBytes($u.File)
            if ($bytes.Length -lt 20000 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'The downloaded file is not a valid TapForge.exe.' }
            Start-UpdateHelper @'
param([string]$NewExe,[string]$TargetExe,[int]$WaitPid)
for($i=0;$i -lt 120;$i++){if(!(Get-Process -Id $WaitPid -ErrorAction SilentlyContinue)){break};Start-Sleep -Milliseconds 500}
$ok=$false
for($i=0;$i -lt 40 -and -not $ok;$i++){try{Copy-Item -LiteralPath $NewExe -Destination $TargetExe -Force -ErrorAction Stop;$ok=$true}catch{Start-Sleep -Milliseconds 500}}
Start-Process -FilePath $TargetExe -WorkingDirectory (Split-Path -Parent $TargetExe)
'@ ("-NewExe `"$($u.File)`" -TargetExe `"$($script:exePath)`" -WaitPid $PID")
        } else {
            [void](New-Item -ItemType Directory -Force -Path $u.Stage)
            Expand-Archive -LiteralPath $u.File -DestinationPath $u.Stage -Force
            if (-not (Test-Path -LiteralPath (Join-Path $u.Stage 'TapForge.exe'))) { throw 'The update package is missing TapForge.exe.' }
            Start-UpdateHelper @'
param([string]$TargetDir,[string]$StageDir,[int]$WaitPid)
for($i=0;$i -lt 120;$i++){if(!(Get-Process -Id $WaitPid -ErrorAction SilentlyContinue)){break};Start-Sleep -Milliseconds 500}
foreach($name in @('TapForge.exe','AutoClicker.ps1','TapForge.ico','TapForgeLogo.png','VERSION','README.txt','Launch AutoClicker.bat')){$from=Join-Path $StageDir $name;if(Test-Path -LiteralPath $from){for($i=0;$i -lt 20;$i++){try{Copy-Item -LiteralPath $from -Destination (Join-Path $TargetDir $name) -Force -ErrorAction Stop;break}catch{Start-Sleep -Milliseconds 500}}}}
Start-Process -FilePath (Join-Path $TargetDir 'TapForge.exe') -WorkingDirectory $TargetDir
'@ ("-TargetDir `"$target`" -StageDir `"$($u.Stage)`" -WaitPid $PID")
        }
    } catch {
        Set-UpdateStatus 'Update failed.'
        [void](Show-TFDialog 'Update failed' ("TapForge could not install the update.`n`n" + $_.Exception.Message))
        if ($u.Stage -and (Test-Path -LiteralPath $u.Stage)) { Remove-Item -LiteralPath $u.Stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
$script:updateTimer.Add_Tick({
    if ($script:downloadRequest) {
        $r = $script:downloadRequest
        if (-not $r.Done) {
            if ($r.Total -gt 0) { Set-UpdateStatus ('Downloading {0}{1} {2:N0}%' -f $script:pendingUpdate.Tag, $script:ell, (100.0 * $r.Received / $r.Total)) }
            return
        }
        $script:updateTimer.Stop(); $script:downloadRequest = $null
        if ($r.Error) { Set-UpdateStatus 'Download failed.'; [void](Show-TFDialog 'Update failed' ("Could not download the update.`n`n" + $r.Error)); return }
        Complete-TapForgeInstall
        return
    }
    $r = $script:updateRequest
    if (-not $r -or -not $r.Done) { return }
    $script:updateTimer.Stop(); $script:updateRequest = $null
    if ($r.Error) {
        Set-UpdateStatus 'Could not check for updates.'
        if (-not $script:updateAutomatic) { [void](Show-TFDialog 'Update check' ("Could not check for updates.`n`n" + $r.Error)) }
        return
    }
    try { $release = ConvertFrom-Json -InputObject $r.Text } catch { Set-UpdateStatus 'Could not read the update information.'; return }
    $available = try { ([version]([string]$release.tag_name -replace '^v', '')) -gt ([version]$script:appVersion) } catch { $false }
    if (-not $available) {
        Set-UpdateStatus "You're up to date (v$($script:appVersion))."
        if (-not $script:updateAutomatic) { [void](Show-TFDialog 'Up to date' "TapForge v$($script:appVersion) is the latest version.") }
        return
    }
    Set-UpdateStatus "Update available: $($release.tag_name)"
    $notes = ([string]$release.body).Trim()
    if ($notes.Length -gt 700) { $notes = $notes.Substring(0, 700) + $script:ell }
    $whatsNew = if ($notes) { "`n`nWhat's new:`n$notes" } else { '' }
    if ((Show-TFDialog 'Update available' "TapForge $($release.tag_name) is available.$whatsNew`n`nInstall it now? TapForge will close and reopen." @('Not now', 'Install')) -eq 1) { Install-TapForgeRelease $release }
})
$ui.checkUpdateButton.Add_Click({ Start-UpdateCheck $false })
$ui.maintCheckButton.Add_Click({ Start-UpdateCheck $false })
$ui.publishUpdateButton.Add_Click({
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$($script:publisherPath)`"" -WorkingDirectory $script:exeDir -WindowStyle Hidden
})

# ===== Tray ================================================================
$script:exitRequested = $false
$script:trayIcon = [System.Windows.Forms.NotifyIcon]::new()
$script:trayIcon.Text = 'TapForge'
if ($script:trayIconImage) { $script:trayIcon.Icon = $script:trayIconImage }
elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'TapForge.ico')) { $script:trayIcon.Icon = [System.Drawing.Icon]::new((Join-Path $PSScriptRoot 'TapForge.ico')) }
$trayMenu = [System.Windows.Forms.ContextMenuStrip]::new()
$trayOpen = $trayMenu.Items.Add('Open TapForge')
$trayToggle = $trayMenu.Items.Add('Start / stop clicking')
[void]$trayMenu.Items.Add('-')
$trayExit = $trayMenu.Items.Add('Exit')
$script:trayIcon.ContextMenuStrip = $trayMenu
$script:RestoreFromTray = {
    $window.Show()
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) { $window.WindowState = [System.Windows.WindowState]::Normal }
    [void]$window.Activate()
    $script:trayIcon.Visible = $false
}
$trayOpen.Add_Click({ & $script:RestoreFromTray })
$trayToggle.Add_Click({ Switch-Clicking })
$trayExit.Add_Click({ $script:exitRequested = $true; $window.Close() })
$script:trayIcon.Add_DoubleClick({ & $script:RestoreFromTray })
$script:trayIcon.Add_BalloonTipClosed({ if ($script:hideTrayAfterTip -and $window.IsVisible) { $script:trayIcon.Visible = $false }; $script:hideTrayAfterTip = $false })

# ===== Settings ============================================================
function Save-UserSettings {
    try {
        $accents = @{}; foreach ($k in $script:pageAccents.Keys) { $accents[$k] = $script:pageAccents[$k] }
        $saved = [ordered]@{
            intervalMs = (Get-IntervalMilliseconds); intervalMsExact = $script:intervalMs; intervalUnit = $ui.intervalUnit.SelectedIndex
            button = $ui.buttonPick.SelectedIndex; stopMode = $ui.modePick.SelectedIndex; limit = [long]$limit.Value
            speedMode = $ui.speedMode.SelectedIndex; rate = [double]$rate.Value; extendedSpeed = (Is-On $ui.extendedSpeed)
            startKey = [string]$ui.keyPick.SelectedItem; emergencyKey = [string]$ui.emergencyKey.SelectedItem; hotkeyMode = $ui.hotkeyMode.SelectedIndex
            keyboardMode = (Is-On $ui.keyboardMode); keyCode = $ui.keyCodePick.SelectedIndex; doubleClick = ($ui.clickTypePick.SelectedIndex -eq 1)
            duty = [int]$duty.Value; randomize = [int]$randomize.Value
            cornerStop = (Is-On $ui.cornerStop); cornerSize = [int]$cornerSize.Value; edgeStop = (Is-On $ui.edgeStop); edgeSize = [int]$edgeSize.Value
            alwaysTop = (Is-On $ui.alwaysTop); stopAlert = (Is-On $ui.stopAlert); strictHotkey = (Is-On $ui.strictHotkey); stopAltTab = (Is-On $ui.stopAltTab)
            minimizeTray = (Is-On $ui.minimizeTray); rememberPosition = (Is-On $ui.rememberPosition); runOnStartup = (Is-On $ui.runOnStartup)
            pointDefaultClicks = [int]$pointClicks.Value; pointDefaultRadius = [int]$pointRadius.Value
            pointsEnabled = (Is-On $ui.pointsEnabled); stopWhenPointsDone = (Is-On $ui.stopWhenPointsDone)
            points = @($script:points | ForEach-Object { @{ x = $_.X; y = $_.Y } })
            filterProcess = (Is-On $ui.filterProcess); processTitle = $script:selectedProcessTitle
            theme = $ui.themePick.SelectedIndex; appearanceMode = $ui.appearanceModePick.SelectedIndex; globalAccent = $script:globalAccent; pageAccents = $accents
            activeIcon = (Is-On $ui.activeIcon); iconTheme = $ui.iconTheme.SelectedIndex; iconColor = $ui.iconColor.SelectedIndex
            footer = (Is-On $ui.footerToggle); page = $script:currentPage; compact = $script:compactMode; activePreset = $script:activePreset
        }
        $tmp = $script:settingsFile + '.tmp'
        $saved | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $script:settingsFile -Force
    } catch { Write-TFLog ('Save settings failed: ' + $_.Exception.Message) }
}
function Restore-UserSettings {
    if (-not (Test-Path -LiteralPath $script:settingsFile)) { return }
    $script:restoring = $true
    try {
        $d = Get-Content -LiteralPath $script:settingsFile -Raw | ConvertFrom-Json
        if (Has-Prop $d 'extendedSpeed') { $ui.extendedSpeed.IsChecked = [bool]$d.extendedSpeed }
        Update-RateLimit
        Set-IntervalFromData $d
        if (Has-Prop $d 'button') { Set-Index $ui.buttonPick $d.button }
        if (Has-Prop $d 'stopMode') { Set-Index $ui.modePick $d.stopMode }
        if (Has-Prop $d 'limit') { $limit.Value = [double]$d.limit }
        if (Has-Prop $d 'speedMode') { Set-Index $ui.speedMode $d.speedMode }
        if (Has-Prop $d 'rate') { $rate.Value = [double]$d.rate }
        if (Has-Prop $d 'hotkeyMode') { Set-Index $ui.hotkeyMode $d.hotkeyMode }
        $sk = [string]$d.startKey; $ek = [string]$d.emergencyKey
        if ($ek -and $ui.emergencyKey.Items.Contains($ek) -and $ek -ne [string]$ui.keyPick.SelectedItem) { $ui.emergencyKey.SelectedItem = $ek }
        if ($sk -and $ui.keyPick.Items.Contains($sk) -and $sk -ne [string]$ui.emergencyKey.SelectedItem) { $ui.keyPick.SelectedItem = $sk }
        if ($ek -and $ui.emergencyKey.Items.Contains($ek) -and $ek -ne [string]$ui.keyPick.SelectedItem) { $ui.emergencyKey.SelectedItem = $ek }
        if (Has-Prop $d 'keyboardMode') { $ui.keyboardMode.IsChecked = [bool]$d.keyboardMode }
        if (Has-Prop $d 'keyCode') { Set-Index $ui.keyCodePick $d.keyCode }
        if (Has-Prop $d 'doubleClick') { $ui.clickTypePick.SelectedIndex = if ([bool]$d.doubleClick) { 1 } else { 0 } }
        if (Has-Prop $d 'duty') { $duty.Value = [double]$d.duty }
        if (Has-Prop $d 'randomize') { $randomize.Value = [double]$d.randomize }
        if (Has-Prop $d 'cornerStop') { $ui.cornerStop.IsChecked = [bool]$d.cornerStop }
        if (Has-Prop $d 'cornerSize') { $cornerSize.Value = [double]$d.cornerSize }
        if (Has-Prop $d 'edgeStop') { $ui.edgeStop.IsChecked = [bool]$d.edgeStop }
        if (Has-Prop $d 'edgeSize') { $edgeSize.Value = [double]$d.edgeSize }
        foreach ($n in @('alwaysTop', 'stopAlert', 'strictHotkey', 'stopAltTab', 'minimizeTray', 'rememberPosition', 'runOnStartup', 'pointsEnabled', 'stopWhenPointsDone', 'filterProcess', 'activeIcon')) {
            if (Has-Prop $d $n) { $ui[$n].IsChecked = [bool]$d.$n }
        }
        if (Has-Prop $d 'footer') { $ui.footerToggle.IsChecked = [bool]$d.footer }
        if (Has-Prop $d 'pointDefaultClicks') { $pointClicks.Value = [double]$d.pointDefaultClicks }
        if (Has-Prop $d 'pointDefaultRadius') { $pointRadius.Value = [double]$d.pointDefaultRadius }
        $script:points.Clear()
        if (Has-Prop $d 'points') { foreach ($p in @($d.points)) { if ($null -ne $p) { [void]$script:points.Add([System.Drawing.Point]::new([int]$p.x, [int]$p.y)) } } }
        if (Has-Prop $d 'processTitle') { $script:selectedProcessTitle = [string]$d.processTitle; if ($script:selectedProcessTitle) { $ui.processSelectedLabel.Text = 'Selected: ' + $script:selectedProcessTitle } }
        if (Has-Prop $d 'theme') { Set-Index $ui.themePick $d.theme }
        if (Has-Prop $d 'appearanceMode') { Set-Index $ui.appearanceModePick $d.appearanceMode }
        if ((Has-Prop $d 'globalAccent') -and (Test-Hex ([string]$d.globalAccent))) { $script:globalAccent = ([string]$d.globalAccent).ToUpper() }
        foreach ($k in @($script:pageAccents.Keys)) { $script:pageAccents[$k] = $script:globalAccent }
        if (Has-Prop $d 'pageAccents') {
            foreach ($prop in $d.pageAccents.PSObject.Properties) {
                $hex = [string]$prop.Value; if (-not (Test-Hex $hex)) { continue }
                if ($script:pageAccents.ContainsKey($prop.Name)) { $script:pageAccents[$prop.Name] = $hex.ToUpper() }
                if ($prop.Name -eq 'Behavior') { $script:pageAccents['More control'] = $hex.ToUpper() }
            }
        }
        if (Has-Prop $d 'iconTheme') { Set-Index $ui.iconTheme $d.iconTheme }
        if (Has-Prop $d 'iconColor') { Set-Index $ui.iconColor $d.iconColor }
        if ((Has-Prop $d 'activePreset') -and $d.activePreset) { $script:activePreset = [string]$d.activePreset }
        if (Has-Prop $d 'page') {
            $legacy = @{ 'Click Points' = 'Points'; 'Process List' = 'Process' }
            $pg = [string]$d.page; if ($legacy.ContainsKey($pg)) { $pg = $legacy[$pg] }
            if ($script:pageMap.Contains($pg)) { $script:currentPage = $pg }
        }
        $script:restoreCompact = [bool]$d.compact
    } catch { Write-TFLog ('Restore settings failed: ' + $_.Exception.Message) }
    finally { $script:restoring = $false }
}
$ui.resetSettings.Add_Click({
    if ((Show-TFDialog 'Reset all settings?' 'Return every TapForge option to its default? Your presets and usage data are kept.' @('Cancel', 'Reset')) -ne 1) { return }
    $script:restoring = $true
    try {
        $ui.themePick.SelectedIndex = 0; $ui.appearanceModePick.SelectedIndex = 0
        $script:globalAccent = '#7B61FF'; foreach ($k in @($script:pageAccents.Keys)) { $script:pageAccents[$k] = '#7B61FF' }
        $ui.extendedSpeed.IsChecked = $false; Update-RateLimit
        $ui.intervalUnit.SelectedIndex = 0; $script:intervalMs = 100.0; Show-IntervalInUnit
        $ui.buttonPick.SelectedIndex = 0; $ui.clickTypePick.SelectedIndex = 0; $ui.modePick.SelectedIndex = 0; $limit.Value = 100
        $ui.speedMode.SelectedIndex = 0; $rate.Value = 10; $ui.hotkeyMode.SelectedIndex = 0
        $ui.emergencyKey.SelectedItem = 'F7'; $ui.keyPick.SelectedItem = 'F6'
        $ui.keyboardMode.IsChecked = $false; $ui.keyCodePick.SelectedIndex = 0
        $duty.Value = 0; $randomize.Value = 0; $cornerSize.Value = 50; $edgeSize.Value = 40
        $ui.cornerStop.IsChecked = $false; $ui.edgeStop.IsChecked = $false
        $ui.alwaysTop.IsChecked = $false; $ui.stopAlert.IsChecked = $true; $ui.strictHotkey.IsChecked = $false; $ui.stopAltTab.IsChecked = $false
        $ui.minimizeTray.IsChecked = $false; $ui.rememberPosition.IsChecked = $true
        $pointClicks.Value = 1; $pointRadius.Value = 0; $ui.pointsEnabled.IsChecked = $false; $ui.stopWhenPointsDone.IsChecked = $false
        $script:points.Clear(); Update-PointList
        $ui.filterProcess.IsChecked = $false
        $ui.activeIcon.IsChecked = $true; $ui.iconTheme.SelectedIndex = 0; $ui.iconColor.SelectedIndex = 0; $ui.footerToggle.IsChecked = $true
        $script:activePreset = $null; Update-Footer
    } finally { $script:restoring = $false }
    $ui.runOnStartup.IsChecked = $false
    Apply-Theme; Apply-Accent -Force; Update-SpeedUi; Update-ModeUi; Update-HotkeyCaption
    Save-UserSettings
})

# ===== Startup =============================================================
Restore-UserSettings
Apply-Theme
Show-IntervalInUnit
Update-SpeedUi; Update-ModeUi; Update-HotkeyCaption; Update-PointList; Update-PresetList; Update-Footer; Update-UsageUi
$ui.footer.Visibility = if (Is-On $ui.footerToggle) { 'Visible' } else { 'Collapsed' }
$window.Topmost = Is-On $ui.alwaysTop
if (Is-On $ui.alwaysTop) { $ui.pinButton.Content = [string][char]0xE840; Set-NavActive 'pinButton' $true }
$script:prevStartKey = [string]$ui.keyPick.SelectedItem; $script:prevEmergencyKey = [string]$ui.emergencyKey.SelectedItem
$startPage = $script:currentPage; $script:currentPage = ''
Show-Page $startPage
Apply-Accent -Force

if ((Is-On $ui.rememberPosition) -and (Test-Path -LiteralPath $script:windowStateFile)) {
    try {
        $w = Get-Content -LiteralPath $script:windowStateFile -Raw | ConvertFrom-Json
        $vsLeft = [System.Windows.SystemParameters]::VirtualScreenLeft; $vsTop = [System.Windows.SystemParameters]::VirtualScreenTop
        $vsRight = $vsLeft + [System.Windows.SystemParameters]::VirtualScreenWidth; $vsBottom = $vsTop + [System.Windows.SystemParameters]::VirtualScreenHeight
        $x = [double]$w.x; $y = [double]$w.y
        if ($x -ge $vsLeft - 50 -and $y -ge $vsTop - 10 -and $x -lt $vsRight - 100 -and $y -lt $vsBottom - 60) {
            $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
            $window.Left = $x; $window.Top = $y
            if ((Has-Prop $w 'w') -and [double]$w.w -ge 800) { $window.Width = [double]$w.w }
            if ((Has-Prop $w 'h') -and [double]$w.h -ge 580) { $window.Height = [double]$w.h }
        }
    } catch { }
}

$window.Add_Closing({
    param($s, $e)
    if ((Is-On $ui.minimizeTray) -and -not $script:exitRequested) {
        $e.Cancel = $true; $window.Hide(); $script:trayIcon.Visible = $true
        return
    }
    if (Is-On $ui.rememberPosition) {
        try {
            $size = if ($script:compactMode) { $script:normalSize } else { @($window.RestoreBounds.Width, $window.RestoreBounds.Height) }
            $left = if ($window.WindowState -eq [System.Windows.WindowState]::Normal) { $window.Left } else { $window.RestoreBounds.Left }
            $top = if ($window.WindowState -eq [System.Windows.WindowState]::Normal) { $window.Top } else { $window.RestoreBounds.Top }
            @{ x = $left; y = $top; w = $size[0]; h = $size[1] } | ConvertTo-Json | Set-Content -LiteralPath $script:windowStateFile -Encoding UTF8
        } catch { }
    }
    Save-UserSettings
    if ($script:running) { Stop-Clicking }
    [ClickNative]::Stop()
    $script:hotkeyTimer.Stop(); $script:monitorTimer.Stop(); $script:updateTimer.Stop()
    $script:trayIcon.Visible = $false; $script:trayIcon.Dispose()
})
$window.Add_ContentRendered({
    if ($script:restoreCompact) { $script:restoreCompact = $false; Set-Compact $true }
    $script:startupCheck = [System.Windows.Threading.DispatcherTimer]::new()
    $script:startupCheck.Interval = [TimeSpan]::FromSeconds(2)
    $script:startupCheck.Add_Tick({ $script:startupCheck.Stop(); Start-UpdateCheck $true })
    $script:startupCheck.Start()
})

$script:hotkeyTimer.Start()
$global:TapForgeReady = $true
# Run as a normal (non-modal) app window. ShowDialog would end as soon as the
# window is hidden (tray, point picker) and leave a frozen window behind.
$script:app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$window.Add_Closed({ $script:app.Shutdown() })
[void]$script:app.Run($window)

} catch {
    $line = if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 }
    $msg = "TapForge could not start.`r`n`r`n$($_.Exception.Message)`r`n`r`n(line $line)"
    Write-TFLog ($msg + "`r`n" + $_.ScriptStackTrace)
    [System.Windows.Forms.MessageBox]::Show($msg, 'TapForge', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

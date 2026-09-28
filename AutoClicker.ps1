Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;
using System.Diagnostics;
using System.Threading;
using System.Runtime.InteropServices;
public class TapForgeWindow : System.Windows.Forms.Form {
    const int WM_NCHITTEST=0x84;
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd,int msg,IntPtr wParam,IntPtr lParam);
    public static void BeginDrag(IntPtr hwnd){ReleaseCapture();SendMessage(hwnd,0xA1,new IntPtr(2),IntPtr.Zero);}
    protected override CreateParams CreateParams { get { CreateParams cp=base.CreateParams;cp.Style|=0x00040000;return cp; } }
    protected override void WndProc(ref Message m){if(m.Msg==WM_NCHITTEST&&WindowState==FormWindowState.Normal){Point p=PointToClient(Cursor.Position);int b=7;bool l=p.X<b,r=p.X>=ClientSize.Width-b,t=p.Y<b,bt=p.Y>=ClientSize.Height-b;if(t&&l)m.Result=(IntPtr)13;else if(t&&r)m.Result=(IntPtr)14;else if(bt&&l)m.Result=(IntPtr)16;else if(bt&&r)m.Result=(IntPtr)17;else if(l)m.Result=(IntPtr)10;else if(r)m.Result=(IntPtr)11;else if(t)m.Result=(IntPtr)12;else if(bt)m.Result=(IntPtr)15;else base.WndProc(ref m);return;}base.WndProc(ref m);}
}
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
    public static void Configure(int random,int hold,int clicks,int seconds,bool corner,int cornerSize,bool edge,int edgeSize,bool keyMode,int key,bool dbl,int[] clickPoints,int radius,int pointClicks) {
        randomPct=random;holdPct=hold;maxClicks=clicks;maxSeconds=seconds;useCorner=corner;cornerPx=cornerSize;useEdge=edge;edgePx=edgeSize;
        keyboard=keyMode;keyCode=key;doubleClick=dbl;points=clickPoints??new int[0];pointRadius=Math.Max(0,radius);clicksPerPoint=Math.Max(1,pointClicks);
    }
    public static long Count { get { return Interlocked.Read(ref sent); } }
    public static bool Active { get { return active; } }
    public static int[] Cursor { get { POINT p; GetCursorPos(out p); return new int[]{p.X,p.Y}; } }
    public static void Start(uint downFlag, uint upFlag, int intervalMs) {
        Stop(); periodSet=(timeBeginPeriod(1)==0); down=downFlag; up=upFlag; Interlocked.Exchange(ref sent,0); active=true;
        worker=new Thread(() => {
            long frequency=Stopwatch.Frequency;
            long period=Math.Max(1L, (long)(frequency * (intervalMs / 1000.0)));
            long next=Stopwatch.GetTimestamp(); long started=next; int pointIndex=0,clicksAtPoint=0;
            while(active) {
                if(maxSeconds>0 && (Stopwatch.GetTimestamp()-started)/((double)frequency)>=maxSeconds) { active=false; break; }
                if(TargetProcessId>0) { uint foregroundPid; GetWindowThreadProcessId(GetForegroundWindow(),out foregroundPid); if(foregroundPid!=(uint)TargetProcessId) { Thread.Sleep(1); continue; } }
                POINT pos; GetCursorPos(out pos);
                System.Drawing.Rectangle bounds=System.Windows.Forms.SystemInformation.VirtualScreen;
                if(useCorner && ((pos.X<bounds.Left+cornerPx&&pos.Y<bounds.Top+cornerPx)||(pos.X<bounds.Left+cornerPx&&pos.Y>=bounds.Bottom-cornerPx)||(pos.X>=bounds.Right-cornerPx&&pos.Y<bounds.Top+cornerPx)||(pos.X>=bounds.Right-cornerPx&&pos.Y>=bounds.Bottom-cornerPx))) { active=false; break; }
                if(useEdge && (pos.X<bounds.Left+edgePx||pos.Y<bounds.Top+edgePx||pos.X>=bounds.Right-edgePx||pos.Y>=bounds.Bottom-edgePx)) { active=false; break; }
                if(!active) break;
                if(points.Length>=2 && clicksAtPoint==0) { int px=points[pointIndex],py=points[pointIndex+1];if(pointRadius>0){double a=rng.NextDouble()*Math.PI*2,r=Math.Sqrt(rng.NextDouble())*pointRadius;px+=(int)Math.Round(Math.Cos(a)*r);py+=(int)Math.Round(Math.Sin(a)*r);}SetCursorPos(px,py); }
                int repeats=doubleClick?2:1;
                for(int n=0;n<repeats && active;n++) {
                    if(keyboard) { keybd_event((byte)keyCode,0,0,UIntPtr.Zero); if(holdPct>0) HoldFor(Math.Max(1,intervalMs*holdPct/100)); keybd_event((byte)keyCode,0,2,UIntPtr.Zero); }
                    else { mouse_event(down,0,0,0,UIntPtr.Zero); if(holdPct>0) HoldFor(Math.Max(1,intervalMs*holdPct/100)); mouse_event(up,0,0,0,UIntPtr.Zero); }
                    Interlocked.Increment(ref sent);
                    if(points.Length>=2 && ++clicksAtPoint>=clicksPerPoint){clicksAtPoint=0;pointIndex=(pointIndex+2)%points.Length;}
                    if(maxClicks>0 && Count>=maxClicks) { active=false; break; }
                }
                int variation=randomPct==0?0:rng.Next(-randomPct,randomPct+1);
                long wait=Math.Max(1,period*(100+variation)/100); next += wait;
                while(active) {
                    long remaining=next-Stopwatch.GetTimestamp();
                    if(remaining<=0) break;
                    if(remaining > frequency/500) Thread.Sleep(1);
                    else Thread.Yield();
                }
            }
        }); worker.IsBackground=true; worker.Priority=ThreadPriority.Highest; worker.Start();
    }
    public static void Stop() { active=false; if(worker!=null && worker.IsAlive) worker.Join(100); worker=null; if(periodSet){timeEndPeriod(1);periodSet=false;} }
}
public static class LogoColorizer {
    static Color HsvToColor(double h,double s,double v,int alpha){double c=v*s,x=c*(1-Math.Abs((h/60.0%2)-1)),m=v-c,r=0,g=0,b=0;if(h<60){r=c;g=x;}else if(h<120){r=x;g=c;}else if(h<180){g=c;b=x;}else if(h<240){g=x;b=c;}else if(h<300){r=x;b=c;}else{r=c;b=x;}return Color.FromArgb(alpha,(int)Math.Round((r+m)*255),(int)Math.Round((g+m)*255),(int)Math.Round((b+m)*255));}
    public static Bitmap Tint(Bitmap source,Color accent){Bitmap normalized=new Bitmap(source.Width,source.Height,PixelFormat.Format32bppArgb);using(Graphics g=Graphics.FromImage(normalized)){g.DrawImage(source,0,0,source.Width,source.Height);}Bitmap result=new Bitmap(source.Width,source.Height,PixelFormat.Format32bppArgb);Rectangle area=new Rectangle(0,0,source.Width,source.Height);BitmapData input=normalized.LockBits(area,ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);BitmapData output=result.LockBits(area,ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);byte[] row=new byte[source.Width*4];for(int y=0;y<source.Height;y++){Marshal.Copy(IntPtr.Add(input.Scan0,y*input.Stride),row,0,row.Length);for(int x=0;x<source.Width;x++){int i=x*4,b=row[i],g=row[i+1],r=row[i+2],a=row[i+3];int max=Math.Max(r,Math.Max(g,b)),min=Math.Min(r,Math.Min(g,b)),delta=max-min;double h=0,s=max==0?0:delta/(double)max,v=max/255.0;if(delta>0){if(max==r)h=60.0*(((g-b)/(double)delta)%6);else if(max==g)h=60.0*(((b-r)/(double)delta)+2);else h=60.0*(((r-g)/(double)delta)+4);if(h<0)h+=360;}if(a>0&&h>=245&&h<=325&&s>=0.24&&v>=0.26){row[i]=(byte)Math.Round(accent.B*v);row[i+1]=(byte)Math.Round(accent.G*v);row[i+2]=(byte)Math.Round(accent.R*v);}}Marshal.Copy(row,0,IntPtr.Add(output.Scan0,y*output.Stride),row.Length);}normalized.UnlockBits(input);result.UnlockBits(output);normalized.Dispose();return result;}
    public static Icon MakeIcon(Bitmap bitmap){using(Bitmap small=new Bitmap(64,64,PixelFormat.Format32bppArgb)){using(Graphics g=Graphics.FromImage(small)){g.Clear(Color.Transparent);g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.SmoothingMode=SmoothingMode.HighQuality;g.PixelOffsetMode=PixelOffsetMode.HighQuality;g.DrawImage(bitmap,0,0,64,64);}IntPtr handle=small.GetHicon();try{using(Icon icon=Icon.FromHandle(handle)){return (Icon)icon.Clone();}}finally{ClickNative.DestroyIcon(handle);}}}
}
public class SmoothCanvas : System.Windows.Forms.Panel { public SmoothCanvas(){ DoubleBuffered=true; ResizeRedraw=true; } }
public class TapForgeSwitch : System.Windows.Forms.CheckBox {
    public static Color AccentColor=Color.FromArgb(123,97,255);
    public TapForgeSwitch(){AutoSize=false;Text=String.Empty;Size=new Size(46,26);BackColor=Color.Transparent;Cursor=Cursors.Hand;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.SupportsTransparentBackColor,true);}
    protected override void OnCheckedChanged(EventArgs e){base.OnCheckedChanged(e);Invalidate();}
    protected override void OnPaint(PaintEventArgs e){base.OnPaintBackground(e);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;int h=20,w=42,x=2,y=(Height-h)/2;Color track=Checked?AccentColor:Color.FromArgb(76,82,96);using(GraphicsPath p=new GraphicsPath()){p.AddArc(x,y,h,h,90,180);p.AddArc(x+w-h,y,w-h,h,270,180);p.CloseFigure();using(Brush b=new SolidBrush(track))e.Graphics.FillPath(b,p);}int d=14;int thumbX=Checked?x+w-h+3:x+3;using(Brush b=new SolidBrush(Color.White))e.Graphics.FillEllipse(b,thumbX,y+3,d,d);if(Focused){using(Pen p=new Pen(AccentColor,1))e.Graphics.DrawRectangle(p,0,0,Width-1,Height-1);}}
}
public class TapForgeCard : System.Windows.Forms.Panel {
    public static Color BorderColor=Color.FromArgb(45,52,69);
    const int Radius=14;
    static GraphicsPath Shape(Rectangle r){int d=Radius*2;GraphicsPath p=new GraphicsPath();if(r.Width<d||r.Height<d){p.AddRectangle(r);return p;}p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;}
    public TapForgeCard(){DoubleBuffered=true;ResizeRedraw=true;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.SupportsTransparentBackColor,true);}
    protected override void OnResize(EventArgs e){base.OnResize(e);using(GraphicsPath p=Shape(new Rectangle(0,0,Width,Height)))Region=new Region(p);}
    protected override void OnPaintBackground(PaintEventArgs e){e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;using(GraphicsPath p=Shape(new Rectangle(0,0,Width-1,Height-1)))using(Brush b=new SolidBrush(BackColor))e.Graphics.FillPath(b,p);}
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;using(GraphicsPath p=Shape(new Rectangle(0,0,Width-1,Height-1)))using(Pen pen=new Pen(BorderColor,1))e.Graphics.DrawPath(pen,p);}
}
public class TapForgeLabel : System.Windows.Forms.Label {
    public TapForgeLabel(){SetStyle(ControlStyles.OptimizedDoubleBuffer|ControlStyles.AllPaintingInWmPaint|ControlStyles.SupportsTransparentBackColor,true);BackColor=Color.Transparent;}
    protected override void OnPaintBackground(PaintEventArgs e){base.OnPaintBackground(e);}
}
public class HuePickerControl : System.Windows.Forms.Panel {
    public double Hue=252, Saturation=0.62, Brightness=1.0;
    Bitmap hueMap;
    bool dragging, hueDrag;
    public HuePickerControl(){ DoubleBuffered=true; ResizeRedraw=true; BackColor=System.Drawing.Color.FromArgb(24,29,43); hueMap=new Bitmap(360,24); using(Graphics g=Graphics.FromImage(hueMap)){ for(int x=0;x<360;x++){ Color c=Hsv(x,1,1); using(Brush b=new SolidBrush(c)) g.FillRectangle(b,x,0,1,24); } } }
    static Color Hsv(double h,double s,double v){ double c=v*s, x=c*(1-Math.Abs((h/60.0%2)-1)), m=v-c, r=0,g=0,b=0; if(h<60){r=c;g=x;} else if(h<120){r=x;g=c;} else if(h<180){g=c;b=x;} else if(h<240){g=x;b=c;} else if(h<300){r=x;b=c;} else {r=c;b=x;} return Color.FromArgb(255,(int)((r+m)*255),(int)((g+m)*255),(int)((b+m)*255)); }
    public Color SelectedColor { get { return Hsv(Hue,Saturation,Brightness); } }
    void UpdateFromPoint(int px,int py){ if(hueDrag){Hue=Math.Max(0,Math.Min(359,px/(double)Math.Max(1,Width)*360));} else { Saturation=Math.Max(0,Math.Min(1,px/(double)Math.Max(1,Width-1))); Brightness=1-Math.Max(0,Math.Min(1,py/200.0)); } Invalidate(); }
    protected override void OnMouseDown(System.Windows.Forms.MouseEventArgs e){ base.OnMouseDown(e); if(e.Button==System.Windows.Forms.MouseButtons.Left){ dragging=true; Capture=true; hueDrag=e.Y>=210; UpdateFromPoint(e.X,e.Y); } }
    protected override void OnMouseMove(System.Windows.Forms.MouseEventArgs e){ base.OnMouseMove(e); if(dragging) UpdateFromPoint(e.X,e.Y); }
    protected override void OnMouseUp(System.Windows.Forms.MouseEventArgs e){ base.OnMouseUp(e); if(e.Button==System.Windows.Forms.MouseButtons.Left){ dragging=false; Capture=false; } }
    protected override void OnPaint(System.Windows.Forms.PaintEventArgs e){ base.OnPaint(e); Rectangle square=new Rectangle(0,0,Width,200); using(Brush whiteHue=new LinearGradientBrush(square,Color.White,Hsv(Hue,1,1),0f)) e.Graphics.FillRectangle(whiteHue,square); using(Brush shade=new LinearGradientBrush(square,Color.FromArgb(0,0,0,0),Color.FromArgb(255,0,0,0),LinearGradientMode.Vertical)) e.Graphics.FillRectangle(shade,square); if(hueMap!=null)e.Graphics.DrawImage(hueMap,new Rectangle(0,214,Width,24)); int sx=(int)(Saturation*(Width-1)), sy=(int)((1-Brightness)*200); using(Pen p=new Pen(Color.Black,3))e.Graphics.DrawEllipse(p,sx-7,sy-7,14,14); using(Pen p=new Pen(Color.White,2))e.Graphics.DrawEllipse(p,sx-7,sy-7,14,14); int hx=(int)(Hue/360.0*Width); e.Graphics.DrawRectangle(Pens.Black,hx-3,213,6,25); e.Graphics.DrawRectangle(Pens.White,hx-2,214,4,23); }
    protected override void Dispose(bool disposing){ if(disposing&&hueMap!=null){hueMap.Dispose();hueMap=null;} base.Dispose(disposing); }
}
public class AccentSlider : System.Windows.Forms.Panel {
    public int Minimum=0, Maximum=100;
    int currentValue=50;
    bool dragging;
    public static Color AccentColor=Color.FromArgb(123,97,255);
    public event EventHandler ValueChanged;
    public int Value { get { return currentValue; } set { int v=Math.Max(Minimum,Math.Min(Maximum,value)); if(v!=currentValue){currentValue=v;Invalidate();if(ValueChanged!=null)ValueChanged(this,EventArgs.Empty);} } }
    public AccentSlider(){DoubleBuffered=true;ResizeRedraw=true;Height=36;BackColor=Color.FromArgb(24,29,43);Cursor=System.Windows.Forms.Cursors.Hand;}
    void SetFromX(int x){int span=Math.Max(1,Width-20);Value=Minimum+(int)Math.Round(Math.Max(0,Math.Min(1,(x-10)/(double)span))*(Maximum-Minimum));}
    protected override void OnMouseDown(System.Windows.Forms.MouseEventArgs e){base.OnMouseDown(e);if(e.Button==System.Windows.Forms.MouseButtons.Left){dragging=true;Capture=true;SetFromX(e.X);}}
    protected override void OnMouseMove(System.Windows.Forms.MouseEventArgs e){base.OnMouseMove(e);if(dragging)SetFromX(e.X);}
    protected override void OnMouseUp(System.Windows.Forms.MouseEventArgs e){base.OnMouseUp(e);if(e.Button==System.Windows.Forms.MouseButtons.Left){dragging=false;Capture=false;}}
    protected override void OnMouseWheel(System.Windows.Forms.MouseEventArgs e){base.OnMouseWheel(e);Value+=Math.Sign(e.Delta);}
    protected override void OnPaint(System.Windows.Forms.PaintEventArgs e){base.OnPaint(e);int left=10,right=Width-10,y=Height/2;int x=left+(int)((right-left)*(Value-Minimum)/(double)Math.Max(1,Maximum-Minimum));using(Pen track=new Pen(Color.FromArgb(74,79,91),4))e.Graphics.DrawLine(track,left,y,right,y);using(Pen fill=new Pen(AccentColor,4))e.Graphics.DrawLine(fill,left,y,x,y);using(Brush thumb=new SolidBrush(AccentColor))e.Graphics.FillEllipse(thumb,x-7,y-7,14,14);using(Pen edge=new Pen(Color.FromArgb(230,230,238),1))e.Graphics.DrawEllipse(edge,x-7,y-7,14,14);}
}
public class AccentArrow : System.Windows.Forms.Panel {
    public static Color AccentColor=Color.FromArgb(123,97,255);
    public AccentArrow(){DoubleBuffered=true;Cursor=Cursors.Hand;}
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);using(Brush b=new SolidBrush(AccentColor))e.Graphics.FillRectangle(b,ClientRectangle);int cx=Width/2,cy=Height/2;using(Pen p=new Pen(Color.White,2)){e.Graphics.DrawLine(p,cx-4,cy-2,cx,cy+2);e.Graphics.DrawLine(p,cx,cy+2,cx+4,cy-2);}}
}
public class AccentSpinner : System.Windows.Forms.Panel {
    public static Color AccentColor=Color.FromArgb(123,97,255);
    public NumericUpDown Target;
    public AccentSpinner(NumericUpDown target){Target=target;DoubleBuffered=true;Cursor=Cursors.Hand;}
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);using(Brush b=new SolidBrush(AccentColor))e.Graphics.FillRectangle(b,ClientRectangle);int cx=Width/2, top=Height/4, bottom=Height*3/4;using(Brush b=new SolidBrush(Color.White)){Point[] up={new Point(cx-4,top+2),new Point(cx+4,top+2),new Point(cx,top-2)};Point[] down={new Point(cx-4,bottom-2),new Point(cx+4,bottom-2),new Point(cx,bottom+2)};e.Graphics.FillPolygon(b,up);e.Graphics.FillPolygon(b,down);}}
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);if(e.Button==MouseButtons.Left&&Target!=null){if(e.Y<Height/2)Target.UpButton();else Target.DownButton();Target.Focus();}}
}
public class AccentFrameLine : System.Windows.Forms.Panel {
    public static Color OutlineColor=Color.FromArgb(90,90,105);
    public AccentFrameLine(){Enabled=false;}
    protected override void OnPaint(PaintEventArgs e){using(Brush b=new SolidBrush(OutlineColor))e.Graphics.FillRectangle(b,ClientRectangle);}
}
'@ -ReferencedAssemblies @('System.Windows.Forms.dll','System.Drawing.dll')

[System.Windows.Forms.Application]::EnableVisualStyles()
$script:running = $false
$script:clickTimer = $null
$script:clickCount = 0L
$script:stopwatch = [System.Diagnostics.Stopwatch]::new()
$script:lastF6 = $false
$script:lastF7 = $false
$script:colorBg = [System.Drawing.Color]::FromArgb(15,18,28)
$script:colorPanel = [System.Drawing.Color]::FromArgb(24,29,43)
$script:colorAccent = [System.Drawing.Color]::FromArgb(123,97,255)
$script:colorMuted = [System.Drawing.Color]::FromArgb(151,161,181)

function New-Label($text, $x, $y, $w, $h, $size = 10, $color = $script:colorMuted, $bold = $false) {
    $l = [TapForgeLabel]::new()
    $l.Text = $text; $l.Location = [System.Drawing.Point]::new($x,$y); $l.Size = [System.Drawing.Size]::new($w,$h)
    $l.ForeColor = $color; if($color.ToArgb() -eq $script:colorMuted.ToArgb()){$l.Tag='muted'}; $l.Font = [System.Drawing.Font]::new('Segoe UI',$size, $(if($bold){[System.Drawing.FontStyle]::Bold}else{[System.Drawing.FontStyle]::Regular}))
    $l
}
function New-Card($x,$y,$w,$h) {
    $p = [TapForgeCard]::new(); $p.Location = [System.Drawing.Point]::new($x,$y); $p.Size = [System.Drawing.Size]::new($w,$h)
    $p.BackColor = $script:colorPanel; $p.Tag='surface'; $p
}
function New-Button($text,$x,$y,$w,$h,$back,$fore) {
    $b = [System.Windows.Forms.Button]::new(); $b.Text=$text; $b.Location=[System.Drawing.Point]::new($x,$y); $b.Size=[System.Drawing.Size]::new($w,$h)
    $b.FlatStyle='Flat'; $b.FlatAppearance.BorderSize=0; $b.BackColor=$back; $b.ForeColor=$fore; if($back.ToArgb() -eq $script:colorAccent.ToArgb()){$b.Tag='primary'}; $b.Font=[System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold); $b.Cursor='Hand'; $b
}
function Get-HsvColor([double]$h,[double]$s,[double]$v) {
    $c=$v*$s; $x=$c*(1-[Math]::Abs((($h/60)%2)-1)); $m=$v-$c
    if($h -lt 60){$r=$c;$g=$x;$b=0}elseif($h -lt 120){$r=$x;$g=$c;$b=0}elseif($h -lt 180){$r=0;$g=$c;$b=$x}elseif($h -lt 240){$r=0;$g=$x;$b=$c}elseif($h -lt 300){$r=$x;$g=0;$b=$c}else{$r=$c;$g=0;$b=$x}
    [System.Drawing.Color]::FromArgb(255,[int](($r+$m)*255),[int](($g+$m)*255),[int](($b+$m)*255))
}
function Show-HuePicker([System.Drawing.Color]$initialColor) {
    $rr=$initialColor.R/255.0;$gg=$initialColor.G/255.0;$bb=$initialColor.B/255.0;$mx=[Math]::Max($rr,[Math]::Max($gg,$bb));$mn=[Math]::Min($rr,[Math]::Min($gg,$bb));$delta=$mx-$mn;$script:hue=0.0
    if($delta -gt 0){if($mx -eq $rr){$script:hue=60*((($gg-$bb)/$delta)%6)}elseif($mx -eq $gg){$script:hue=60*((($bb-$rr)/$delta)+2)}else{$script:hue=60*((($rr-$gg)/$delta)+4)}};if($script:hue -lt 0){$script:hue+=360};$script:saturation=if($mx -eq 0){0.0}else{$delta/$mx};$script:value=$mx;$script:hueResult=$null
    $script:hueAccepted=$false;$script:hueForm=[System.Windows.Forms.Form]::new();$script:hueForm.Text='Choose accent color';$script:hueForm.Size=[System.Drawing.Size]::new(390,430);$script:hueForm.StartPosition='CenterParent';$script:hueForm.FormBorderStyle='FixedDialog';$script:hueForm.MaximizeBox=$false;$script:hueForm.MinimizeBox=$false;$script:hueForm.BackColor=$script:colorBg;$script:hueForm.ForeColor=[System.Drawing.Color]::White
    $script:hueForm.Add_HandleCreated({Enable-DarkChrome $script:hueForm})
    $script:picker=[HuePickerControl]::new();$script:picker.Location=[System.Drawing.Point]::new(24,24);$script:picker.Size=[System.Drawing.Size]::new(320,244);$script:picker.Hue=$script:hue;$script:picker.Saturation=$script:saturation;$script:picker.Brightness=$script:value;$script:hueForm.Controls.Add($script:picker)
    $script:colorPreview=[System.Windows.Forms.Panel]::new();$script:colorPreview.Location=[System.Drawing.Point]::new(24,284);$script:colorPreview.Size=[System.Drawing.Size]::new(54,38);$script:colorPreview.BackColor=$initialColor;$script:hueForm.Controls.Add($script:colorPreview)
    $script:hexLabel=New-Label ('#'+$initialColor.R.ToString('X2')+$initialColor.G.ToString('X2')+$initialColor.B.ToString('X2')) 92 289 150 28 12 ([System.Drawing.Color]::White) $true;$script:hueForm.Controls.Add($script:hexLabel)
    $script:pickerTimer=[System.Windows.Forms.Timer]::new();$script:pickerTimer.Interval=35;$script:pickerTimer.Add_Tick({$c=$script:picker.SelectedColor;$script:colorPreview.BackColor=$c;$script:hexLabel.Text='#'+$c.R.ToString('X2')+$c.G.ToString('X2')+$c.B.ToString('X2')});$script:pickerTimer.Start()
    $apply=New-Button 'Apply color' 212 344 132 34 $script:colorAccent ([System.Drawing.Color]::White);$script:hueForm.Controls.Add($apply);$cancel=New-Button 'Cancel' 68 344 124 34 ([System.Drawing.Color]::FromArgb(48,55,73)) ([System.Drawing.Color]::White);$script:hueForm.Controls.Add($cancel)
    $apply.Add_Click({$script:hueResult=$script:picker.SelectedColor;$script:hueAccepted=$true;$script:hueForm.Close()});$cancel.Add_Click({$script:hueForm.Close()})
    [void]$script:hueForm.ShowDialog($form);$script:pickerTimer.Stop();$script:pickerTimer.Dispose();$script:picker.Dispose();if($script:hueAccepted){$script:hueResult}else{$null}
}

$form = [TapForgeWindow]::new()
$form.Text='TapForge'; $form.Size=[System.Drawing.Size]::new(1080,800); $form.MinimumSize=[System.Drawing.Size]::new(1080,780); $form.AutoScroll=$false
$form.StartPosition='CenterScreen'; $form.BackColor=$script:colorBg; $form.ForeColor=[System.Drawing.Color]::White; $form.Font=[System.Drawing.Font]::new('Segoe UI',10)
$form.FormBorderStyle='None'; $form.MaximizeBox=$true
$script:logoPath=Join-Path $PSScriptRoot 'TapForge.ico';$script:logoIcon=[System.Drawing.Icon]::new($script:logoPath);$script:logoSourcePath=Join-Path $PSScriptRoot 'TapForgeLogo.png';$script:logoSourceImage=[System.Drawing.Bitmap]::FromFile($script:logoSourcePath);$script:brandImage=$script:logoSourceImage.Clone()
$brandMark=[System.Windows.Forms.PictureBox]::new();$brandMark.Size=[System.Drawing.Size]::new(34,34);$brandMark.SizeMode='Zoom';$brandMark.BackColor=[System.Drawing.Color]::Transparent;$brandMark.Image=$script:brandImage;$brandMark.AccessibleName='TapForge logo';$script:brandMark=$brandMark
$brandTitle=New-Label 'TapForge' 0 0 118 32 17 ([System.Drawing.Color]::White) $true;$brandTitle.Font=[System.Drawing.Font]::new('Bahnschrift',17,[System.Drawing.FontStyle]::Bold)
$statusPill = New-Label '●  READY' 0 0 78 24 9 ([System.Drawing.Color]::FromArgb(108,220,170)) $true

$settings = New-Card 26 96 442 396; $form.Controls.Add($settings)
$form.Controls.Add((New-Label 'Click settings' 48 114 250 30 14 ([System.Drawing.Color]::White) $true))
$form.Controls.Add((New-Label 'Set your click pattern and activation behavior.' 48 144 390 24 9 $script:colorMuted))

$settings.Controls.Add((New-Label 'BUTTON' 22 62 130 22 8 $script:colorMuted $true))
$buttonPick=[System.Windows.Forms.ComboBox]::new(); $buttonPick.Location=[System.Drawing.Point]::new(22,87); $buttonPick.Size=[System.Drawing.Size]::new(185,34); $buttonPick.DropDownStyle='DropDownList'; $buttonPick.BackColor=[System.Drawing.Color]::FromArgb(34,40,57); $buttonPick.ForeColor=[System.Drawing.Color]::White; $buttonPick.FlatStyle='Flat'; [void]$buttonPick.Items.AddRange(@('Left click','Right click','Middle click')); $buttonPick.SelectedIndex=0; $settings.Controls.Add($buttonPick)
$settings.Controls.Add((New-Label 'CLICK INTERVAL' 232 62 240 22 8 $script:colorMuted $true))
$interval=[System.Windows.Forms.NumericUpDown]::new(); $interval.Location=[System.Drawing.Point]::new(232,87); $interval.Size=[System.Drawing.Size]::new(112,34); $interval.Minimum=1; $interval.Maximum=3600000; $interval.Value=100; $interval.Increment=10; $interval.BackColor=[System.Drawing.Color]::FromArgb(34,40,57); $interval.ForeColor=[System.Drawing.Color]::White; $interval.BorderStyle='FixedSingle'; $settings.Controls.Add($interval)
$intervalUnit=[System.Windows.Forms.ComboBox]::new();$intervalUnit.Location=[System.Drawing.Point]::new(352,87);$intervalUnit.Size=[System.Drawing.Size]::new(120,34);$intervalUnit.DropDownStyle='DropDownList';$intervalUnit.BackColor=[System.Drawing.Color]::FromArgb(34,40,57);$intervalUnit.ForeColor=[System.Drawing.Color]::White;$intervalUnit.FlatStyle='Flat';[void]$intervalUnit.Items.AddRange(@('Milliseconds','Seconds','Minutes'));$intervalUnit.SelectedIndex=0;$settings.Controls.Add($intervalUnit)
$settings.Controls.Add((New-Label 'Time between clicks · max 60 minutes' 232 122 240 20 8 $script:colorMuted))
function Get-IntervalMilliseconds { $factor=([decimal[]]@(1,1000,60000))[$intervalUnit.SelectedIndex];[long][Math]::Max(1,[Math]::Round([double]$interval.Value*[double]$factor)) }
function Set-IntervalMilliseconds([long]$milliseconds) { $index=$intervalUnit.SelectedIndex;$factor=([decimal[]]@(1,1000,60000))[$index];$minimum=([decimal[]]@(1,0.001,0.00002))[$index];$maximum=([decimal[]]@(3600000,3600,60))[$index];$places=([int[]]@(0,3,5))[$index];$increment=([decimal[]]@(10,0.01,0.001))[$index];$interval.Value=$interval.Minimum;$interval.DecimalPlaces=$places;$interval.Minimum=$minimum;$interval.Maximum=$maximum;$interval.Increment=$increment;$shown=[decimal]$milliseconds/$factor;$interval.Value=[Math]::Min($maximum,[Math]::Max($minimum,$shown)) }
$script:intervalMilliseconds=100;$script:intervalUnitIndex=0
$interval.Add_ValueChanged({$factor=([decimal[]]@(1,1000,60000))[$script:intervalUnitIndex];$script:intervalMilliseconds=[long][Math]::Max(1,[Math]::Round([double]$interval.Value*[double]$factor))})
$intervalUnit.Add_SelectedIndexChanged({if($intervalUnit.SelectedIndex -ge 0){$ms=$script:intervalMilliseconds;$script:intervalUnitIndex=$intervalUnit.SelectedIndex;Set-IntervalMilliseconds $ms;$interval.Enabled=($speedMode.SelectedIndex -eq 0)}})

$settings.Controls.Add((New-Label 'STOP AFTER' 22 159 160 22 8 $script:colorMuted $true))
$modePick=[System.Windows.Forms.ComboBox]::new(); $modePick.Location=[System.Drawing.Point]::new(22,184); $modePick.Size=[System.Drawing.Size]::new(185,34); $modePick.DropDownStyle='DropDownList'; $modePick.BackColor=[System.Drawing.Color]::FromArgb(34,40,57); $modePick.ForeColor=[System.Drawing.Color]::White; $modePick.FlatStyle='Flat'; [void]$modePick.Items.AddRange(@('Until stopped','Number of clicks','Time limit')); $modePick.SelectedIndex=0; $settings.Controls.Add($modePick)
$limit=[System.Windows.Forms.NumericUpDown]::new(); $limit.Location=[System.Drawing.Point]::new(232,184); $limit.Size=[System.Drawing.Size]::new(160,34); $limit.Minimum=1; $limit.Maximum=10000000; $limit.Value=100; $limit.BackColor=[System.Drawing.Color]::FromArgb(34,40,57); $limit.ForeColor=[System.Drawing.Color]::White; $settings.Controls.Add($limit)
$limitHint=New-Label 'clicks' 232 219 180 20 8 $script:colorMuted; $settings.Controls.Add($limitHint)
$modePick.Add_SelectedIndexChanged({ $limitHint.Text=@('No limit','clicks','seconds')[$modePick.SelectedIndex]; $limit.Enabled=($modePick.SelectedIndex -ne 0) })
$limit.Enabled=$false

$settings.Controls.Add((New-Label 'START / STOP HOTKEY' 22 257 180 22 8 $script:colorMuted $true))
$keyPick=[System.Windows.Forms.ComboBox]::new(); $keyPick.Location=[System.Drawing.Point]::new(22,282); $keyPick.Size=[System.Drawing.Size]::new(185,34); $keyPick.DropDownStyle='DropDownList'; $keyPick.BackColor=[System.Drawing.Color]::FromArgb(34,40,57); $keyPick.ForeColor=[System.Drawing.Color]::White; $keyPick.FlatStyle='Flat'; [void]$keyPick.Items.AddRange(@('F6','F8','F9','F10','F11','F12')); $keyPick.SelectedIndex=0; $settings.Controls.Add($keyPick)
$settings.Controls.Add((New-Label 'Global hotkey · works while minimized' 22 319 390 21 8 $script:colorMuted))
$settings.Controls.Add((New-Label 'F7 always stops clicking immediately.' 22 350 390 21 8 ([System.Drawing.Color]::FromArgb(190,170,255))))
@($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -eq 'Click settings' }) | ForEach-Object { $form.Controls.Remove($_); $_.Location=[System.Drawing.Point]::new(22,14); $_.Size=[System.Drawing.Size]::new(250,28); $settings.Controls.Add($_) }
@($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -eq 'Set your click pattern and activation behavior.' }) | ForEach-Object { $form.Controls.Remove($_); $_.Location=[System.Drawing.Point]::new(22,39); $_.Size=[System.Drawing.Size]::new(390,20); $settings.Controls.Add($_) }
@($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -in @('TapForge  ·  Runs locally on your PC','F6 START/STOP     F7 EMERGENCY STOP') }) | ForEach-Object { $form.Controls.Remove($_) }

$monitor=New-Card 486 96 246 396; $form.Controls.Add($monitor)
$monitor.Controls.Add((New-Label 'Live monitor' 20 18 200 28 14 ([System.Drawing.Color]::White) $true))
$monitor.Controls.Add((New-Label 'CLICKS SENT' 20 72 150 20 8 $script:colorMuted $true))
$countLabel=New-Label '0' 20 96 205 70 34 ([System.Drawing.Color]::White) $true; $monitor.Controls.Add($countLabel)
$monitor.Controls.Add((New-Label 'ELAPSED' 20 190 150 20 8 $script:colorMuted $true))
$elapsedLabel=New-Label '00:00:00' 20 216 205 40 20 ([System.Drawing.Color]::White) $true; $monitor.Controls.Add($elapsedLabel)
$monitor.Controls.Add((New-Label 'CURRENT MODE' 20 285 150 20 8 $script:colorMuted $true))
$modeLabel=New-Label 'Continuous' 20 310 205 27 12 ([System.Drawing.Color]::FromArgb(166,149,255)) $true; $monitor.Controls.Add($modeLabel)
$monitor.Controls.Add((New-Label 'Ready when you are.' 20 350 205 24 8 $script:colorMuted))

$startButton=New-Button '▶   Start clicking' 26 512 442 54 $script:colorAccent ([System.Drawing.Color]::White); $form.Controls.Add($startButton)
$stopButton=New-Button '■   Stop' 486 512 246 54 ([System.Drawing.Color]::FromArgb(48,55,73)) ([System.Drawing.Color]::White); $form.Controls.Add($stopButton)

# Expanded controls use the same dark card system as the main panel.
$advanced=New-Card 26 625 850 540; $form.Controls.Add($advanced)
$advanced.Controls.Add((New-Label 'More control' 22 16 300 30 15 ([System.Drawing.Color]::White) $true))
$advanced.Controls.Add((New-Label 'Fine-tune the click pattern and set screen safety stops.' 22 47 700 22 9 $script:colorMuted))
$advanced.Controls.Add((New-Label 'SPEED MODE' 22 83 150 20 8 $script:colorMuted $true))
$speedMode=[System.Windows.Forms.ComboBox]::new(); $speedMode.Location=[System.Drawing.Point]::new(22,107); $speedMode.Size=[System.Drawing.Size]::new(170,30); $speedMode.DropDownStyle='DropDownList'; [void]$speedMode.Items.AddRange(@('Interval','Clicks per second')); $speedMode.SelectedIndex=0; $speedMode.BackColor=[System.Drawing.Color]::FromArgb(34,40,57); $speedMode.ForeColor=[System.Drawing.Color]::White; $advanced.Controls.Add($speedMode)
$rate=[System.Windows.Forms.NumericUpDown]::new(); $rate.Location=[System.Drawing.Point]::new(207,107); $rate.Size=[System.Drawing.Size]::new(140,30); $rate.Minimum=1; $rate.Maximum=500; $rate.Value=10; $rate.Enabled=$false; $advanced.Controls.Add($rate)
$speedMode.Add_SelectedIndexChanged({ $rate.Enabled=($speedMode.SelectedIndex -eq 1); $interval.Enabled=($speedMode.SelectedIndex -eq 0);$intervalUnit.Enabled=($speedMode.SelectedIndex -eq 0); if($speedMode.SelectedIndex -eq 1){Set-IntervalMilliseconds ([long][Math]::Max(1,[Math]::Round(1000/[double]$rate.Value)))} })
$rate.Add_ValueChanged({ if($speedMode.SelectedIndex -eq 1){Set-IntervalMilliseconds ([long][Math]::Max(1,[Math]::Round(1000/[double]$rate.Value)))} })
$advanced.Controls.Add((New-Label 'GLOBAL HOTKEY BEHAVIOR' 390 83 220 20 8 $script:colorMuted $true))
$hotkeyMode=[System.Windows.Forms.ComboBox]::new(); $hotkeyMode.Location=[System.Drawing.Point]::new(390,107); $hotkeyMode.Size=[System.Drawing.Size]::new(180,30); $hotkeyMode.DropDownStyle='DropDownList'; [void]$hotkeyMode.Items.AddRange(@('Toggle','Hold while pressed')); $hotkeyMode.SelectedIndex=0; $hotkeyMode.BackColor=[System.Drawing.Color]::FromArgb(34,40,57); $hotkeyMode.ForeColor=[System.Drawing.Color]::White; $advanced.Controls.Add($hotkeyMode)
$keyboardMode=[System.Windows.Forms.CheckBox]::new(); $keyboardMode.Text='Send keyboard key'; $keyboardMode.Location=[System.Drawing.Point]::new(22,158); $keyboardMode.Size=[System.Drawing.Size]::new(180,25); $keyboardMode.ForeColor=[System.Drawing.Color]::White; $advanced.Controls.Add($keyboardMode)
$keyCodePick=[System.Windows.Forms.ComboBox]::new(); $keyCodePick.Location=[System.Drawing.Point]::new(207,155); $keyCodePick.Size=[System.Drawing.Size]::new(140,28); $keyCodePick.DropDownStyle='DropDownList'; [void]$keyCodePick.Items.AddRange(@('Space','Enter','A','F')); $keyCodePick.SelectedIndex=0; $keyCodePick.Enabled=$false; $advanced.Controls.Add($keyCodePick)
$keyboardMode.Add_CheckedChanged({$keyCodePick.Enabled=$keyboardMode.Checked})
$doubleClick=[System.Windows.Forms.CheckBox]::new(); $doubleClick.Text='Double click'; $doubleClick.Location=[System.Drawing.Point]::new(390,158); $doubleClick.Size=[System.Drawing.Size]::new(150,25); $doubleClick.ForeColor=[System.Drawing.Color]::White; $advanced.Controls.Add($doubleClick)
$advanced.Controls.Add((New-Label 'DUTY CYCLE · BUTTON HELD (%)' 22 205 260 20 8 $script:colorMuted $true))
$duty=[System.Windows.Forms.NumericUpDown]::new(); $duty.Location=[System.Drawing.Point]::new(22,230); $duty.Size=[System.Drawing.Size]::new(120,30); $duty.Minimum=0; $duty.Maximum=100; $duty.Value=0; $advanced.Controls.Add($duty)
$advanced.Controls.Add((New-Label '0 = instant tap' 150 235 160 20 9 $script:colorMuted))
$advanced.Controls.Add((New-Label 'SPEED RANDOMIZATION (%)' 390 205 250 20 8 $script:colorMuted $true))
$randomize=[System.Windows.Forms.NumericUpDown]::new(); $randomize.Location=[System.Drawing.Point]::new(390,230); $randomize.Size=[System.Drawing.Size]::new(120,30); $randomize.Minimum=0; $randomize.Maximum=90; $randomize.Value=0; $advanced.Controls.Add($randomize)
$cornerStop=[System.Windows.Forms.CheckBox]::new(); $cornerStop.Text='Stop at screen corners'; $cornerStop.Location=[System.Drawing.Point]::new(22,287); $cornerStop.Size=[System.Drawing.Size]::new(220,25); $cornerStop.ForeColor=[System.Drawing.Color]::White; $advanced.Controls.Add($cornerStop)
$cornerSize=[System.Windows.Forms.NumericUpDown]::new(); $cornerSize.Location=[System.Drawing.Point]::new(245,284); $cornerSize.Size=[System.Drawing.Size]::new(95,30); $cornerSize.Minimum=10; $cornerSize.Maximum=500; $cornerSize.Value=50; $advanced.Controls.Add($cornerSize)
$edgeStop=[System.Windows.Forms.CheckBox]::new(); $edgeStop.Text='Stop at screen edges'; $edgeStop.Location=[System.Drawing.Point]::new(390,287); $edgeStop.Size=[System.Drawing.Size]::new(200,25); $edgeStop.ForeColor=[System.Drawing.Color]::White; $advanced.Controls.Add($edgeStop)
$edgeSize=[System.Windows.Forms.NumericUpDown]::new(); $edgeSize.Location=[System.Drawing.Point]::new(600,284); $edgeSize.Size=[System.Drawing.Size]::new(95,30); $edgeSize.Minimum=5; $edgeSize.Maximum=300; $edgeSize.Value=40; $advanced.Controls.Add($edgeSize)
$script:points=[System.Collections.ArrayList]::new()
$pointList=[System.Windows.Forms.ListBox]::new(); $pointList.Location=[System.Drawing.Point]::new(22,500); $pointList.Size=[System.Drawing.Size]::new(380,92); $advanced.Controls.Add($pointList)
$pointList.DrawMode='OwnerDrawFixed'; $pointList.BorderStyle='None'; $pointList.ItemHeight=24
$pointList.Add_DrawItem({param($s,$e) $e.Graphics.FillRectangle([System.Drawing.SolidBrush]::new($script:colorPanel),$e.Bounds);if($e.Index -ge 0){$e.Graphics.DrawString($s.Items[$e.Index],$s.Font,[System.Drawing.SolidBrush]::new([System.Drawing.Color]::White),$e.Bounds)};if(($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0){$e.Graphics.DrawRectangle([System.Drawing.Pen]::new($script:colorAccent,2),[System.Drawing.Rectangle]::Inflate($e.Bounds,-1,-1))}})
$pickPoint=New-Button 'Pick point' 420 500 140 34 $script:colorAccent ([System.Drawing.Color]::White); $advanced.Controls.Add($pickPoint)
$removePoint=New-Button 'Remove' 420 542 140 34 ([System.Drawing.Color]::FromArgb(48,55,73)) ([System.Drawing.Color]::White); $advanced.Controls.Add($removePoint)
$script:pointPicker=$false
foreach($control in $advanced.Controls){
    if($control -is [System.Windows.Forms.NumericUpDown]){$control.BackColor=[System.Drawing.Color]::FromArgb(34,40,57);$control.ForeColor=[System.Drawing.Color]::White;$control.BorderStyle='None'}
    elseif($control -is [System.Windows.Forms.ComboBox]){$control.FlatStyle='Flat'}
    elseif($control -is [System.Windows.Forms.ListBox]){$control.BackColor=[System.Drawing.Color]::FromArgb(34,40,57);$control.ForeColor=[System.Drawing.Color]::White}
    elseif($control -is [System.Windows.Forms.CheckBox]){$control.BackColor=$script:colorPanel}
}

# Replace the long, stacked form with compact top navigation and focused pages.
$pageHost=[System.Windows.Forms.Panel]::new(); $pageHost.Location=[System.Drawing.Point]::new(16,52); $pageHost.Size=[System.Drawing.Size]::new(1018,700); $pageHost.Anchor='Top,Bottom,Left,Right';$pageHost.BackColor=$script:colorBg; $form.Controls.Add($pageHost)
$navBar=[System.Windows.Forms.Panel]::new(); $navBar.Location=[System.Drawing.Point]::new(0,0); $navBar.Size=[System.Drawing.Size]::new(1080,46);$navBar.Anchor='Top,Left,Right';$navBar.Tag='titlebar';$navBar.BackColor=[System.Drawing.Color]::FromArgb(22,22,22); $form.Controls.Add($navBar)
$navBar.Controls.Add($brandMark);$navBar.Controls.Add($brandTitle);$navBar.Controls.Add($statusPill)
$script:titleAccentLine=[System.Windows.Forms.Panel]::new();$script:titleAccentLine.Location=[System.Drawing.Point]::new(0,44);$script:titleAccentLine.Size=[System.Drawing.Size]::new(1080,2);$script:titleAccentLine.Anchor='Bottom,Left,Right';$script:titleAccentLine.BackColor=$script:colorAccent;$navBar.Controls.Add($script:titleAccentLine)
$settingsBar=[System.Windows.Forms.Panel]::new();$settingsBar.Location=[System.Drawing.Point]::new(16,52);$settingsBar.Size=[System.Drawing.Size]::new(152,700);$settingsBar.Anchor='Top,Bottom,Left';$settingsBar.BackColor=$script:colorPanel;$settingsBar.Visible=$false;$form.Controls.Add($settingsBar)
$settingsBar.Controls.Add((New-Label 'SETTINGS' 12 8 126 22 8 $script:colorMuted $true))
$clickPage=[System.Windows.Forms.Panel]::new(); $clickPage.Size=$pageHost.Size; $clickPage.BackColor=[System.Drawing.Color]::Transparent
$behaviorPage=[System.Windows.Forms.Panel]::new(); $behaviorPage.Size=$pageHost.Size; $behaviorPage.BackColor=[System.Drawing.Color]::Transparent
$appearancePage=[System.Windows.Forms.Panel]::new(); $appearancePage.Size=$pageHost.Size; $appearancePage.BackColor=[System.Drawing.Color]::Transparent; $appearancePage.AutoScroll=$false
$clickPointsPage=[System.Windows.Forms.Panel]::new();$clickPointsPage.Size=$pageHost.Size;$clickPointsPage.BackColor=[System.Drawing.Color]::Transparent
$keybindPage=[System.Windows.Forms.Panel]::new();$keybindPage.Size=$pageHost.Size;$keybindPage.BackColor=[System.Drawing.Color]::Transparent;$keybindPage.AutoScroll=$true
$processPage=[System.Windows.Forms.Panel]::new();$processPage.Size=$pageHost.Size;$processPage.BackColor=[System.Drawing.Color]::Transparent
$presetsPage=[System.Windows.Forms.Panel]::new();$presetsPage.Size=$pageHost.Size;$presetsPage.BackColor=[System.Drawing.Color]::Transparent
$maintenancePage=[System.Windows.Forms.Panel]::new();$maintenancePage.Size=$pageHost.Size;$maintenancePage.BackColor=[System.Drawing.Color]::Transparent
$pageHost.Controls.AddRange(@($clickPage,$behaviorPage,$clickPointsPage,$appearancePage,$keybindPage,$processPage,$presetsPage,$maintenancePage))
$form.Controls.Remove($settings); $form.Controls.Remove($monitor); $form.Controls.Remove($startButton); $form.Controls.Remove($stopButton); $form.Controls.Remove($advanced)
$settings.Location=[System.Drawing.Point]::new(0,0); $monitor.Location=[System.Drawing.Point]::new(460,0); $monitor.Size=[System.Drawing.Size]::new(390,396)
$clickPage.Controls.AddRange(@($settings,$monitor))
$startButton.Location=[System.Drawing.Point]::new(0,420); $startButton.Size=[System.Drawing.Size]::new(442,54); $clickPage.Controls.Add($startButton)
$stopButton.Location=[System.Drawing.Point]::new(460,420); $stopButton.Size=[System.Drawing.Size]::new(390,54); $clickPage.Controls.Add($stopButton)
$script:footerLeft=New-Label 'TapForge  |  Runs locally on your PC' 4 490 380 22 8 $script:colorMuted; $clickPage.Controls.Add($script:footerLeft)
$script:footerRight=New-Label 'F6 START/STOP    F7 EMERGENCY STOP' 460 490 350 22 8 $script:colorMuted $true; $clickPage.Controls.Add($script:footerRight)
$advanced.Location=[System.Drawing.Point]::new(0,0); $advanced.Size=[System.Drawing.Size]::new(850,280); $behaviorPage.Controls.Add($advanced)
$behaviorPage.AutoScroll=$false
$behaviorExtras=New-Card 0 292 830 780;$behaviorPage.Controls.Add($behaviorExtras)
$behaviorExtras.Controls.Add((New-Label 'Behavior and startup' 20 16 330 28 15 ([System.Drawing.Color]::White) $true))
function Add-BehaviorToggle([string]$title,[string]$detail,[int]$y,[bool]$checked=$false){$behaviorExtras.Controls.Add((New-Label $title 20 $y 520 24 11 ([System.Drawing.Color]::White) $true));$behaviorExtras.Controls.Add((New-Label $detail 20 ($y+22) 640 22 9 $script:colorMuted));$cb=[TapForgeSwitch]::new();$cb.Location=[System.Drawing.Point]::new(754,$y+1);$cb.Checked=$checked;$cb.AccessibleName=$title;if(!$script:behaviorSwitches){$script:behaviorSwitches=[System.Collections.Generic.List[TapForgeSwitch]]::new()};$script:behaviorSwitches.Add($cb);$behaviorExtras.Controls.Add($cb);$cb}
$script:alwaysTop=Add-BehaviorToggle 'Always on top' 'Keep TapForge above other windows.' 56 $false
$script:stopAlert=Add-BehaviorToggle 'Stop reason alert' 'Show a notification when an automatic safety limit stops clicking.' 108 $true
$script:strictHotkey=Add-BehaviorToggle 'Strict hotkey modifiers' 'Ignore the start shortcut while Ctrl, Shift, Alt, or Windows is held.' 188 $false
$script:stopAltTab=Add-BehaviorToggle 'Stop on Alt+Tab' 'Stop clicking when switching to another window.' 240 $false
$script:extendedSpeed=Add-BehaviorToggle 'Extended speed limit' 'Allow rates up to 1000 CPS; actual speed depends on Windows and the target app.' 292 $false
$behaviorExtras.Controls.Add((New-Label 'Click point defaults' 20 352 330 26 12 ([System.Drawing.Color]::White) $true))
$behaviorExtras.Controls.Add((New-Label 'Clicks per point' 20 388 250 24 10 $script:colorMuted));$script:pointDefaultClicks=[System.Windows.Forms.NumericUpDown]::new();$script:pointDefaultClicks.Location=[System.Drawing.Point]::new(700,384);$script:pointDefaultClicks.Size=[System.Drawing.Size]::new(90,28);$script:pointDefaultClicks.Minimum=1;$script:pointDefaultClicks.Maximum=9999;$script:pointDefaultClicks.Value=1;$behaviorExtras.Controls.Add($script:pointDefaultClicks)
$behaviorExtras.Controls.Add((New-Label 'Randomization radius (pixels)' 20 430 300 24 10 $script:colorMuted));$script:pointDefaultRadius=[System.Windows.Forms.NumericUpDown]::new();$script:pointDefaultRadius.Location=[System.Drawing.Point]::new(700,426);$script:pointDefaultRadius.Size=[System.Drawing.Size]::new(90,28);$script:pointDefaultRadius.Minimum=0;$script:pointDefaultRadius.Maximum=1000;$script:pointDefaultRadius.Value=0;$behaviorExtras.Controls.Add($script:pointDefaultRadius)
$behaviorExtras.Controls.Add((New-Label 'Startup' 20 476 330 26 12 ([System.Drawing.Color]::White) $true))
$script:minimizeTray=Add-BehaviorToggle 'Minimize to tray' 'Close to the notification area instead of exiting.' 504 $false
$script:rememberPosition=Add-BehaviorToggle 'Remember window position' 'Open the window at its last position.' 556 $true
$script:runOnStartup=Add-BehaviorToggle 'Run on startup' 'Start TapForge when you sign in to Windows.' 608 $false
$behaviorExtras.Controls.Add((New-Label 'Screen safety' 20 680 330 26 12 ([System.Drawing.Color]::White) $true))
foreach($control in @($cornerStop,$cornerSize,$edgeStop,$edgeSize)){$advanced.Controls.Remove($control);$behaviorExtras.Controls.Add($control)}
$cornerStop.Location=[System.Drawing.Point]::new(20,716);$cornerSize.Location=[System.Drawing.Point]::new(245,713);$edgeStop.Location=[System.Drawing.Point]::new(390,716);$edgeSize.Location=[System.Drawing.Point]::new(600,713)
$script:extendedSpeed.Add_CheckedChanged({$rate.Maximum=if($script:extendedSpeed.Checked){1000}else{500};$quickRate.Maximum=$rate.Maximum;if($rate.Value -gt $rate.Maximum){$rate.Value=$rate.Maximum}})
$script:alwaysTop.Add_CheckedChanged({$form.TopMost=$script:alwaysTop.Checked;if($script:pinButton){$script:pinButton.BackColor=if($script:alwaysTop.Checked){$script:colorAccent}else{Blend-Color $script:colorPanel $script:colorAccent 18}}})
$script:runOnStartup.Add_CheckedChanged({try{$rk=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run',$true);if($script:runOnStartup.Checked){$rk.SetValue('TapForge','"'+(Join-Path $PSScriptRoot 'TapForge.exe')+'"')}else{$rk.DeleteValue('TapForge',$false)};$rk.Dispose()}catch{[System.Windows.Forms.MessageBox]::Show('Could not update the Windows startup setting.','TapForge')}})
$clickPointsCard=New-Card 0 0 850 360;$clickPointsPage.Controls.Add($clickPointsCard)
foreach($control in @($pointList,$pickPoint,$removePoint)){$advanced.Controls.Remove($control);$clickPointsCard.Controls.Add($control)}
$clickPointsCard.Controls.Add((New-Label 'Click points' 22 18 300 30 16 ([System.Drawing.Color]::White) $true))
$clickPointsCard.Controls.Add((New-Label 'Pick screen locations to click in sequence. Each point uses the active click settings.' 22 50 790 24 9 $script:colorMuted))
$script:pointsEnabled=[System.Windows.Forms.CheckBox]::new();$script:pointsEnabled.Text='Enable click points';$script:pointsEnabled.Location=[System.Drawing.Point]::new(600,22);$script:pointsEnabled.Size=[System.Drawing.Size]::new(190,28);$script:pointsEnabled.ForeColor=[System.Drawing.Color]::White;$clickPointsCard.Controls.Add($script:pointsEnabled)
$script:stopWhenPointsDone=[System.Windows.Forms.CheckBox]::new();$script:stopWhenPointsDone.Text='Stop when complete';$script:stopWhenPointsDone.Location=[System.Drawing.Point]::new(570,210);$script:stopWhenPointsDone.Size=[System.Drawing.Size]::new(200,28);$script:stopWhenPointsDone.ForeColor=[System.Drawing.Color]::White;$clickPointsCard.Controls.Add($script:stopWhenPointsDone)
$pointList.Location=[System.Drawing.Point]::new(22,100);$pointList.Size=[System.Drawing.Size]::new(520,220)
$pickPoint.Location=[System.Drawing.Point]::new(570,100);$pickPoint.Size=[System.Drawing.Size]::new(180,38)
$removePoint.Location=[System.Drawing.Point]::new(570,148);$removePoint.Size=[System.Drawing.Size]::new(180,38)
$pageButtons=@{};$settingButtons=@{}
function Show-Page([string]$name){
    $script:currentPage=$name
    if($script:appearanceMode -eq 'Individual page' -and $script:pageAccents.ContainsKey($name)){$script:colorAccent=$script:pageAccents[$name]}else{$script:colorAccent=$script:globalAccent}
    $isSettings=($name -in @('Appearance','Keybinds','Process List','Presets','Maintenance'));$settingsBar.Visible=$isSettings;$contentWidth=[Math]::Max(700,$form.ClientSize.Width-32);$contentHeight=[Math]::Max(450,$form.ClientSize.Height-76);$settingsBar.Size=[System.Drawing.Size]::new(152,$contentHeight);$pageHost.Location=if($isSettings){[System.Drawing.Point]::new(184,52)}else{[System.Drawing.Point]::new(16,52)};$pageHost.Size=if($isSettings){[System.Drawing.Size]::new($contentWidth-168,$contentHeight)}else{[System.Drawing.Size]::new($contentWidth,$contentHeight)};foreach($p in $pageHost.Controls){$p.Size=$pageHost.Size}
    if(!$isSettings){$leftWidth=[int](($pageHost.Width-18)/2);$settings.Width=$leftWidth;$monitor.Location=[System.Drawing.Point]::new($leftWidth+18,0);$monitor.Width=$pageHost.Width-$leftWidth-18;$startButton.Width=$leftWidth;$stopButton.Location=[System.Drawing.Point]::new($leftWidth+18,420);$stopButton.Width=$pageHost.Width-$leftWidth-18;$script:footerRight.Location=[System.Drawing.Point]::new($leftWidth+18,490);$script:footerRight.Width=$pageHost.Width-$leftWidth-18;$advanced.Width=$pageHost.Width;$behaviorExtras.Width=$pageHost.Width-20;$clickPointsCard.Width=$pageHost.Width};$processCard.Width=$pageHost.Width;$presetCard.Width=$pageHost.Width;$maintenanceCard.Width=$pageHost.Width
    $behaviorPage.PerformLayout();if($script:behaviorScrollTrack){$script:behaviorScrollTrack.Location=[System.Drawing.Point]::new([Math]::Max(0,$behaviorPage.Width-8),0);$script:behaviorScrollTrack.Size=[System.Drawing.Size]::new(8,$behaviorPage.Height)};$behaviorContentWidth=[Math]::Max(700,$behaviorPage.ClientSize.Width-12);$advanced.Width=$behaviorContentWidth;$behaviorExtras.Width=[Math]::Max(680,$behaviorContentWidth-20);if($script:behaviorScrollTrack){Set-BehaviorScroll $script:behaviorScrollOffset}
    $clickPage.Visible=($name -eq 'Clicking');$behaviorPage.Visible=($name -eq 'Behavior');if($script:behaviorScrollTrack){$script:behaviorScrollTrack.Visible=($name -eq 'Behavior')};$clickPointsPage.Visible=($name -eq 'Click Points');$appearancePage.Visible=($name -eq 'Appearance');$keybindPage.Visible=($name -eq 'Keybinds');$processPage.Visible=($name -eq 'Process List');$presetsPage.Visible=($name -eq 'Presets');$maintenancePage.Visible=($name -eq 'Maintenance')
    foreach($key in $pageButtons.Keys){$pageButtons[$key].BackColor=if($key -eq $name){$script:colorAccent}else{Blend-Color $script:colorPanel $script:colorAccent 12};$pageButtons[$key].ForeColor=[System.Drawing.Color]::White}
    foreach($key in $settingButtons.Keys){$settingButtons[$key].BackColor=if($key -eq $name){$script:colorAccent}else{Blend-Color $script:colorPanel $script:colorAccent 12};$settingButtons[$key].ForeColor=[System.Drawing.Color]::White}
    Apply-Accent
}
$navIcons=@{Clicking='◉';Behavior='◌';'Click Points'='⊙'}
foreach($page in @('Clicking','Behavior','Click Points')){$btn=New-Button $navIcons[$page] (48+($pageButtons.Count*38)) 6 32 32 ([System.Drawing.Color]::FromArgb(34,40,57)) ([System.Drawing.Color]::White);$btn.Font=[System.Drawing.Font]::new('Segoe UI Symbol',12,[System.Drawing.FontStyle]::Regular);$btn.Tag=$page;$btn.AccessibleName=$page;$navBar.Controls.Add($btn);$pageButtons[$page]=$btn;$btn.Add_Click({param($sender,$eventArgs) Show-Page $sender.Tag})}
$gearButton=New-Button '⚙' 8 6 32 32 ([System.Drawing.Color]::FromArgb(34,40,57)) ([System.Drawing.Color]::White);$gearButton.Font=[System.Drawing.Font]::new('Segoe UI Symbol',12,[System.Drawing.FontStyle]::Regular);$gearButton.AccessibleName='Settings';$navBar.Controls.Add($gearButton);$gearButton.Add_Click({Show-Page 'Appearance'})
$script:headerTips=[System.Windows.Forms.ToolTip]::new();$script:headerTips.SetToolTip($gearButton,'Settings');foreach($entry in $pageButtons.GetEnumerator()){$script:headerTips.SetToolTip($entry.Value,$entry.Value.AccessibleName)}
$script:pinButton=New-Button '⌖' 0 6 30 32 ([System.Drawing.Color]::FromArgb(34,40,57)) ([System.Drawing.Color]::White);$script:pinButton.Font=[System.Drawing.Font]::new('Segoe UI Symbol',12);$script:pinButton.AccessibleName='Always on top';$script:pinButton.Tag='chrome';$navBar.Controls.Add($script:pinButton);$script:headerTips.SetToolTip($script:pinButton,'Always on top');$script:pinButton.Add_Click({$script:alwaysTop.Checked=!$script:alwaysTop.Checked})
$script:windowMin=New-Button '—' 0 6 30 32 ([System.Drawing.Color]::FromArgb(22,22,22)) ([System.Drawing.Color]::White);$script:windowMin.Font=[System.Drawing.Font]::new('Segoe UI',11);$script:windowMin.Tag='chrome';$navBar.Controls.Add($script:windowMin);$script:headerTips.SetToolTip($script:windowMin,'Minimize');$script:windowMin.Add_Click({$form.WindowState=[System.Windows.Forms.FormWindowState]::Minimized})
$script:windowMax=New-Button '□' 0 6 30 32 ([System.Drawing.Color]::FromArgb(22,22,22)) ([System.Drawing.Color]::White);$script:windowMax.Font=[System.Drawing.Font]::new('Segoe UI Symbol',10);$script:windowMax.Tag='chrome';$navBar.Controls.Add($script:windowMax);$script:headerTips.SetToolTip($script:windowMax,'Maximize');$script:windowMax.Add_Click({if($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized){$form.WindowState=[System.Windows.Forms.FormWindowState]::Normal}else{$form.WindowState=[System.Windows.Forms.FormWindowState]::Maximized}})
$script:windowClose=New-Button '×' 0 6 34 32 ([System.Drawing.Color]::FromArgb(22,22,22)) ([System.Drawing.Color]::White);$script:windowClose.Font=[System.Drawing.Font]::new('Segoe UI',15);$script:windowClose.Tag='chrome';$navBar.Controls.Add($script:windowClose);$script:headerTips.SetToolTip($script:windowClose,'Close');$script:windowClose.Add_Click({$form.Close()})
$script:windowMin.FlatAppearance.MouseOverBackColor=[System.Drawing.Color]::FromArgb(55,55,55);$script:windowMax.FlatAppearance.MouseOverBackColor=[System.Drawing.Color]::FromArgb(55,55,55);$script:windowClose.FlatAppearance.MouseOverBackColor=[System.Drawing.Color]::FromArgb(190,45,55)
$navBar.Add_Resize({$w=$navBar.ClientSize.Width;$brandX=[int](($w-160)/2);$brandMark.Location=[System.Drawing.Point]::new($brandX,6);$brandTitle.Location=[System.Drawing.Point]::new($brandX+40,7);$statusPill.Location=[System.Drawing.Point]::new([Math]::Max(520,$w-350),11);$script:pinButton.Location=[System.Drawing.Point]::new($w-246,6);if($script:compactButton){$script:compactButton.Location=[System.Drawing.Point]::new($w-208,6)};$script:windowMin.Location=[System.Drawing.Point]::new($w-132,6);$script:windowMax.Location=[System.Drawing.Point]::new($w-98,6);$script:windowClose.Location=[System.Drawing.Point]::new($w-64,6)})
foreach($dragTarget in @($navBar,$brandMark,$brandTitle,$statusPill,$script:titleAccentLine)){$dragTarget.Add_MouseDown({param($s,$e)if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left){[TapForgeWindow]::BeginDrag($form.Handle)}})}
foreach($entry in @(@('Appearance','☼','Appearance'),@('Keybinds','⌘','Keybinds'),@('Process List','▤','Process List'),@('Presets','◆','Presets'),@('Maintenance','⚒','Maintenance'))){$page=$entry[0];$caption="$($entry[1])   $($entry[2])";$btn=New-Button $caption 8 (36+($settingButtons.Count*48)) 136 40 ([System.Drawing.Color]::FromArgb(34,40,57)) ([System.Drawing.Color]::White);$btn.Tag=$page;$settingsBar.Controls.Add($btn);$settingButtons[$page]=$btn;$btn.Add_Click({param($sender,$eventArgs) Show-Page $sender.Tag})}
$processCard=New-Card 0 0 830 540;$processPage.Controls.Add($processCard)
$processCard.Controls.Add((New-Label 'Process list' 20 18 300 30 16 ([System.Drawing.Color]::White) $true))
$processCard.Controls.Add((New-Label 'Optionally restrict clicks to one foreground application.' 20 50 700 24 9 $script:colorMuted))
$processList=[System.Windows.Forms.ListBox]::new();$processList.Location=[System.Drawing.Point]::new(20,96);$processList.Size=[System.Drawing.Size]::new(550,360);$processList.BackColor=[System.Drawing.Color]::FromArgb(34,40,57);$processList.ForeColor=[System.Drawing.Color]::White;$processCard.Controls.Add($processList)
$refreshProcesses=New-Button 'Refresh' 600 96 170 36 $script:colorAccent ([System.Drawing.Color]::White);$processCard.Controls.Add($refreshProcesses)
$script:filterProcess=[System.Windows.Forms.CheckBox]::new();$script:filterProcess.Text='Only click while selected app is active';$script:filterProcess.Location=[System.Drawing.Point]::new(600,150);$script:filterProcess.Size=[System.Drawing.Size]::new(210,48);$script:filterProcess.ForeColor=[System.Drawing.Color]::White;$processCard.Controls.Add($script:filterProcess)
$script:processIds=[System.Collections.Generic.List[int]]::new();$refreshProcesses.Add_Click({$processList.Items.Clear();$script:processIds.Clear();foreach($p in [System.Diagnostics.Process]::GetProcesses()|Where-Object {$_.MainWindowTitle}|Sort-Object MainWindowTitle){[void]$processList.Items.Add(('{0}  (PID {1})' -f $p.MainWindowTitle,$p.Id));$script:processIds.Add($p.Id)}})
$refreshProcesses.PerformClick()
$keybindCard=New-Card 0 0 830 430;$keybindPage.Controls.Add($keybindCard)
$keybindCard.Controls.Add((New-Label 'Keybinds' 20 18 300 30 16 ([System.Drawing.Color]::White) $true))
$keybindCard.Controls.Add((New-Label 'Set the global start/stop and emergency stop keys.' 20 50 700 24 9 $script:colorMuted))
$keybindCard.Controls.Add((New-Label 'Start / stop clicking' 20 104 400 28 12 ([System.Drawing.Color]::White) $true));$startKeyHint=New-Label 'Global shortcut · works while TapForge is minimized.' 20 132 520 22 9 $script:colorMuted;$keybindCard.Controls.Add($startKeyHint)
$startKeyOnKeybind=[System.Windows.Forms.ComboBox]::new();$startKeyOnKeybind.Location=[System.Drawing.Point]::new(600,104);$startKeyOnKeybind.Size=[System.Drawing.Size]::new(170,34);$startKeyOnKeybind.DropDownStyle='DropDownList';[void]$startKeyOnKeybind.Items.AddRange(@('F6','F8','F9','F10','F11','F12'));$startKeyOnKeybind.SelectedItem=$keyPick.SelectedItem;$keybindCard.Controls.Add($startKeyOnKeybind)
$keybindCard.Controls.Add((New-Label 'Emergency stop' 20 200 400 28 12 ([System.Drawing.Color]::White) $true));$keybindCard.Controls.Add((New-Label 'Always stops the click engine immediately.' 20 228 520 22 9 $script:colorMuted))
$script:emergencyKey=[System.Windows.Forms.ComboBox]::new();$script:emergencyKey.Location=[System.Drawing.Point]::new(600,200);$script:emergencyKey.Size=[System.Drawing.Size]::new(170,34);$script:emergencyKey.DropDownStyle='DropDownList';[void]$script:emergencyKey.Items.AddRange(@('F7','F8','F9','F10','F11','F12'));$script:emergencyKey.SelectedIndex=0;$keybindCard.Controls.Add($script:emergencyKey)
$script:syncingKeys=$false
$keyPick.Add_SelectedIndexChanged({if(!$script:syncingKeys -and $null -ne $startKeyOnKeybind){$script:syncingKeys=$true;$startKeyOnKeybind.SelectedItem=$keyPick.SelectedItem;if($script:emergencyKey.SelectedItem -eq $keyPick.SelectedItem){$script:emergencyKey.SelectedIndex=0};$script:syncingKeys=$false}})
$startKeyOnKeybind.Add_SelectedIndexChanged({if(!$script:syncingKeys -and $null -ne $startKeyOnKeybind.SelectedItem){$script:syncingKeys=$true;$keyPick.SelectedItem=$startKeyOnKeybind.SelectedItem;$script:syncingKeys=$false}})
$script:emergencyKey.Add_SelectedIndexChanged({if(!$script:syncingKeys -and $script:emergencyKey.SelectedItem -eq $keyPick.SelectedItem){$script:syncingKeys=$true;$keyPick.SelectedItem='F6';$startKeyOnKeybind.SelectedItem='F6';$script:syncingKeys=$false}})
$keybindCard.Controls.Add((New-Label 'Use Behavior to choose toggle or hold mode.' 20 300 740 44 9 $script:colorMuted))
$presetCard=New-Card 0 0 830 540;$presetsPage.Controls.Add($presetCard)
$presetCard.Controls.Add((New-Label 'Presets' 20 18 300 30 16 ([System.Drawing.Color]::White) $true))
$presetCard.Controls.Add((New-Label 'Save and restore your click settings.' 20 50 700 24 9 $script:colorMuted))
$script:presetName=[System.Windows.Forms.TextBox]::new();$script:presetName.Location=[System.Drawing.Point]::new(20,96);$script:presetName.Size=[System.Drawing.Size]::new(400,34);$presetCard.Controls.Add($script:presetName)
$presetList=[System.Windows.Forms.ListBox]::new();$presetList.Location=[System.Drawing.Point]::new(20,150);$presetList.Size=[System.Drawing.Size]::new(540,330);$presetList.BackColor=[System.Drawing.Color]::FromArgb(34,40,57);$presetList.ForeColor=[System.Drawing.Color]::White;$presetCard.Controls.Add($presetList)
$presetSave=New-Button 'Save current' 600 96 170 36 $script:colorAccent ([System.Drawing.Color]::White);$presetLoad=New-Button 'Load selected' 600 150 170 36 $script:colorAccent ([System.Drawing.Color]::White);$presetDelete=New-Button 'Delete selected' 600 204 170 36 ([System.Drawing.Color]::FromArgb(48,55,73)) ([System.Drawing.Color]::White);$presetCard.Controls.AddRange(@($presetSave,$presetLoad,$presetDelete))
$script:presetDirectory=Join-Path $env:LOCALAPPDATA 'TapForge\Presets';[void](New-Item -ItemType Directory -Force -Path $script:presetDirectory)
function Refresh-Presets {$presetList.Items.Clear();foreach($f in Get-ChildItem -LiteralPath $script:presetDirectory -Filter '*.json' -ErrorAction SilentlyContinue){[void]$presetList.Items.Add([System.IO.Path]::GetFileNameWithoutExtension($f.Name))}}
$presetSave.Add_Click({$name=($script:presetName.Text -replace '[^a-zA-Z0-9 _-]','').Trim();if(!$name){[System.Windows.Forms.MessageBox]::Show('Enter a preset name first.','TapForge');return};$data=@{intervalMs=(Get-IntervalMilliseconds);interval=[int]$interval.Value;intervalUnit=$intervalUnit.SelectedIndex;button=$buttonPick.SelectedIndex;stopMode=$modePick.SelectedIndex;limit=[long]$limit.Value;speedMode=$speedMode.SelectedIndex;rate=[int]$rate.Value;extended=$script:extendedSpeed.Checked;hotkey=$keyPick.SelectedItem.ToString();hotkeyMode=$hotkeyMode.SelectedIndex;keyboard=$keyboardMode.Checked;keyCode=$keyCodePick.SelectedIndex;double=$doubleClick.Checked;duty=[int]$duty.Value;random=[int]$randomize.Value;corners=$cornerStop.Checked;cornerSize=[int]$cornerSize.Value;edges=$edgeStop.Checked;edgeSize=[int]$edgeSize.Value};$data|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $script:presetDirectory ($name+'.json')) -Encoding UTF8;Refresh-Presets})
$presetLoad.Add_Click({if($presetList.SelectedItem){$d=Get-Content -LiteralPath (Join-Path $script:presetDirectory ($presetList.SelectedItem+'.json')) -Raw|ConvertFrom-Json;$script:extendedSpeed.Checked=[bool]$d.extended;if($d.PSObject.Properties['intervalMs']){$intervalUnit.SelectedIndex=if($d.PSObject.Properties['intervalUnit']){[int]$d.intervalUnit}else{0};Set-IntervalMilliseconds ([long]$d.intervalMs)}else{$intervalUnit.SelectedIndex=0;$SetOldInterval=[decimal]$d.interval;$interval.Value=[Math]::Min($interval.Maximum,[Math]::Max($interval.Minimum,$SetOldInterval))};$buttonPick.SelectedIndex=[int]$d.button;$modePick.SelectedIndex=[int]$d.stopMode;$limit.Value=[decimal]$d.limit;$speedMode.SelectedIndex=[int]$d.speedMode;$rate.Value=[decimal]$d.rate;$keyPick.SelectedItem=[string]$d.hotkey;$hotkeyMode.SelectedIndex=[int]$d.hotkeyMode;$keyboardMode.Checked=[bool]$d.keyboard;$keyCodePick.SelectedIndex=[int]$d.keyCode;$doubleClick.Checked=[bool]$d.double;$duty.Value=[decimal]$d.duty;$randomize.Value=[decimal]$d.random;$cornerStop.Checked=[bool]$d.corners;$cornerSize.Value=[decimal]$d.cornerSize;$edgeStop.Checked=[bool]$d.edges;$edgeSize.Value=[decimal]$d.edgeSize}})
$presetDelete.Add_Click({if($presetList.SelectedItem){Remove-Item -LiteralPath (Join-Path $script:presetDirectory ($presetList.SelectedItem+'.json')) -Force;Refresh-Presets}});Refresh-Presets
$maintenanceCard=New-Card 0 0 830 390;$maintenancePage.Controls.Add($maintenanceCard)
$maintenanceCard.Controls.Add((New-Label 'Maintenance' 20 18 300 30 16 ([System.Drawing.Color]::White) $true))
$maintenanceCard.Controls.Add((New-Label 'Manage settings, diagnostics, and TapForge updates.' 20 50 700 24 9 $script:colorMuted))
$resetSettings=New-Button 'Reset all settings' 20 104 180 38 ([System.Drawing.Color]::FromArgb(48,55,73)) ([System.Drawing.Color]::White);$openDiagnostics=New-Button 'Open diagnostics folder' 220 104 200 38 $script:colorAccent ([System.Drawing.Color]::White);$exportDiagnostics=New-Button 'Export diagnostics' 440 104 180 38 $script:colorAccent ([System.Drawing.Color]::White);$resetUsage=New-Button 'Reset usage data' 20 160 180 38 ([System.Drawing.Color]::FromArgb(48,55,73)) ([System.Drawing.Color]::White);$maintenanceCard.Controls.AddRange(@($resetSettings,$openDiagnostics,$exportDiagnostics,$resetUsage))
$script:checkUpdateButton=New-Button 'Check for updates' 220 160 180 38 $script:colorAccent ([System.Drawing.Color]::White);$maintenanceCard.Controls.Add($script:checkUpdateButton)
$script:publishUpdateButton=New-Button 'Publish update' 420 160 180 38 ([System.Drawing.Color]::FromArgb(48,55,73)) ([System.Drawing.Color]::White);$script:publishUpdateButton.Visible=(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Publish-TapForgeUpdate.ps1'));$maintenanceCard.Controls.Add($script:publishUpdateButton)
$script:updateStatus=New-Label 'Current version: loading…' 20 218 720 24 9 $script:colorMuted;$maintenanceCard.Controls.Add($script:updateStatus)
$script:versionFile=Join-Path $PSScriptRoot 'VERSION';$script:appVersion='3.9.6';if(Test-Path -LiteralPath $script:versionFile){try{$script:appVersion=(Get-Content -LiteralPath $script:versionFile -Raw).Trim()}catch{}}
$script:updateStatus.Text="Current version: $($script:appVersion)"
$script:diagnosticsDirectory=Join-Path $env:LOCALAPPDATA 'TapForge\Diagnostics';[void](New-Item -ItemType Directory -Force -Path $script:diagnosticsDirectory)
$openDiagnostics.Add_Click({Start-Process explorer.exe -ArgumentList ('"'+$script:diagnosticsDirectory+'"')})
$exportDiagnostics.Add_Click({$dlg=[System.Windows.Forms.SaveFileDialog]::new();$dlg.Filter='JSON report|*.json';$dlg.FileName='TapForge-diagnostics.json';if($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK){@{app='TapForge';created=(Get-Date).ToString('o');windows=[Environment]::OSVersion.Version.ToString();powershell=$PSVersionTable.PSVersion.ToString();clicks=$script:clickCount;clickEngine='Native high-resolution worker'}|ConvertTo-Json|Set-Content -LiteralPath $dlg.FileName -Encoding UTF8};$dlg.Dispose()})
$resetUsage.Add_Click({$script:clickCount=0;$countLabel.Text='0';$script:stopwatch.Reset();$elapsedLabel.Text='00:00:00'})
function Get-TapForgeLatestRelease {
    [System.Net.ServicePointManager]::SecurityProtocol=[System.Net.SecurityProtocolType]::Tls12
    $request=[System.Net.HttpWebRequest]::Create('https://api.github.com/repos/saberapexyt-commits/TapForge/releases/latest')
    $request.Method='GET';$request.UserAgent='TapForge-Updater';$request.Accept='application/vnd.github+json';$request.Timeout=7000;$request.ReadWriteTimeout=7000
    $response=$null;$reader=$null
    try{$response=$request.GetResponse();$reader=[System.IO.StreamReader]::new($response.GetResponseStream());$json=$reader.ReadToEnd();ConvertFrom-Json -InputObject $json}
    finally{if($reader){$reader.Dispose()};if($response){$response.Dispose()}}
}
function Install-TapForgeRelease($release) {
    $tag=[string]$release.tag_name;$assetName="TapForge-$tag-Portable.zip";$asset=@($release.assets|Where-Object{$_.name -eq $assetName}|Select-Object -First 1)
    if(!$tag -or !$asset){[System.Windows.Forms.MessageBox]::Show("The $tag release does not contain its portable app ZIP.",'TapForge update',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)|Out-Null;return}
    $target=$PSScriptRoot;$updates=Join-Path $env:LOCALAPPDATA 'TapForge\Updates';$stage=Join-Path $updates ([guid]::NewGuid().ToString('N'));$zip=Join-Path $updates $assetName
    try{
        [void](New-Item -ItemType Directory -Force -Path $stage)
        $request=[System.Net.HttpWebRequest]::Create([string]$asset.browser_download_url);$request.Method='GET';$request.UserAgent='TapForge-Updater';$request.Timeout=30000;$request.ReadWriteTimeout=30000
        $response=$request.GetResponse();try{$inputStream=$response.GetResponseStream();$file=[System.IO.File]::Open($zip,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write);try{$inputStream.CopyTo($file)}finally{$file.Dispose();$inputStream.Dispose()}}finally{$response.Dispose()}
        if($asset.digest -and ([string]$asset.digest -match '^sha256:([0-9a-fA-F]{64})$')){$expected=$Matches[1];$actual=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash;if($actual -ne $expected){throw 'The downloaded update did not pass its SHA-256 check.'}}
        Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
        foreach($required in @('TapForge.exe','AutoClicker.ps1','TapForge.ico','TapForgeLogo.png','VERSION')){if(!(Test-Path -LiteralPath (Join-Path $stage $required))){throw "The update package is missing $required."}}
        $probe=Join-Path $target '.tapforge-update-check';Set-Content -LiteralPath $probe -Value 'ok' -Encoding ascii;Remove-Item -LiteralPath $probe -Force
        $helper=Join-Path $updates 'Apply-TapForgeUpdate.ps1'
        @'
param([string]$TargetDir,[string]$StageDir,[int]$WaitPid)
$ErrorActionPreference='Stop'
for($i=0;$i -lt 120;$i++){if(!(Get-Process -Id $WaitPid -ErrorAction SilentlyContinue)){break};Start-Sleep -Milliseconds 500}
if(Get-Process -Id $WaitPid -ErrorAction SilentlyContinue){exit 2}
foreach($name in @('TapForge.exe','AutoClicker.ps1','TapForge.ico','TapForgeLogo.png','VERSION','README.txt','Launch AutoClicker.bat')){$from=Join-Path $StageDir $name;if(Test-Path -LiteralPath $from){Copy-Item -LiteralPath $from -Destination (Join-Path $TargetDir $name) -Force}}
Start-Process -FilePath (Join-Path $TargetDir 'TapForge.exe') -WorkingDirectory $TargetDir
'@ | Set-Content -LiteralPath $helper -Encoding UTF8
        $args="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$helper`" -TargetDir `"$target`" -StageDir `"$stage`" -WaitPid $PID"
        Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $args -WindowStyle Hidden
        $script:exitRequested=$true;$form.Close()
    }catch{[System.Windows.Forms.MessageBox]::Show("TapForge could not install the update.`r`n`r`n$($_.Exception.Message)",'TapForge update',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null;if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}}
}
$script:updateWorker=[System.ComponentModel.BackgroundWorker]::new();$script:updateWorker.WorkerSupportsCancellation=$false
$script:updateWorker.Add_DoWork({param($sender,$e)try{$e.Result=@{Release=(Get-TapForgeLatestRelease);Automatic=[bool]$e.Argument;Error=$null}}catch{$e.Result=@{Release=$null;Automatic=[bool]$e.Argument;Error=$_.Exception.Message}}})
$script:updateWorker.Add_RunWorkerCompleted({param($sender,$e)$result=$e.Result;if($e.Error){$script:updateStatus.Text='Could not check for updates.';if(!$script:updateCheckAutomatic){[System.Windows.Forms.MessageBox]::Show("Could not check for updates.`r`n`r`n$($e.Error.Message)",'TapForge update')|Out-Null};return};if($result.Error){$script:updateStatus.Text='Could not check for updates.';if(!$result.Automatic){[System.Windows.Forms.MessageBox]::Show("Could not check for updates.`r`n`r`n$($result.Error)",'TapForge update')|Out-Null};return};$release=$result.Release;$available=try{([version]([string]$release.tag_name -replace '^v','')) -gt ([version]$script:appVersion)}catch{$false};if(!$available){$script:updateStatus.Text="You're up to date (v$($script:appVersion)).";if(!$result.Automatic){[System.Windows.Forms.MessageBox]::Show("TapForge v$($script:appVersion) is up to date.",'TapForge update')|Out-Null};return};$script:updateStatus.Text="Update available: $($release.tag_name)";$choice=[System.Windows.Forms.MessageBox]::Show("TapForge $($release.tag_name) is available. Download and install it now?`r`n`r`nTapForge will close and reopen after the update.",'TapForge update',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Information);if($choice -eq [System.Windows.Forms.DialogResult]::Yes){Install-TapForgeRelease $release}})
$script:updateCheckAutomatic=$false
$script:checkForTapForgeUpdate={param([bool]$automatic=$false)if($script:updateWorker.IsBusy){return};$script:updateCheckAutomatic=$automatic;$script:updateStatus.Text='Checking for updates…';$script:updateWorker.RunWorkerAsync($automatic)}
$script:checkUpdateButton.Add_Click({& $script:checkForTapForgeUpdate $false})
$script:publishUpdateButton.Add_Click({$v=[version]$script:appVersion;$next="$($v.Major).$($v.Minor).$($v.Build+1)";$answer=[Microsoft.VisualBasic.Interaction]::InputBox('Enter the version to publish (for example, '+$next+').','Publish TapForge update',$next);if(!$answer){return};if($answer -notmatch '^\d+\.\d+\.\d+$'){[System.Windows.Forms.MessageBox]::Show('Use a version in major.minor.patch format.','Publish TapForge update')|Out-Null;return};$publisher=Join-Path $PSScriptRoot 'Publish-TapForgeUpdate.ps1';$args="-NoProfile -ExecutionPolicy Bypass -File `"$publisher`" -Version `"$answer`"";Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $args -WorkingDirectory $PSScriptRoot})
$resetSettings.Add_Click({if([System.Windows.Forms.MessageBox]::Show('Reset TapForge settings to their defaults?','TapForge',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes){$themePick.SelectedIndex=0;$appearanceModePick.SelectedIndex=0;$script:globalAccent=[System.Drawing.Color]::FromArgb(123,97,255);foreach($k in $script:pageAccents.Keys){$script:pageAccents[$k]=$script:globalAccent};$intervalUnit.SelectedIndex=0;Set-IntervalMilliseconds 100;$buttonPick.SelectedIndex=0;$modePick.SelectedIndex=0;$limit.Value=100;$speedMode.SelectedIndex=0;$rate.Value=10;$keyPick.SelectedIndex=0;$hotkeyMode.SelectedIndex=0;$keyboardMode.Checked=$false;$doubleClick.Checked=$false;$duty.Value=0;$randomize.Value=0;$cornerStop.Checked=$false;$edgeStop.Checked=$false;$script:alwaysTop.Checked=$false;$script:stopAlert.Checked=$true;$script:strictHotkey.Checked=$false;$script:stopAltTab.Checked=$false;$script:extendedSpeed.Checked=$false;$script:minimizeTray.Checked=$false;$script:rememberPosition.Checked=$true;$script:runOnStartup.Checked=$false;$script:pointDefaultClicks.Value=1;$script:pointDefaultRadius.Value=0;$script:pointsEnabled.Checked=$false;$script:stopWhenPointsDone.Checked=$false;$script:points.Clear();$pointList.Items.Clear();Apply-Theme}})
$script:globalAccent=$script:colorAccent;$script:pageAccents=@{Clicking=$script:colorAccent;Behavior=$script:colorAccent;Appearance=$script:colorAccent;'Click Points'=$script:colorAccent;Keybinds=$script:colorAccent;'Process List'=$script:colorAccent;Presets=$script:colorAccent;Maintenance=$script:colorAccent};$script:appearanceMode='Global';$script:lightTheme=$false;$script:panelOpacity=100
$appearanceCard=New-Card 0 0 830 490; $appearanceCard.Location=[System.Drawing.Point]::new(0,0);$appearancePage.Controls.Add($appearanceCard)
$appearanceCard.Controls.Add((New-Label 'Appearance' 22 18 300 30 17 ([System.Drawing.Color]::White) $true))
$appearanceCard.Controls.Add((New-Label 'Choose a theme and accent hue.' 22 50 600 20 9 $script:colorMuted))
$script:themeSection=New-Card 10 74 810 156;$appearanceCard.Controls.Add($script:themeSection)
$script:iconSection=New-Card 10 238 810 240;$appearanceCard.Controls.Add($script:iconSection)
$appearanceCard.Controls.Add((New-Label 'THEME' 22 88 140 18 8 $script:colorMuted $true))
$themePick=[System.Windows.Forms.ComboBox]::new();$themePick.Location=[System.Drawing.Point]::new(22,110);$themePick.Size=[System.Drawing.Size]::new(220,32);$themePick.DropDownStyle='DropDownList';[void]$themePick.Items.AddRange(@('Dark','Light'));$themePick.SelectedIndex=0;$appearanceCard.Controls.Add($themePick)
$appearanceCard.Controls.Add((New-Label 'APPEARANCE MODE' 280 88 180 18 8 $script:colorMuted $true))
$appearanceModePick=[System.Windows.Forms.ComboBox]::new();$appearanceModePick.Location=[System.Drawing.Point]::new(280,110);$appearanceModePick.Size=[System.Drawing.Size]::new(220,32);$appearanceModePick.DropDownStyle='DropDownList';[void]$appearanceModePick.Items.AddRange(@('Global','Individual page'));$appearanceModePick.SelectedIndex=0;$appearanceCard.Controls.Add($appearanceModePick)
$appearanceCard.Controls.Add((New-Label 'EDIT PAGE' 530 88 180 18 8 $script:colorMuted $true))
$script:accentTarget=[System.Windows.Forms.ComboBox]::new();$script:accentTarget.Location=[System.Drawing.Point]::new(530,110);$script:accentTarget.Size=[System.Drawing.Size]::new(220,32);$script:accentTarget.DropDownStyle='DropDownList';[void]$script:accentTarget.Items.AddRange(@('Clicking','Behavior','Click Points','Appearance','Keybinds','Process List','Presets','Maintenance'));$script:accentTarget.SelectedIndex=0;$appearanceCard.Controls.Add($script:accentTarget)
$appearanceCard.Controls.Add((New-Label 'ACCENT HUE' 22 164 180 18 8 $script:colorMuted $true))
$script:accentSwatch=[System.Windows.Forms.Panel]::new();$script:accentSwatch.Location=[System.Drawing.Point]::new(22,188);$script:accentSwatch.Size=[System.Drawing.Size]::new(52,36);$script:accentSwatch.BackColor=$script:colorAccent;$appearanceCard.Controls.Add($script:accentSwatch)
$script:accentHex=New-Label '#7B61FF' 88 192 110 28 11 ([System.Drawing.Color]::White) $true;$appearanceCard.Controls.Add($script:accentHex)
$script:hueButton=New-Button 'Open hue picker' 280 188 220 36 $script:colorAccent ([System.Drawing.Color]::White);$script:hueButton.Tag='primary';$appearanceCard.Controls.Add($script:hueButton)
$appearanceCard.Controls.Add((New-Label 'TASKBAR ICON' 22 258 180 18 8 $script:colorMuted $true))
$script:activeIcon=[System.Windows.Forms.CheckBox]::new();$script:activeIcon.Text='Show active state in the taskbar icon';$script:activeIcon.Location=[System.Drawing.Point]::new(22,284);$script:activeIcon.Size=[System.Drawing.Size]::new(300,25);$script:activeIcon.Checked=$true;$appearanceCard.Controls.Add($script:activeIcon)
$script:iconTheme=[System.Windows.Forms.ComboBox]::new();$script:iconTheme.Location=[System.Drawing.Point]::new(350,280);$script:iconTheme.Size=[System.Drawing.Size]::new(180,30);$script:iconTheme.DropDownStyle='DropDownList';[void]$script:iconTheme.Items.AddRange(@('Auto','Dark','Light'));$script:iconTheme.SelectedIndex=0;$appearanceCard.Controls.Add($script:iconTheme)
$appearanceCard.Controls.Add((New-Label 'ICON COLOR' 22 334 140 18 8 $script:colorMuted $true))
$script:iconColor=[System.Windows.Forms.ComboBox]::new();$script:iconColor.Location=[System.Drawing.Point]::new(22,358);$script:iconColor.Size=[System.Drawing.Size]::new(220,30);$script:iconColor.DropDownStyle='DropDownList';[void]$script:iconColor.Items.Add('User-provided TapForge logo');$script:iconColor.SelectedIndex=0;$appearanceCard.Controls.Add($script:iconColor)
$script:footerToggle=[System.Windows.Forms.CheckBox]::new();$script:footerToggle.Text='Show status footer';$script:footerToggle.Location=[System.Drawing.Point]::new(22,422);$script:footerToggle.Size=[System.Drawing.Size]::new(250,25);$script:footerToggle.Checked=$true;$appearanceCard.Controls.Add($script:footerToggle)
$script:themeSection.SendToBack();$script:iconSection.SendToBack()
foreach($c in $appearanceCard.Controls){if($c -is [System.Windows.Forms.ComboBox]){$c.BackColor=[System.Drawing.Color]::FromArgb(34,40,57);$c.ForeColor=[System.Drawing.Color]::White;$c.FlatStyle='Flat'}elseif($c -is [System.Windows.Forms.TextBox]){$c.BackColor=[System.Drawing.Color]::FromArgb(34,40,57);$c.ForeColor=[System.Drawing.Color]::White;$c.BorderStyle='FixedSingle'}elseif($c -is [AccentSlider]){$c.BackColor=$script:colorPanel}elseif($c -is [System.Windows.Forms.CheckBox]){$c.BackColor=$script:colorPanel;$c.ForeColor=[System.Drawing.Color]::White}}
function Enable-AccentCombo([System.Windows.Forms.ComboBox]$combo){if($combo.Tag -eq 'accent-drawn') {return};$combo.Tag='accent-drawn';$combo.DrawMode='OwnerDrawFixed';$combo.ItemHeight=24;$combo.FlatStyle='Flat';$combo.Add_DrawItem({param($s,$e)$idx=if($e.Index -ge 0){$e.Index}else{$s.SelectedIndex};$chosen=($e.Index -lt 0) -or (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0);$base=if($script:lightTheme){[System.Drawing.Color]::FromArgb(250,251,253)}else{[System.Drawing.Color]::FromArgb(34,40,57)};$fill=if($chosen){$script:comboAccent}else{Blend-Color $base $script:comboAccent 12};$inkColor=if($script:lightTheme -and !$chosen){[System.Drawing.Color]::FromArgb(28,32,43)}else{[System.Drawing.Color]::White};$brush=[System.Drawing.SolidBrush]::new($fill);$ink=[System.Drawing.SolidBrush]::new($inkColor);$e.Graphics.FillRectangle($brush,$e.Bounds);$brush.Dispose();if($idx -ge 0 -and $idx -lt $s.Items.Count){$e.Graphics.DrawString($s.Items[$idx].ToString(),$s.Font,$ink,$e.Bounds.X+5,$e.Bounds.Y+4)};$ink.Dispose();$e.DrawFocusRectangle()});if(!$script:accentCombos){$script:accentCombos=[System.Collections.Generic.List[System.Windows.Forms.ComboBox]]::new()};$script:accentCombos.Add($combo);$arrow=[AccentArrow]::new();$arrow.Size=[System.Drawing.Size]::new(18,[Math]::Max(20,$combo.Height-2));$arrow.Location=[System.Drawing.Point]::new($combo.Right-19,$combo.Top+1);$combo.Parent.Controls.Add($arrow);$arrow.BringToFront();$script:accentArrows.Add($arrow);$target=$combo;$overlay=$arrow;$arrow.Add_Click({$target.DroppedDown=!$target.DroppedDown}.GetNewClosure());$combo.Add_LocationChanged({$overlay.Location=[System.Drawing.Point]::new($target.Right-19,$target.Top+1)}.GetNewClosure());$combo.Add_SizeChanged({$overlay.Location=[System.Drawing.Point]::new($target.Right-19,$target.Top+1);$overlay.Height=[Math]::Max(20,$target.Height-2)}.GetNewClosure())}
$script:accentCombos=[System.Collections.Generic.List[System.Windows.Forms.ComboBox]]::new();$script:accentArrows=[System.Collections.Generic.List[AccentArrow]]::new();$script:accentSpinners=[System.Collections.Generic.List[AccentSpinner]]::new();$script:accentFrames=[System.Collections.Generic.List[AccentFrameLine]]::new()
function Add-AccentFrame($control){$parent=$control.Parent;$lines=@();$top=[AccentFrameLine]::new();$bottom=[AccentFrameLine]::new();$left=[AccentFrameLine]::new();$right=[AccentFrameLine]::new();foreach($line in @($top,$bottom,$left,$right)){$parent.Controls.Add($line);$line.BringToFront();$script:accentFrames.Add($line);$lines+=,$line};$update={ $top.Location=[System.Drawing.Point]::new($control.Left,$control.Top);$top.Size=[System.Drawing.Size]::new($control.Width,1);$bottom.Location=[System.Drawing.Point]::new($control.Left,$control.Bottom-1);$bottom.Size=[System.Drawing.Size]::new($control.Width,1);$left.Location=[System.Drawing.Point]::new($control.Left,$control.Top+1);$left.Size=[System.Drawing.Size]::new(1,[Math]::Max(1,$control.Height-2));$right.Location=[System.Drawing.Point]::new($control.Right-1,$control.Top+1);$right.Size=[System.Drawing.Size]::new(1,[Math]::Max(1,$control.Height-2))}.GetNewClosure();$control.Add_LocationChanged($update);$control.Add_SizeChanged($update);& $update}
function Add-AccentSpinner([System.Windows.Forms.NumericUpDown]$control){$control.BorderStyle='None';$spinner=[AccentSpinner]::new($control);$spinner.Size=[System.Drawing.Size]::new(18,$control.Height);$spinner.Location=[System.Drawing.Point]::new($control.Right-18,$control.Top);$control.Parent.Controls.Add($spinner);$spinner.BringToFront();$script:accentSpinners.Add($spinner);$target=$control;$overlay=$spinner;$control.Add_LocationChanged({$overlay.Location=[System.Drawing.Point]::new($target.Right-18,$target.Top)}.GetNewClosure());$control.Add_SizeChanged({$overlay.Location=[System.Drawing.Point]::new($target.Right-18,$target.Top);$overlay.Height=$target.Height}.GetNewClosure())}
$pending=[System.Collections.Generic.Stack[System.Windows.Forms.Control]]::new();$pending.Push($form);while($pending.Count -gt 0){$node=$pending.Pop();if($node -is [System.Windows.Forms.ComboBox]){Enable-AccentCombo $node;Add-AccentFrame $node}elseif($node -is [System.Windows.Forms.NumericUpDown]){Add-AccentSpinner $node;Add-AccentFrame $node}elseif($node -is [System.Windows.Forms.TextBox]){$node.BorderStyle='None';Add-AccentFrame $node};foreach($child in $node.Controls){$pending.Push($child)}}
function Blend-Color([System.Drawing.Color]$a,[System.Drawing.Color]$b,[int]$percent){$t=[Math]::Max(0,[Math]::Min(100,$percent))/100.0;[System.Drawing.Color]::FromArgb([int]($a.R*(1-$t)+$b.R*$t),[int]($a.G*(1-$t)+$b.G*$t),[int]($a.B*(1-$t)+$b.B*$t))}
function Enable-DarkChrome([System.Windows.Forms.Form]$window){[ClickNative]::ApplyDarkTitle($window.Handle);$pending=[System.Collections.Generic.Stack[System.Windows.Forms.Control]]::new();$pending.Push($window);while($pending.Count -gt 0){$control=$pending.Pop();foreach($child in $control.Controls){$pending.Push($child)};if($control -is [System.Windows.Forms.ComboBox] -or $control -is [System.Windows.Forms.NumericUpDown] -or $control -is [System.Windows.Forms.ListBox] -or $control -is [System.Windows.Forms.TextBox]){[ClickNative]::ApplyDarkControl($control.Handle)}}}
function Apply-Accent {
    if($script:appearanceMode -eq 'Global'){$script:colorAccent=$script:globalAccent}elseif($script:pageAccents.ContainsKey($script:currentPage)){$script:colorAccent=$script:pageAccents[$script:currentPage]}else{$script:colorAccent=$script:globalAccent}
    if($script:titleAccentLine){$script:titleAccentLine.BackColor=$script:colorAccent}
    $accentPage=$script:accentTarget.SelectedItem.ToString();$displayAccent=if($script:appearanceMode -eq 'Individual page' -and $script:currentPage -eq 'Appearance'){$script:pageAccents[$accentPage]}else{$script:colorAccent};$script:comboAccent=$displayAccent
    [AccentSlider]::AccentColor=$displayAccent;[AccentArrow]::AccentColor=$displayAccent;[AccentSpinner]::AccentColor=$displayAccent;[AccentFrameLine]::OutlineColor=Blend-Color $script:inputColor $displayAccent 42;[TapForgeCard]::BorderColor=Blend-Color $script:colorPanel $displayAccent 25;foreach($arrow in $script:accentArrows){$arrow.Invalidate()};foreach($spinner in $script:accentSpinners){$spinner.Invalidate()};foreach($frame in $script:accentFrames){$frame.Invalidate()}
    foreach($key in $pageButtons.Keys){$pageButtons[$key].BackColor=if($script:currentPage -eq $key){$script:colorAccent}else{Blend-Color $(if($script:lightTheme){[System.Drawing.Color]::FromArgb(224,228,236)}else{[System.Drawing.Color]::FromArgb(34,40,57)}) $displayAccent}}
    foreach($key in $settingButtons.Keys){$settingButtons[$key].BackColor=if($script:currentPage -eq $key){$script:colorAccent}else{Blend-Color $(if($script:lightTheme){[System.Drawing.Color]::FromArgb(224,228,236)}else{[System.Drawing.Color]::FromArgb(34,40,57)}) $displayAccent}}
    $script:accentSwatch.BackColor=$displayAccent;$script:accentHex.Text='#'+$displayAccent.R.ToString('X2')+$displayAccent.G.ToString('X2')+$displayAccent.B.ToString('X2')
    $script:hueButton.BackColor=$displayAccent;$script:hueButton.ForeColor=[System.Drawing.Color]::White
    $startButton.BackColor=if($script:running){Blend-Color $script:pageAccents.Clicking ([System.Drawing.Color]::Black) 22}else{$script:pageAccents.Clicking}
    $pickPoint.BackColor=$displayAccent
    $gearButton.BackColor=if($script:currentPage -eq 'Appearance'){$script:colorAccent}else{if($script:lightTheme){[System.Drawing.Color]::FromArgb(224,228,236)}else{[System.Drawing.Color]::FromArgb(34,40,57)}}
    $script:behaviorScrollThumb.BackColor=$script:colorAccent
    [TapForgeSwitch]::AccentColor=$displayAccent;foreach($toggle in $script:behaviorSwitches){$toggle.Invalidate()}
    $pending=[System.Collections.Generic.Stack[System.Windows.Forms.Control]]::new();$pending.Push($form);while($pending.Count -gt 0){$c=$pending.Pop();foreach($child in $c.Controls){$pending.Push($child)}
        if($c -is [System.Windows.Forms.ComboBox]){$c.BackColor=Blend-Color $script:inputColor $displayAccent 22;$c.Invalidate()}
        elseif($c -is [System.Windows.Forms.TextBox] -or $c -is [System.Windows.Forms.NumericUpDown] -or $c -is [System.Windows.Forms.ListBox]){$c.BackColor=Blend-Color $script:inputColor $displayAccent 12}
        elseif($c -is [System.Windows.Forms.CheckBox]){$c.FlatStyle='Flat';$c.FlatAppearance.BorderColor=$displayAccent;$c.FlatAppearance.CheckedBackColor=$displayAccent;$c.FlatAppearance.MouseOverBackColor=Blend-Color $script:colorPanel $displayAccent 25}
        elseif($c -is [System.Windows.Forms.Button]){if([object]::ReferenceEquals($c,$gearButton)){$c.BackColor=if($script:currentPage -eq 'Appearance'){$script:colorAccent}else{Blend-Color $script:colorPanel $displayAccent 18}}elseif($c.Tag -eq 'chrome'){$c.BackColor=if([object]::ReferenceEquals($c,$script:pinButton) -and $form.TopMost){$script:colorAccent}elseif([object]::ReferenceEquals($c,$script:windowMin) -or [object]::ReferenceEquals($c,$script:windowMax) -or [object]::ReferenceEquals($c,$script:windowClose)){if($script:lightTheme){[System.Drawing.Color]::FromArgb(235,238,244)}else{[System.Drawing.Color]::FromArgb(22,22,22)}}else{Blend-Color $script:colorPanel $displayAccent 18}}elseif($pageButtons.ContainsKey([string]$c.Tag)){$c.BackColor=if($c.Tag -eq $script:currentPage){$script:colorAccent}else{Blend-Color $script:colorPanel $displayAccent 18}}elseif($settingButtons.ContainsKey([string]$c.Tag)){$c.BackColor=if($c.Tag -eq $script:currentPage){$script:colorAccent}else{Blend-Color $script:colorPanel $displayAccent 18}}elseif($c.Tag -eq 'primary'){$c.BackColor=$displayAccent}else{$c.BackColor=Blend-Color $script:colorPanel $displayAccent 22}}
        elseif($c -is [System.Windows.Forms.Panel] -and $c.Tag -eq 'surface'){$c.BackColor=Blend-Color (Blend-Color $script:colorBg $script:colorPanel $script:panelOpacity) $displayAccent 8;if($c -is [TapForgeCard]){$c.Invalidate()}}
        elseif($c -is [AccentSlider]){$c.Invalidate()}
    }
    $pointList.Invalidate();Update-TaskbarIcon
}
$script:behaviorScrollTrack=[System.Windows.Forms.Panel]::new();$script:behaviorScrollTrack.Location=[System.Drawing.Point]::new(0,0);$script:behaviorScrollTrack.Size=[System.Drawing.Size]::new(8,600);$script:behaviorScrollTrack.BackColor=[System.Drawing.Color]::FromArgb(25,29,42);$pageHost.Controls.Add($script:behaviorScrollTrack);$script:behaviorScrollTrack.BringToFront()
$script:behaviorScrollThumb=[System.Windows.Forms.Panel]::new();$script:behaviorScrollThumb.Location=[System.Drawing.Point]::new(1,0);$script:behaviorScrollThumb.Size=[System.Drawing.Size]::new(6,300);$script:behaviorScrollThumb.BackColor=$script:colorAccent;$script:behaviorScrollThumb.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:behaviorScrollTrack.Controls.Add($script:behaviorScrollThumb)
$script:behaviorScrollOffset=0;$script:behaviorScrollDragging=$false;$script:behaviorScrollGrabY=0
function Set-BehaviorScroll([int]$offset){$contentHeight=[Math]::Max($advanced.Height,292+$behaviorExtras.Height);$max=[Math]::Max(0,$contentHeight-$behaviorPage.ClientSize.Height);$script:behaviorScrollOffset=[Math]::Max(0,[Math]::Min($max,$offset));$behaviorPage.SuspendLayout();$advanced.Top=-$script:behaviorScrollOffset;$behaviorExtras.Top=292-$script:behaviorScrollOffset;$behaviorPage.ResumeLayout($false);$trackHeight=[Math]::Max(1,$script:behaviorScrollTrack.Height);$thumbHeight=[Math]::Max(36,[int]($trackHeight*[Math]::Min(1.0,$behaviorPage.ClientSize.Height/[double]$contentHeight)));$script:behaviorScrollThumb.Height=[Math]::Min($trackHeight,$thumbHeight);$travel=[Math]::Max(1,$trackHeight-$script:behaviorScrollThumb.Height);$script:behaviorScrollThumb.Top=if($max -gt 0){[int]($script:behaviorScrollOffset/$max*$travel)}else{0}}
function Add-BehaviorWheel([System.Windows.Forms.Control]$control){$control.Add_MouseWheel({param($s,$e)Set-BehaviorScroll ($script:behaviorScrollOffset-[Math]::Sign($e.Delta)*48)});foreach($child in $control.Controls){Add-BehaviorWheel $child}}
$script:behaviorScrollThumb.Add_MouseDown({param($s,$e)$script:behaviorScrollDragging=$true;$script:behaviorScrollGrabY=$e.Y;$s.Capture=$true})
$script:behaviorScrollThumb.Add_MouseMove({if($script:behaviorScrollDragging){$max=[Math]::Max(0,[Math]::Max($advanced.Height,292+$behaviorExtras.Height)-$behaviorPage.ClientSize.Height);$travel=[Math]::Max(1,$script:behaviorScrollTrack.Height-$script:behaviorScrollThumb.Height);$cursorY=$script:behaviorScrollTrack.PointToClient([System.Windows.Forms.Control]::MousePosition).Y;$top=[Math]::Max(0,[Math]::Min($travel,$cursorY-$script:behaviorScrollGrabY));Set-BehaviorScroll $(if($travel){[int]($top/$travel*$max)}else{0})}})
$script:behaviorScrollThumb.Add_MouseUp({$script:behaviorScrollDragging=$false;$script:behaviorScrollThumb.Capture=$false})
$script:behaviorScrollTrack.Add_MouseDown({param($s,$e)if($e.Y -lt $script:behaviorScrollThumb.Top){Set-BehaviorScroll ($script:behaviorScrollOffset-$behaviorPage.ClientSize.Height)}elseif($e.Y -gt ($script:behaviorScrollThumb.Top+$script:behaviorScrollThumb.Height)){Set-BehaviorScroll ($script:behaviorScrollOffset+$behaviorPage.ClientSize.Height)}})
Add-BehaviorWheel $behaviorPage
function Apply-Theme {
    $script:lightTheme=($themePick.SelectedIndex -eq 1)
    if($script:lightTheme){$script:colorBg=[System.Drawing.Color]::FromArgb(242,244,248);$script:colorPanel=[System.Drawing.Color]::FromArgb(255,255,255);$inputColor=[System.Drawing.Color]::FromArgb(250,251,253);$textColor=[System.Drawing.Color]::FromArgb(28,32,43);$script:colorMuted=[System.Drawing.Color]::FromArgb(94,101,116);[TapForgeCard]::BorderColor=[System.Drawing.Color]::FromArgb(220,224,233)}else{$script:colorBg=[System.Drawing.Color]::FromArgb(15,18,28);$script:colorPanel=[System.Drawing.Color]::FromArgb(24,29,43);$inputColor=[System.Drawing.Color]::FromArgb(34,40,57);$textColor=[System.Drawing.Color]::White;$script:colorMuted=[System.Drawing.Color]::FromArgb(151,161,181);[TapForgeCard]::BorderColor=[System.Drawing.Color]::FromArgb(45,52,69)};$script:inputColor=$inputColor
    $stack=[System.Collections.Generic.Stack[System.Windows.Forms.Control]]::new();$stack.Push($form)
    while($stack.Count -gt 0){$c=$stack.Pop();foreach($child in $c.Controls){$stack.Push($child)}
        if($c -is [System.Windows.Forms.Form]){$c.BackColor=$script:colorBg;$c.ForeColor=$textColor}
        elseif($c -is [System.Windows.Forms.Panel]){if($c.Tag -eq 'surface'){$c.BackColor=Blend-Color $script:colorBg $script:colorPanel $script:panelOpacity}elseif([object]::ReferenceEquals($c,$navBar)){$c.BackColor=if($script:lightTheme){[System.Drawing.Color]::FromArgb(235,238,244)}else{[System.Drawing.Color]::FromArgb(22,22,22)}}elseif([object]::ReferenceEquals($c,$script:titleAccentLine)){$c.BackColor=$script:colorAccent}elseif([object]::ReferenceEquals($c,$settingsBar)){$c.BackColor=$script:colorPanel}elseif([object]::ReferenceEquals($c,$clickPage) -or [object]::ReferenceEquals($c,$behaviorPage) -or [object]::ReferenceEquals($c,$appearancePage)){$c.BackColor=[System.Drawing.Color]::Transparent}else{$c.BackColor=$script:colorBg}}
        elseif($c -is [System.Windows.Forms.Label]){$c.ForeColor=if($c.Tag -eq 'muted'){$script:colorMuted}else{$textColor}}
        elseif($c -is [System.Windows.Forms.ComboBox] -or $c -is [System.Windows.Forms.TextBox] -or $c -is [System.Windows.Forms.NumericUpDown] -or $c -is [System.Windows.Forms.ListBox]){$c.BackColor=$inputColor;$c.ForeColor=$textColor}
        elseif($c -is [TapForgeSwitch]){$c.BackColor=[System.Drawing.Color]::Transparent;$c.ForeColor=$textColor}
        elseif($c -is [System.Windows.Forms.CheckBox]){$c.BackColor=$script:colorPanel;$c.ForeColor=$textColor}
        elseif($c -is [AccentSlider]){$c.BackColor=$script:colorPanel;$c.Invalidate()}
        elseif($c -is [System.Windows.Forms.TrackBar]){$c.BackColor=$script:colorPanel}
        elseif($c -is [System.Windows.Forms.Button]){$c.BackColor=if($c.Tag -eq 'primary'){$script:colorAccent}else{$script:colorPanel};$c.ForeColor=if($c.Tag -eq 'primary'){[System.Drawing.Color]::White}else{$textColor}}
    }
    $pageHost.BackColor=$script:colorBg;$script:behaviorScrollTrack.BackColor=if($script:lightTheme){[System.Drawing.Color]::FromArgb(221,225,233)}else{[System.Drawing.Color]::FromArgb(25,29,42)};$script:behaviorScrollThumb.BackColor=$script:colorAccent;Apply-Accent
}
function Update-TaskbarIcon {
    if(!$script:logoSourceImage){return}
    $newBitmap=[LogoColorizer]::Tint($script:logoSourceImage,$script:colorAccent);$oldBitmap=$script:brandImage;$script:brandImage=$newBitmap
    if($script:brandMark -and !$script:brandMark.IsDisposed){$script:brandMark.Image=$newBitmap}
    $newIcon=[LogoColorizer]::MakeIcon($newBitmap);$oldIcon=$script:logoIcon;$script:logoIcon=$newIcon;$form.Icon=$newIcon
    if($script:trayIcon -and !$script:trayIcon.IsDisposed){$script:trayIcon.Icon=$newIcon}
    if($oldIcon -and ![object]::ReferenceEquals($oldIcon,$newIcon)){$oldIcon.Dispose()}
    if($oldBitmap -and ![object]::ReferenceEquals($oldBitmap,$script:logoSourceImage)){$oldBitmap.Dispose()}
}
$form.Icon=$script:logoIcon
$script:settingsDirectory=Join-Path $env:LOCALAPPDATA 'TapForge';[void](New-Item -ItemType Directory -Force -Path $script:settingsDirectory);$script:windowStateFile=Join-Path $script:settingsDirectory 'window.json';$script:settingsFile=Join-Path $script:settingsDirectory 'settings.json'
if($script:rememberPosition.Checked -and (Test-Path -LiteralPath $script:windowStateFile)){try{$w=Get-Content -LiteralPath $script:windowStateFile -Raw|ConvertFrom-Json;$candidate=[System.Drawing.Rectangle]::new([int]$w.x,[int]$w.y,$form.Width,$form.Height);$visible=$false;foreach($screen in [System.Windows.Forms.Screen]::AllScreens){if($screen.WorkingArea.IntersectsWith($candidate)){$visible=$true}};if($visible){$form.StartPosition='Manual';$form.Location=[System.Drawing.Point]::new([int]$w.x,[int]$w.y)}}catch{}}
$script:footerToggle.Add_CheckedChanged({$script:footerLeft.Visible=$script:footerToggle.Checked;$script:footerRight.Visible=$script:footerToggle.Checked})
$themePick.Add_SelectedIndexChanged({Apply-Theme;Update-TaskbarIcon})
$appearanceModePick.Add_SelectedIndexChanged({$script:appearanceMode=if($appearanceModePick.SelectedIndex -eq 0){'Global'}else{'Individual page'};Apply-Accent})
$script:accentTarget.Add_SelectedIndexChanged({Apply-Accent})
$script:hueButton.Add_Click({$targetPage=if($script:appearanceMode -eq 'Global'){$script:currentPage}else{$script:accentTarget.SelectedItem.ToString()};$picked=Show-HuePicker $script:pageAccents[$targetPage];if($picked){if($script:appearanceMode -eq 'Global'){$script:globalAccent=$picked;foreach($key in $script:pageAccents.Keys){$script:pageAccents[$key]=$picked}}else{$script:pageAccents[$targetPage]=$picked};Apply-Accent;Update-TaskbarIcon}})
$script:activeIcon.Add_CheckedChanged({Update-TaskbarIcon});$script:iconTheme.Add_SelectedIndexChanged({Update-TaskbarIcon});$script:iconColor.Add_SelectedIndexChanged({Update-TaskbarIcon})
$script:compactButton=New-Button 'Compact' 0 6 68 32 ([System.Drawing.Color]::FromArgb(34,40,57)) ([System.Drawing.Color]::White);$script:compactButton.Font=[System.Drawing.Font]::new('Segoe UI',9,[System.Drawing.FontStyle]::Bold);$navBar.Controls.Add($script:compactButton);$script:headerTips.SetToolTip($script:compactButton,'Switch to compact controls')
$compactPanel=New-Card 20 54 850 145;$form.Controls.Add($compactPanel);$compactPanel.Visible=$false
$compactPanel.Controls.Add((New-Label 'QUICK CONTROLS' 18 14 200 22 9 $script:colorMuted $true))
$compactPanel.Controls.Add((New-Label 'Clicks per second' 18 50 140 24 10 ([System.Drawing.Color]::White) $true))
$quickRate=[System.Windows.Forms.NumericUpDown]::new();$quickRate.Location=[System.Drawing.Point]::new(160,46);$quickRate.Size=[System.Drawing.Size]::new(110,32);$quickRate.Minimum=1;$quickRate.Maximum=500;$quickRate.Value=10;$quickRate.BackColor=[System.Drawing.Color]::FromArgb(34,40,57);$quickRate.ForeColor=[System.Drawing.Color]::White;$compactPanel.Controls.Add($quickRate)
$quickHotkey=New-Label 'F6  Start / stop  ·  F7  emergency stop' 300 50 320 28 9 $script:colorMuted;$compactPanel.Controls.Add($quickHotkey)
function Update-HotkeyCaption { $start=$keyPick.SelectedItem.ToString();$emergency=$script:emergencyKey.SelectedItem.ToString();$quickHotkey.Text="$start  Start / stop  ·  $emergency  Emergency stop";$startKeyHint.Text="Current shortcut: $start · works while TapForge is minimized." }
$keyPick.Add_SelectedIndexChanged({if($quickHotkey){Update-HotkeyCaption}});$script:emergencyKey.Add_SelectedIndexChanged({if($quickHotkey){Update-HotkeyCaption}});Update-HotkeyCaption
$quickStart=New-Button '▶  Start' 18 94 300 36 $script:colorAccent ([System.Drawing.Color]::White);$quickStop=New-Button '■  Stop' 336 94 300 36 ([System.Drawing.Color]::FromArgb(48,55,73)) ([System.Drawing.Color]::White);$compactPanel.Controls.AddRange(@($quickStart,$quickStop))
$script:compactButton.Add_Click({if(!$script:compactMode){$script:compactMode=$true;$pageHost.Hide();$settingsBar.Hide();$script:compactButton.Text='Expand';$script:headerTips.SetToolTip($script:compactButton,'Return to full window');$compactPanel.Show();$form.MinimumSize=[System.Drawing.Size]::new(900,260);$form.Size=[System.Drawing.Size]::new(900,260)}else{$script:compactMode=$false;$compactPanel.Hide();$pageHost.Show();$settingsBar.Hide();$script:compactButton.Text='Compact';$script:headerTips.SetToolTip($script:compactButton,'Switch to compact controls');$form.MinimumSize=[System.Drawing.Size]::new(1080,780);$form.Size=[System.Drawing.Size]::new(1080,800)}})
$quickRate.Add_ValueChanged({$speedMode.SelectedIndex=1;$rate.Value=[Math]::Min([decimal]$quickRate.Value,$rate.Maximum)})
$rate.Add_ValueChanged({if($quickRate.Value -ne [decimal]$rate.Value){$quickRate.Value=[Math]::Min([decimal]$rate.Value,$quickRate.Maximum)}})
$quickStart.Add_Click({if($script:running){Stop-Clicking}else{Start-Clicking}});$quickStop.Add_Click({Stop-Clicking})
function Save-UserSettings {
    try {
        $accents=@{};foreach($name in $script:pageAccents.Keys){$c=$script:pageAccents[$name];$accents[$name]='#'+$c.R.ToString('X2')+$c.G.ToString('X2')+$c.B.ToString('X2')}
        $g=$script:globalAccent;$globalHex='#'+$g.R.ToString('X2')+$g.G.ToString('X2')+$g.B.ToString('X2')
        $saved=@{
            intervalMs=(Get-IntervalMilliseconds);intervalUnit=$intervalUnit.SelectedIndex;button=$buttonPick.SelectedIndex;stopMode=$modePick.SelectedIndex;limit=[long]$limit.Value
            speedMode=$speedMode.SelectedIndex;rate=[int]$rate.Value;extendedSpeed=$script:extendedSpeed.Checked;startKey=[string]$keyPick.SelectedItem;emergencyKey=[string]$script:emergencyKey.SelectedItem;hotkeyMode=$hotkeyMode.SelectedIndex
            keyboardMode=$keyboardMode.Checked;keyCode=$keyCodePick.SelectedIndex;doubleClick=$doubleClick.Checked;duty=[int]$duty.Value;randomize=[int]$randomize.Value
            cornerStop=$cornerStop.Checked;cornerSize=[int]$cornerSize.Value;edgeStop=$edgeStop.Checked;edgeSize=[int]$edgeSize.Value
            alwaysTop=$script:alwaysTop.Checked;stopAlert=$script:stopAlert.Checked;strictHotkey=$script:strictHotkey.Checked;stopAltTab=$script:stopAltTab.Checked;minimizeTray=$script:minimizeTray.Checked;rememberPosition=$script:rememberPosition.Checked;runOnStartup=$script:runOnStartup.Checked
            pointDefaultClicks=[int]$script:pointDefaultClicks.Value;pointDefaultRadius=[int]$script:pointDefaultRadius.Value;pointsEnabled=$script:pointsEnabled.Checked;stopWhenPointsDone=$script:stopWhenPointsDone.Checked;points=@($script:points | ForEach-Object {@{x=$_.X;y=$_.Y}})
            filterProcess=$script:filterProcess.Checked;processTitle=$(if($processList.SelectedItem){($processList.SelectedItem.ToString() -replace '  \(PID \d+\)$','')}else{''});theme=$themePick.SelectedIndex;appearanceMode=$appearanceModePick.SelectedIndex;globalAccent=$globalHex;pageAccents=$accents
            activeIcon=$script:activeIcon.Checked;iconTheme=$script:iconTheme.SelectedIndex;iconColor=$script:iconColor.SelectedIndex;footer=$script:footerToggle.Checked;page=$script:currentPage;compact=$script:compactMode
        }
        $tmp=$script:settingsFile+'.tmp';$saved|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $script:settingsFile -Force
    } catch { try { if(Test-Path -LiteralPath ($script:settingsFile+'.tmp')){Remove-Item -LiteralPath ($script:settingsFile+'.tmp') -Force} } catch {} }
}
function Restore-UserSettings {
    if(!(Test-Path -LiteralPath $script:settingsFile)){return}
    try {
        $d=Get-Content -LiteralPath $script:settingsFile -Raw|ConvertFrom-Json
        $script:extendedSpeed.Checked=[bool]$d.extendedSpeed
        if($d.PSObject.Properties['intervalUnit']){$intervalUnit.SelectedIndex=[Math]::Max(0,[Math]::Min(2,[int]$d.intervalUnit))};if($d.PSObject.Properties['intervalMs']){Set-IntervalMilliseconds ([long]$d.intervalMs)}
        $buttonPick.SelectedIndex=[Math]::Max(0,[Math]::Min($buttonPick.Items.Count-1,[int]$d.button));$modePick.SelectedIndex=[Math]::Max(0,[Math]::Min($modePick.Items.Count-1,[int]$d.stopMode));$limit.Value=[Math]::Max($limit.Minimum,[Math]::Min($limit.Maximum,[decimal]$d.limit))
        $speedMode.SelectedIndex=[Math]::Max(0,[Math]::Min(1,[int]$d.speedMode));$rate.Value=[Math]::Max($rate.Minimum,[Math]::Min($rate.Maximum,[decimal]$d.rate));$hotkeyMode.SelectedIndex=[Math]::Max(0,[Math]::Min(1,[int]$d.hotkeyMode))
        if($keyPick.Items.Contains([string]$d.startKey)){$keyPick.SelectedItem=[string]$d.startKey};if($script:emergencyKey.Items.Contains([string]$d.emergencyKey)){$script:emergencyKey.SelectedItem=[string]$d.emergencyKey}
        $keyboardMode.Checked=[bool]$d.keyboardMode;$keyCodePick.SelectedIndex=[Math]::Max(0,[Math]::Min($keyCodePick.Items.Count-1,[int]$d.keyCode));$doubleClick.Checked=[bool]$d.doubleClick
        $duty.Value=[Math]::Max($duty.Minimum,[Math]::Min($duty.Maximum,[decimal]$d.duty));$randomize.Value=[Math]::Max($randomize.Minimum,[Math]::Min($randomize.Maximum,[decimal]$d.randomize))
        $cornerStop.Checked=[bool]$d.cornerStop;$cornerSize.Value=[Math]::Max($cornerSize.Minimum,[Math]::Min($cornerSize.Maximum,[decimal]$d.cornerSize));$edgeStop.Checked=[bool]$d.edgeStop;$edgeSize.Value=[Math]::Max($edgeSize.Minimum,[Math]::Min($edgeSize.Maximum,[decimal]$d.edgeSize))
        $script:alwaysTop.Checked=[bool]$d.alwaysTop;$script:stopAlert.Checked=[bool]$d.stopAlert;$script:strictHotkey.Checked=[bool]$d.strictHotkey;$script:stopAltTab.Checked=[bool]$d.stopAltTab;$script:minimizeTray.Checked=[bool]$d.minimizeTray;$script:rememberPosition.Checked=[bool]$d.rememberPosition;$script:runOnStartup.Checked=[bool]$d.runOnStartup
        if($script:rememberPosition.Checked -and (Test-Path -LiteralPath $script:windowStateFile)){try{$w=Get-Content -LiteralPath $script:windowStateFile -Raw|ConvertFrom-Json;$candidate=[System.Drawing.Rectangle]::new([int]$w.x,[int]$w.y,$form.Width,$form.Height);$visible=$false;foreach($screen in [System.Windows.Forms.Screen]::AllScreens){if($screen.WorkingArea.IntersectsWith($candidate)){$visible=$true}};if($visible){$form.StartPosition='Manual';$form.Location=[System.Drawing.Point]::new([int]$w.x,[int]$w.y)}}catch{}}elseif(!$script:rememberPosition.Checked){$form.StartPosition='CenterScreen'}
        $script:pointDefaultClicks.Value=[Math]::Max($script:pointDefaultClicks.Minimum,[Math]::Min($script:pointDefaultClicks.Maximum,[decimal]$d.pointDefaultClicks));$script:pointDefaultRadius.Value=[Math]::Max($script:pointDefaultRadius.Minimum,[Math]::Min($script:pointDefaultRadius.Maximum,[decimal]$d.pointDefaultRadius));$script:pointsEnabled.Checked=[bool]$d.pointsEnabled;$script:stopWhenPointsDone.Checked=[bool]$d.stopWhenPointsDone
        $script:points.Clear();$pointList.Items.Clear();foreach($p in $d.points){[void]$script:points.Add([System.Drawing.Point]::new([int]$p.x,[int]$p.y));[void]$pointList.Items.Add("Point $($script:points.Count): $($p.x), $($p.y)")}
        $script:filterProcess.Checked=[bool]$d.filterProcess;if($d.processTitle){$refreshProcesses.PerformClick();for($i=0;$i -lt $processList.Items.Count;$i++){if($processList.Items[$i].ToString() -like ([string]$d.processTitle+'  (PID *')){$processList.SelectedIndex=$i;break}}}
        if($d.PSObject.Properties['theme']){$themePick.SelectedIndex=[Math]::Max(0,[Math]::Min(1,[int]$d.theme))};if($d.PSObject.Properties['appearanceMode']){$appearanceModePick.SelectedIndex=[Math]::Max(0,[Math]::Min(1,[int]$d.appearanceMode))}
        if($d.globalAccent){$script:globalAccent=[System.Drawing.ColorTranslator]::FromHtml([string]$d.globalAccent)};if($d.pageAccents){foreach($prop in $d.pageAccents.PSObject.Properties){if($script:pageAccents.ContainsKey($prop.Name)){$script:pageAccents[$prop.Name]=[System.Drawing.ColorTranslator]::FromHtml([string]$prop.Value)}}}
        $script:activeIcon.Checked=[bool]$d.activeIcon;$script:iconTheme.SelectedIndex=[Math]::Max(0,[Math]::Min($script:iconTheme.Items.Count-1,[int]$d.iconTheme));$script:iconColor.SelectedIndex=[Math]::Max(0,[Math]::Min($script:iconColor.Items.Count-1,[int]$d.iconColor));$script:footerToggle.Checked=[bool]$d.footer
        $script:footerLeft.Visible=$script:footerToggle.Checked;$script:footerRight.Visible=$script:footerToggle.Checked
        if($d.compact){$script:compactButton.PerformClick()};if($d.page -and $d.page -in @('Clicking','Behavior','Click Points','Appearance','Keybinds','Process List','Presets','Maintenance')){Show-Page ([string]$d.page)}
        Update-HotkeyCaption;Update-TaskbarIcon
    } catch { }
}
Restore-UserSettings
$form.Add_HandleCreated({Enable-DarkChrome $form});Apply-Theme;Show-Page $(if($script:currentPage){$script:currentPage}else{'Clicking'})

function Stop-Clicking {
    if ($script:clickTimer) { $script:clickTimer.Dispose(); $script:clickTimer=$null }
    [ClickNative]::Stop()
    $script:running=$false
    if (!$form.IsDisposed) { $startButton.Text='▶   Start clicking';$quickStart.Text='▶  Start'; $statusPill.Text='●  READY'; $statusPill.ForeColor=[System.Drawing.Color]::FromArgb(108,220,170);Update-TaskbarIcon;Apply-Accent;if($script:stopReason -and $script:stopAlert.Checked){$script:trayIcon.BalloonTipTitle='TapForge stopped';$script:trayIcon.BalloonTipText=$script:stopReason;$script:trayIcon.Visible=$true;$script:trayIcon.ShowBalloonTip(2500)};$script:stopReason=$null }
}
function Start-Clicking {
    if ($script:running) { return }
    if($script:pointsEnabled.Checked -and $script:points.Count -eq 0){[System.Windows.Forms.MessageBox]::Show('Pick at least one screen location on the Click Points page, or turn click points off.','TapForge');return}
    if($script:filterProcess.Checked){if($processList.SelectedIndex -lt 0 -or $processList.SelectedIndex -ge $script:processIds.Count){[System.Windows.Forms.MessageBox]::Show('Select an application on the Process List page first.','TapForge');return};[ClickNative]::TargetProcessId=$script:processIds[$processList.SelectedIndex]}else{[ClickNative]::TargetProcessId=0}
    $script:running=$true; $script:clickCount=0; $script:stopwatch.Restart();$script:stopReason=$null
    $startButton.Text='●   Clicking…';$quickStart.Text='●  Clicking…'; $startButton.BackColor=[System.Drawing.Color]::FromArgb(82,66,174); $statusPill.Text='●  ACTIVE'; $statusPill.ForeColor=[System.Drawing.Color]::FromArgb(255,196,95);Update-TaskbarIcon
    $modeLabel.Text=@('Continuous','Click count limit','Time limit')[$modePick.SelectedIndex]
    # Store settings in script scope because the timer event runs after this
    # function returns and cannot reliably see its local variables.
    $script:buttonFlags=@(0x0002,0x0008,0x0020); $script:upFlags=@(0x0004,0x0010,0x0040); $script:which=$buttonPick.SelectedIndex
    $every=[int](Get-IntervalMilliseconds); $script:target=[long]$limit.Value; $script:mode=$modePick.SelectedIndex
    $maxClicks=if($script:mode -eq 1){[int]$script:target}else{0}; $maxSeconds=if($script:mode -eq 2){[int]$script:target}else{0}
    if($script:pointsEnabled.Checked -and $script:stopWhenPointsDone.Checked -and $script:points.Count -gt 0){$maxClicks=$script:points.Count*[int]$script:pointDefaultClicks.Value;$maxSeconds=0}
    $vk=@{Space=0x20;Enter=0x0D;A=0x41;F=0x46}[$keyCodePick.SelectedItem.ToString()]
    $pointFlat=[System.Collections.Generic.List[int]]::new(); if($script:pointsEnabled.Checked){foreach($p in $script:points){$pointFlat.Add([int]$p.X);$pointFlat.Add([int]$p.Y)}}
    $script:buttonFlags=@(0x0002,0x0008,0x0020); $script:upFlags=@(0x0004,0x0010,0x0040); $script:which=$buttonPick.SelectedIndex
    $perPoint=if($script:pointsEnabled.Checked){[int]$script:pointDefaultClicks.Value}else{1}
    [ClickNative]::Configure([int]$randomize.Value,[int]$duty.Value,$maxClicks,$maxSeconds,$cornerStop.Checked,[int]$cornerSize.Value,$edgeStop.Checked,[int]$edgeSize.Value,$keyboardMode.Checked,$vk,$doubleClick.Checked,$pointFlat.ToArray(),[int]$script:pointDefaultRadius.Value,$perPoint)
    [ClickNative]::Start([uint32]$script:buttonFlags[$script:which],[uint32]$script:upFlags[$script:which],$every)
    $script:clickTimer=[System.Windows.Forms.Timer]::new(); $script:clickTimer.Interval=50
    $script:clickTimer.Add_Tick({
        $script:clickCount=[ClickNative]::Count
        if (![ClickNative]::Active) { $script:stopReason='A click limit or screen safety stop was reached.'; Stop-Clicking }
        if (!$form.IsDisposed) { $countLabel.Text=$script:clickCount.ToString('N0'); $elapsedLabel.Text=$script:stopwatch.Elapsed.ToString('hh\:mm\:ss') }
    })
    $script:clickTimer.Start()
}
$startButton.Add_Click({ if($script:running){Stop-Clicking}else{Start-Clicking} })
$stopButton.Add_Click({ Stop-Clicking })
$script:trayIcon=[System.Windows.Forms.NotifyIcon]::new();$script:trayIcon.Icon=$script:logoIcon;$script:trayIcon.Text='TapForge';$trayMenu=[System.Windows.Forms.ContextMenuStrip]::new();$trayShow=$trayMenu.Items.Add('Open TapForge');$trayExit=$trayMenu.Items.Add('Exit');$script:trayIcon.ContextMenuStrip=$trayMenu
$script:RestoreFromTray={if($form.Visible -eq $false){$form.Show()};$form.WindowState='Normal';$form.Activate();$script:trayIcon.Visible=$false}
$trayShow.Add_Click({& $script:RestoreFromTray});$trayExit.Add_Click({$script:exitRequested=$true;$script:trayIcon.Visible=$false;$form.Close()});$script:trayIcon.Add_DoubleClick({& $script:RestoreFromTray})
$form.Add_Resize({if($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -and $script:minimizeTray.Checked){$form.Hide();$script:trayIcon.Visible=$true};if($script:windowMax){$script:windowMax.Text=if($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized){'❐'}else{'□'};$script:headerTips.SetToolTip($script:windowMax, $(if($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized){'Restore'}else{'Maximize'}))};if($script:currentPage -and !$script:compactMode -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized){Show-Page $script:currentPage}})
$form.Add_FormClosing({param($s,$e)if($script:rememberPosition.Checked){try{@{x=$form.Location.X;y=$form.Location.Y}|ConvertTo-Json|Set-Content -LiteralPath $script:windowStateFile -Encoding UTF8}catch{}};Save-UserSettings;if($script:minimizeTray.Checked -and !$script:exitRequested -and $e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing){$e.Cancel=$true;$form.Hide();$script:trayIcon.Visible=$true}else{if($script:clickTimer){$script:clickTimer.Stop();$script:clickTimer.Dispose();$script:clickTimer=$null};[ClickNative]::Stop();$script:running=$false;$script:trayIcon.Visible=$false;$script:trayIcon.Dispose()}})

$hotkeyTimer=[System.Windows.Forms.Timer]::new(); $hotkeyTimer.Interval=35
$script:BeginScreenPick={
    $bounds=[System.Windows.Forms.SystemInformation]::VirtualScreen
    $script:pickerOverlay=[System.Windows.Forms.Form]::new();$script:pickerOverlay.FormBorderStyle='None';$script:pickerOverlay.StartPosition='Manual';$script:pickerOverlay.Bounds=$bounds;$script:pickerOverlay.TopMost=$true;$script:pickerOverlay.Opacity=0.14;$script:pickerOverlay.BackColor=[System.Drawing.Color]::Black;$script:pickerOverlay.Cursor=[System.Windows.Forms.Cursors]::Cross;$script:pickerOverlay.ShowInTaskbar=$false;$script:pickerOverlay.KeyPreview=$true
    $script:pointPicker=$true;$script:lastLeft=$false
    [void]$script:pickerOverlay.ShowDialog($form)
    if(!$script:pickerOverlay.IsDisposed){$script:pickerOverlay.Dispose()};$script:pickerOverlay=$null;$script:pointPicker=$false
    $pickPoint.Text='Pick point';$pickPoint.BackColor=$script:colorAccent
}
$pickPoint.Add_Click({$pickPoint.Text='Click a screen location · Esc cancels';$pickPoint.BackColor=[System.Drawing.Color]::FromArgb(82,66,174);& $script:BeginScreenPick})
$removePoint.Add_Click({if($pointList.SelectedIndex -ge 0){$i=$pointList.SelectedIndex;$script:points.RemoveAt($i);$pointList.Items.RemoveAt($i)}})
$hotkeyTimer.Add_Tick({
    $f6code=@{ 'F6'=0x75; 'F8'=0x77; 'F9'=0x78; 'F10'=0x79; 'F11'=0x7A; 'F12'=0x7B }[$keyPick.SelectedItem.ToString()]
    $f6=(([ClickNative]::GetAsyncKeyState($f6code) -band 0x8000) -ne 0)
    $emergencyCode=@{'F7'=0x76;'F8'=0x77;'F9'=0x78;'F10'=0x79;'F11'=0x7A;'F12'=0x7B}[$script:emergencyKey.SelectedItem.ToString()]
    $f7=(([ClickNative]::GetAsyncKeyState($emergencyCode) -band 0x8000) -ne 0)
    $mods=$false;foreach($vk in @(0x10,0x11,0x12,0x5B,0x5C)){if(([ClickNative]::GetAsyncKeyState($vk) -band 0x8000) -ne 0){$mods=$true}}
    $startAllowed=(!$script:strictHotkey.Checked -or !$mods)
    if($script:stopAltTab.Checked -and $script:running -and $mods -and (([ClickNative]::GetAsyncKeyState(0x09) -band 0x8000) -ne 0)){ $script:stopReason='Stopped after switching windows.';Stop-Clicking }
    if($hotkeyMode.SelectedIndex -eq 0){if($f6 -and !$script:lastF6 -and $startAllowed){ if($script:running){Stop-Clicking}else{Start-Clicking} }}
    else {if($f6 -and !$script:running -and $startAllowed){Start-Clicking};if(!$f6 -and $script:running){Stop-Clicking}}
    if($f7 -and !$script:lastF7 -and $script:running){Stop-Clicking}
    $left=(([ClickNative]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0)
    if($script:pointPicker -and (([ClickNative]::GetAsyncKeyState(0x1B) -band 0x8000) -ne 0)){if($script:pickerOverlay -and !$script:pickerOverlay.IsDisposed){$script:pickerOverlay.Close()}}
    if($script:pointPicker -and $left -and !$script:lastLeft){$pt=[ClickNative]::Cursor;[void]$script:points.Add([System.Drawing.Point]::new($pt[0],$pt[1]));[void]$pointList.Items.Add("Point $($script:points.Count): $($pt[0]), $($pt[1])");if($script:pickerOverlay -and !$script:pickerOverlay.IsDisposed){$script:pickerOverlay.Close()}}
    $script:lastLeft=$left
    $script:lastF6=$f6; $script:lastF7=$f7
})
$hotkeyTimer.Start()
$global:TapForgeReady=$true
& $script:checkForTapForgeUpdate $true
[void]$form.ShowDialog()
$hotkeyTimer.Stop(); $hotkeyTimer.Dispose()
$script:brandImage.Dispose();$script:logoSourceImage.Dispose();$script:logoIcon.Dispose()
$null

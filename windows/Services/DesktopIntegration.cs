using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Forms = System.Windows.Forms;

namespace QuickTransfer.Services;

public sealed class DesktopIntegration : IDisposable
{
    private readonly MainWindow window;
    private readonly Forms.NotifyIcon tray;
    private readonly HwndSource source;
    private readonly IntPtr hwnd;

    public DesktopIntegration(MainWindow window, Action exit)
    {
        this.window = window;
        hwnd = new WindowInteropHelper(window).EnsureHandle();
        source = HwndSource.FromHwnd(hwnd)!;
        source.AddHook(WindowMessage);
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("打开", null, (_, _) => Show());
        menu.Items.Add("退出", null, (_, _) => exit());
        using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/quicktransfer.ico"))!.Stream;
        using var icon = new System.Drawing.Icon(stream);
        tray = new Forms.NotifyIcon { Icon = (System.Drawing.Icon)icon.Clone(), Text = "快传", ContextMenuStrip = menu, Visible = true };
        tray.MouseClick += (_, args) => { if (args.Button == Forms.MouseButtons.Left) Show(); };
        if (!RegisterHotKey(hwnd, 1, 0x4003, 'S')) window.Model.Status = "快捷键已被其他程序占用";
    }

    public void Show()
    {
        window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate();
    }

    private IntPtr WindowMessage(IntPtr handle, int message, IntPtr wparam, IntPtr lparam, ref bool handled)
    {
        if (message == 0x0312 && wparam == (IntPtr)1)
        {
            Show();
            _ = window.PasteAsync();
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        UnregisterHotKey(hwnd, 1);
        source.RemoveHook(WindowMessage);
        tray.Visible = false;
        var icon = tray.Icon;
        tray.ContextMenuStrip?.Dispose();
        tray.Dispose();
        icon?.Dispose();
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr hwnd, int id);
}

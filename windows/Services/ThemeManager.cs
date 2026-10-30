using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;

namespace QuickTransfer.Services;

public static class ThemeManager
{
    private static bool dark;
    public static void Initialize()
    {
        Refresh();
        SystemEvents.UserPreferenceChanged += OnPreferenceChanged;
    }

    public static void Dispose() => SystemEvents.UserPreferenceChanged -= OnPreferenceChanged;

    private static void OnPreferenceChanged(object sender, UserPreferenceChangedEventArgs args)
    {
        var app = Application.Current;
        if (app != null && !app.Dispatcher.HasShutdownStarted) app.Dispatcher.BeginInvoke(Refresh);
    }

    private static void Refresh()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            dark = key?.GetValue("AppsUseLightTheme") is int value && value == 0;
        }
        catch (System.Security.SecurityException) { dark = false; }
        Application.Current.Resources.MergedDictionaries[0] = new ResourceDictionary
        { Source = new Uri($"Themes/{(dark ? "Dark" : "Light")}.xaml", UriKind.Relative) };
        foreach (Window window in Application.Current.Windows) ApplyTitleBar(window);
    }

    public static void Attach(Window window) => window.SourceInitialized += (_, _) => ApplyTitleBar(window);

    private static void ApplyTitleBar(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        var enabled = dark ? 1 : 0;
        DwmSetWindowAttribute(hwnd, 20, ref enabled, sizeof(int));
        if (window.TryFindResource("PageBrush") is SolidColorBrush brush)
        {
            var color = brush.Color.R | brush.Color.G << 8 | brush.Color.B << 16;
            DwmSetWindowAttribute(hwnd, 35, ref color, sizeof(int));
        }
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}

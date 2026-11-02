using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace QuickTransfer.Services;

internal static class ShellFileActions
{
    public static void OpenInExplorer(string path)
    {
        path = RequireFile(path);
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
    }

    public static void ShowProperties(Window? owner, string path)
    {
        var info = new ShellExecuteInfo
        {
            Size = Marshal.SizeOf<ShellExecuteInfo>(),
            Mask = 0x0000000C | 0x00000400, // 使用系统右键命令，错误交给界面统一显示。
            Owner = owner == null ? IntPtr.Zero : new WindowInteropHelper(owner).Handle,
            Verb = "properties",
            File = RequireFile(path),
            Show = 1
        };
        if (!ShellExecuteEx(ref info))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法打开文件属性");
    }

    private static string RequireFile(string path)
    {
        path = Path.GetFullPath(path);
        if (!File.Exists(path)) throw new FileNotFoundException("文件已移动或删除：" + Path.GetFileName(path));
        return path;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ShellExecuteInfo
    {
        public int Size;
        public uint Mask;
        public IntPtr Owner;
        public string? Verb;
        public string? File;
        public string? Parameters;
        public string? Directory;
        public int Show;
        public IntPtr Instance;
        public IntPtr ItemIdList;
        public string? Class;
        public IntPtr ClassKey;
        public uint HotKey;
        public IntPtr Icon;
        public IntPtr Process;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShellExecuteEx(ref ShellExecuteInfo info);
}

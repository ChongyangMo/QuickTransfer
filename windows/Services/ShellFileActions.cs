using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using Microsoft.Win32.SafeHandles;

namespace QuickTransfer.Services;

internal static class ShellFileActions
{
    public static void OpenInExplorer(string path)
    {
        path = RequireFile(path);
        Marshal.ThrowExceptionForHR(SHParseDisplayName(path, IntPtr.Zero, out var item, 0, out _));
        try { Marshal.ThrowExceptionForHR(SHOpenFolderAndSelectItems(item, 0, IntPtr.Zero, 0)); }
        finally { Marshal.FreeCoTaskMem(item); }
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

    public static Task MoveToRecycleBinAsync(Window? owner, IReadOnlyList<string> paths)
    {
        var hwnd = owner == null ? IntPtr.Zero : new WindowInteropHelper(owner).Handle;
        var resolved = paths
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(File.Exists)
            .Select(RequireFile)
            .ToArray();
        if (resolved.Length == 0) return Task.CompletedTask;

        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var worker = new Thread(() =>
        {
            var multiPath = string.Join('\0', resolved) + "\0";
            var fromPtr = Marshal.StringToHGlobalUni(multiPath);
            try
            {
                var operation = new ShFileOpStruct
                {
                    Owner = hwnd,
                    Func = 0x0003, // FO_DELETE
                    From = fromPtr,
                    Flags = 0x0004 | 0x0010 | 0x0040 | 0x0400 // FOF_SILENT | FOF_NOCONFIRMATION | FOF_ALLOWUNDO | FOF_NOERRORUI
                };
                var result = SHFileOperation(ref operation);
                if (result != 0)
                    completion.SetException(new IOException($"删除文件失败（错误码 0x{result:X}），文件可能正在被占用"));
                else if (operation.AnyOperationsAborted != 0)
                    completion.SetException(new OperationCanceledException("已取消删除"));
                else
                    completion.SetResult();
            }
            catch (Exception error)
            {
                completion.SetException(error);
            }
            finally
            {
                Marshal.FreeHGlobal(fromPtr);
            }
        })
        { IsBackground = true };
        worker.SetApartmentState(ApartmentState.STA);
        worker.Start();
        return completion.Task;
    }

    private static string RequireFile(string path)
    {
        path = Path.GetFullPath(path);
        if (!File.Exists(path)) throw new FileNotFoundException("文件已移动或删除：" + Path.GetFileName(path));
        // 从文件句柄取得实际路径，兼容应用包对本地数据目录的重定向。
        using var handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        var buffer = new StringBuilder(512);
        while (true)
        {
            var length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "无法获取文件实际路径");
            if (length < buffer.Capacity) break;
            buffer.EnsureCapacity(checked((int)length + 1));
        }
        path = buffer.ToString();
        if (path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) return @"\\" + path[8..];
        return path.StartsWith(@"\\?\", StringComparison.Ordinal) ? path[4..] : path;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ShFileOpStruct
    {
        public IntPtr Owner;
        public uint Func;
        public IntPtr From;
        public IntPtr To;
        public ushort Flags;
        public int AnyOperationsAborted;
        public IntPtr NameMappings;
        public string? ProgressTitle;
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

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperation(ref ShFileOpStruct fileOp);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShellExecuteEx(ref ShellExecuteInfo info);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint count, uint flags);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHParseDisplayName(string name, IntPtr bindContext, out IntPtr item, uint attributes, out uint resultAttributes);

    [DllImport("shell32.dll")]
    private static extern int SHOpenFolderAndSelectItems(IntPtr item, uint count, IntPtr children, uint flags);
}

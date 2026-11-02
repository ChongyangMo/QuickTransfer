using System;
using System.IO;
using System.Runtime.InteropServices;

namespace QuickTransfer.Services;

public static class ReceiveDirectories
{
    private static readonly Lazy<string> defaultDirectory = new(() =>
    {
        var downloads = new Guid("374DE290-123F-4565-9164-39C4925E467B");
        var path = IntPtr.Zero;
        try
        {
            Marshal.ThrowExceptionForHR(SHGetKnownFolderPath(ref downloads, 0, IntPtr.Zero, out path));
            return Path.Combine(Marshal.PtrToStringUni(path)!, "快传");
        }
        finally { Marshal.FreeCoTaskMem(path); }
    });

    public static string DefaultDirectory => defaultDirectory.Value;

    public static string Normalize(string directory)
    {
        directory = directory.Trim();
        if (directory.Length == 0 || !Path.IsPathFullyQualified(directory))
            throw new IOException("请选择有效的保存目录");
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
    }

    public static string EnsureWritable(string directory)
    {
        directory = Normalize(directory);
        Directory.CreateDirectory(directory);
        var probe = Path.Combine(directory, ".quicktransfer-" + Guid.NewGuid().ToString("N") + ".part");
        using (new FileStream(probe, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1, FileOptions.DeleteOnClose)) { }
        return directory;
    }

    [DllImport("shell32.dll")]
    private static extern int SHGetKnownFolderPath(ref Guid folder, uint flags, IntPtr token, out IntPtr path);
}

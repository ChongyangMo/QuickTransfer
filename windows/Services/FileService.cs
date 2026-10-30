using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;
using QuickTransfer.Models;

namespace QuickTransfer.Services;

public sealed class FileService
{
    private readonly SemaphoreSlim imageWorkers = new(2);
    public static bool IsImage(string path) => Path.GetExtension(path).ToLowerInvariant() is
        ".png" or ".jpg" or ".jpeg" or ".bmp" or ".gif" or ".webp" or ".tif" or ".tiff" or ".heic" or ".heif";

    public Task<Attachment[]> ReadFilesAsync(IEnumerable<string> paths) => Task.Run(() =>
        paths.Select(Path.GetFullPath).Distinct(StringComparer.OrdinalIgnoreCase).Select(path =>
        {
            if (!File.Exists(path)) throw new IOException("文件不存在或是文件夹，暂不支持文件夹");
            return ReadAttachment(new FileInfo(path));
        }).ToArray());

    public Task<Attachment[]> ReadReceivedAsync(string root) => Task.Run(() =>
    {
        var directory = Path.Combine(root, "received");
        if (!Directory.Exists(directory)) return Array.Empty<Attachment>();
        return new DirectoryInfo(directory).EnumerateFiles("*", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true })
            .Where(file => file.Extension != ".part").OrderByDescending(file => file.LastWriteTimeUtc).Take(30)
            .Select(ReadAttachment).ToArray();
    });

    private static Attachment ReadAttachment(FileInfo file)
    {
        var image = IsImage(file.FullName);
        double ratio = 1;
        if (image)
        {
            try
            {
                using var stream = file.Open(FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
                var frame = decoder.Frames[0];
                if (frame.PixelHeight > 0) ratio = (double)frame.PixelWidth / frame.PixelHeight;
            }
            catch (Exception error) when (error is IOException or NotSupportedException or ArgumentException or InvalidOperationException or FileFormatException)
            {
                System.Diagnostics.Trace.WriteLine("读取图片尺寸失败：" + error.Message);
            }
        }
        return new Attachment(file.FullName, file.Length, ratio, image);
    }

    public async Task<BitmapSource?> LoadImageAsync(string path, int pixels = 640)
    {
        if (!IsImage(path)) return null;
        await imageWorkers.WaitAsync();
        try
        {
            return await Task.Run(() =>
            {
                using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.DecodePixelWidth = pixels;
                bitmap.StreamSource = stream;
                bitmap.EndInit();
                bitmap.Freeze();
                return bitmap;
            });
        }
        finally { imageWorkers.Release(); }
    }

    public async Task LoadThumbnailAsync(Attachment file)
    {
        if (file.ThumbnailRequested) return;
        file.ThumbnailRequested = true;
        try { file.Thumbnail = await LoadImageAsync(file.Path); }
        catch (Exception error) when (error is IOException or NotSupportedException or ArgumentException or InvalidOperationException or FileFormatException)
        {
            // 无可用解码器时保留文件图标，原文件仍可发送和打开。
            System.Diagnostics.Trace.WriteLine($"生成文件缩略图失败：{error.Message}");
        }
    }
}

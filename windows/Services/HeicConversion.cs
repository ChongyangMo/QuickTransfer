using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using QuickTransfer.Models;

namespace QuickTransfer.Services;

public static class HeicConversion
{
    private static readonly SemaphoreSlim worker = new(1);

    public static bool IsHeic(string path) => Path.GetExtension(path).ToLowerInvariant() is ".heic" or ".heif";

    public static async Task<string> ConvertReceivedAsync(string root, string path, HeicReceiveFormat format)
    {
        if (format == HeicReceiveFormat.Original || !IsHeic(path)) return path;
        if (format is not (HeicReceiveFormat.Jpg or HeicReceiveFormat.Png)) throw new ArgumentOutOfRangeException(nameof(format));
        var received = Path.GetFullPath(Path.Combine(root, "received")) + Path.DirectorySeparatorChar;
        path = Path.GetFullPath(path);
        if (!path.StartsWith(received, StringComparison.OrdinalIgnoreCase)) throw new IOException("只能转换已接收的图片");
        await worker.WaitAsync();
        try { return await Task.Run(() => Convert(root, received, path, format)); }
        finally { worker.Release(); }
    }

    private static string Convert(string root, string received, string path, HeicReceiveFormat format)
    {
        // 转换结果单独放在批次子目录，避免与同批尚未接收完成的 JPG / PNG 重名。
        var directory = Path.Combine(Path.GetDirectoryName(path)!, "converted");
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".part");
        try
        {
            using (var input = File.OpenRead(path))
            {
                var decoder = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat | BitmapCreateOptions.IgnoreColorProfile, BitmapCacheOption.OnLoad);
                var frame = decoder.Frames[0];
                BitmapSource source = Orient(frame);
                source = new FormatConvertedBitmap(source, format == HeicReceiveFormat.Jpg ? PixelFormats.Bgr24 : PixelFormats.Bgra32, null, 0);
                // 保留原色彩配置，避免解码时转为 sRGB 后又附上原配置，造成重复色彩转换。
                BitmapEncoder encoder = format == HeicReceiveFormat.Jpg ? new JpegBitmapEncoder { QualityLevel = 95 } : new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(source, null, null, frame.ColorContexts));
                using var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write);
                encoder.Save(output);
                output.Flush(true);
            }
            File.SetLastWriteTimeUtc(temporary, File.GetLastWriteTimeUtc(path));
            var extension = format == HeicReceiveFormat.Jpg ? ".jpg" : ".png";
            var name = Path.GetFileNameWithoutExtension(path);
            var destination = Path.Combine(directory, name + extension);
            for (var suffix = 2; File.Exists(destination); suffix++)
                destination = Path.Combine(directory, $"{name} ({suffix}){extension}");
            var original = Path.Combine(root, "originals", Path.GetRelativePath(received, path));
            Directory.CreateDirectory(Path.GetDirectoryName(original)!);
            File.Move(temporary, destination);
            try { File.Move(path, original); }
            catch
            {
                File.Delete(destination);
                throw;
            }
            return destination;
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); }
            catch (IOException error) { Trace.WriteLine("清理图片转换临时文件失败：" + error.Message); }
            catch (UnauthorizedAccessException error) { Trace.WriteLine("清理图片转换临时文件失败：" + error.Message); }
        }
    }

    private static BitmapSource Orient(BitmapFrame frame)
    {
        if (frame.Metadata is not BitmapMetadata metadata) return frame;
        foreach (var query in new[] { "System.Photo.Orientation", "/ifd/{ushort=274}", "/app1/ifd/{ushort=274}" })
        {
            object? value;
            try { value = metadata.GetQuery(query); }
            catch (NotSupportedException) { continue; }
            catch (ArgumentException) { continue; }
            if (value == null) continue;
            var matrix = System.Convert.ToUInt16(value) switch
            {
                2 => new Matrix(-1, 0, 0, 1, 0, 0),
                3 => new Matrix(-1, 0, 0, -1, 0, 0),
                4 => new Matrix(1, 0, 0, -1, 0, 0),
                5 => new Matrix(0, 1, 1, 0, 0, 0),
                6 => new Matrix(0, 1, -1, 0, 0, 0),
                7 => new Matrix(0, -1, -1, 0, 0, 0),
                8 => new Matrix(0, -1, 1, 0, 0, 0),
                _ => Matrix.Identity
            };
            return matrix.IsIdentity ? frame : new TransformedBitmap(frame, new MatrixTransform(matrix));
        }
        return frame;
    }
}

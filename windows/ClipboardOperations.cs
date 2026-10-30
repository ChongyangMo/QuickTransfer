using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;

namespace QuickTransfer;

public partial class MainWindow
{
    private async void Paste(object sender, RoutedEventArgs args) => await PasteAsync();

    public async Task PasteAsync()
    {
        try
        {
            // 剪贴板由窗口的 STA 线程读取，图片编码和文件写入交给后台。
            if (Clipboard.ContainsFileDropList())
                await Model.AddFilesAsync(Clipboard.GetFileDropList().Cast<string>().ToArray());
            else if (Clipboard.ContainsImage())
            {
                var image = Clipboard.GetImage();
                if (image == null) return;
                image.Freeze();
                var path = Path.Combine(Model.Settings.Root, "outbox", Guid.NewGuid().ToString("N"), "粘贴图片.png");
                await Task.Run(() =>
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(image));
                    using var stream = File.Create(path);
                    encoder.Save(stream);
                });
                await Model.AddFilesAsync(new[] { path });
            }
            else if (Clipboard.ContainsText()) { Model.Text = Clipboard.GetText(); ShowTextEditor(); }
            else Model.Status = "没有可添加的图片、文件或文字";
        }
        catch (Exception error) { Model.Report(error); }
    }

    private void OnDragOver(object sender, DragEventArgs args)
    {
        args.Effects = args.Data.GetDataPresent(DataFormats.FileDrop) || args.Data.GetDataPresent(DataFormats.UnicodeText)
            ? DragDropEffects.Copy : DragDropEffects.None;
        args.Handled = true;
    }

    private async void OnDrop(object sender, DragEventArgs args)
    {
        args.Handled = true;
        try
        {
            if (args.Data.GetData(DataFormats.FileDrop) is string[] paths) await Model.AddFilesAsync(paths);
            else if (args.Data.GetData(DataFormats.UnicodeText) is string value) { Model.Text = value; ShowTextEditor(); }
        }
        catch (Exception error) { Model.Report(error); }
    }
}

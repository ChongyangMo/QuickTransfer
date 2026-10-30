using System;
using System.Collections.Specialized;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using QuickTransfer.Services;

namespace QuickTransfer.Views;

public sealed class FilePreviewWindow : Window
{
    private readonly Image image = new() { Stretch = Stretch.Uniform };
    private readonly ScaleTransform zoom = new(1, 1);
    private readonly ScrollViewer viewer = new()
    {
        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
        HorizontalContentAlignment = HorizontalAlignment.Center,
        VerticalContentAlignment = VerticalAlignment.Center
    };
    private readonly Border viewport = new() { Padding = new Thickness(16) };
    private readonly string path;
    private Point origin;
    private bool dragging;
    private bool dragArmed;

    private FilePreviewWindow(Window owner, string path)
    {
        this.path = path;
        Owner = owner;
        Title = Path.GetFileName(path);
        Width = 900;
        Height = 650;
        MinWidth = 320;
        MinHeight = 240;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        SetResourceReference(BackgroundProperty, "PageBrush");
        image.LayoutTransform = zoom;
        viewer.Content = image;
        viewport.Child = viewer;
        viewport.SizeChanged += (_, _) => FitImage();
        image.PreviewMouseLeftButtonDown += (_, args) =>
        {
            origin = args.GetPosition(this);
            dragging = false;
            dragArmed = true;
            if (args.ClickCount == 2) { SetZoom(zoom.ScaleX > 1 ? 1 : 2); args.Handled = true; }
        };
        image.MouseMove += DragImage;
        image.PreviewMouseLeftButtonUp += (_, _) => dragArmed = false;
        viewer.PreviewMouseWheel += (_, args) =>
        {
            if (Keyboard.Modifiers != ModifierKeys.Control) return;
            SetZoom(zoom.ScaleX + (args.Delta > 0 ? .25 : -.25));
            args.Handled = true;
        };
        KeyDown += (_, args) => { if (args.Key == Key.Escape) Close(); };
        Content = viewport;
        ThemeManager.Attach(this);
    }

    private void FitImage()
    {
        if (image.Source is not { Width: > 0, Height: > 0 } source) return;
        var width = Math.Max(1, viewport.ActualWidth - viewport.Padding.Left - viewport.Padding.Right);
        var height = Math.Max(1, viewport.ActualHeight - viewport.Padding.Top - viewport.Padding.Bottom);
        var scale = Math.Min(width / source.Width, height / source.Height);
        image.Width = source.Width * scale;
        image.Height = source.Height * scale;
    }

    private void SetZoom(double scale)
    {
        zoom.ScaleX = zoom.ScaleY = Math.Clamp(scale, 1, 6);
        var visibility = zoom.ScaleX > 1 ? ScrollBarVisibility.Auto : ScrollBarVisibility.Disabled;
        viewer.HorizontalScrollBarVisibility = viewer.VerticalScrollBarVisibility = visibility;
        if (zoom.ScaleX == 1)
        {
            viewer.ScrollToHome();
            FitImage();
        }
    }

    public static async Task OpenAsync(Window owner, string path)
    {
        var model = ((MainWindow)Application.Current.MainWindow).Model;
        try
        {
            if (!File.Exists(path)) throw new FileNotFoundException("文件已移动或删除");
            if (!FileService.IsImage(path)) { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); return; }
            var preview = new FilePreviewWindow(owner, path);
            preview.Show();
            try
            {
                var bitmap = await model.FileService.LoadImageAsync(path, 4096);
                if (preview.IsVisible)
                {
                    preview.image.Source = bitmap;
                    preview.FitImage();
                }
            }
            catch
            {
                preview.Close();
                throw;
            }
        }
        catch (Exception error) { model.Report(error); }
    }

    private void DragImage(object sender, MouseEventArgs args)
    {
        if (!dragArmed || args.LeftButton != MouseButtonState.Pressed || dragging) return;
        var point = args.GetPosition(this);
        if (Math.Abs(point.X - origin.X) < SystemParameters.MinimumHorizontalDragDistance && Math.Abs(point.Y - origin.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        dragging = true;
        dragArmed = false;
        try
        {
            var data = new DataObject();
            data.SetFileDropList(new StringCollection { path });
            DragDrop.DoDragDrop(image, data, DragDropEffects.Copy);
        }
        catch (Exception error) { ((MainWindow)Application.Current.MainWindow).Model.Report(error); }
    }
}

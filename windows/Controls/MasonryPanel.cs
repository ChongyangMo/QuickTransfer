using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace QuickTransfer.Controls;

public sealed class MasonryPanel : VirtualizingPanel, IScrollInfo
{
    public static readonly DependencyProperty TargetWidthProperty = DependencyProperty.Register(nameof(TargetWidth), typeof(double), typeof(MasonryPanel), new FrameworkPropertyMetadata(220d * 2 / 3, FrameworkPropertyMetadataOptions.AffectsMeasure, LayoutChanged));
    public static readonly DependencyProperty CompactProperty = DependencyProperty.Register(nameof(Compact), typeof(bool), typeof(MasonryPanel), new FrameworkPropertyMetadata(false, FrameworkPropertyMetadataOptions.AffectsMeasure, LayoutChanged));
    public double TargetWidth { get => (double)GetValue(TargetWidthProperty); set => SetValue(TargetWidthProperty, value); }
    public bool Compact { get => (bool)GetValue(CompactProperty); set => SetValue(CompactProperty, value); }
    private Rect[] bounds = Array.Empty<Rect>();
    private bool dirty = true;
    private double layoutWidth;
    private Size viewport, extent;
    private double offset;

    private static void LayoutChanged(DependencyObject owner, DependencyPropertyChangedEventArgs args) => ((MasonryPanel)owner).dirty = true;

    // 使用完整布局命中，框选滚出视口的图片时无需生成额外容器。
    internal IEnumerable<int> ItemsInSelection(Rect selection)
    {
        for (var index = 0; index < bounds.Length; index++)
            if (bounds[index].IntersectsWith(selection)) yield return index;
    }

    protected override Size MeasureOverride(Size available)
    {
        var owner = ItemsControl.GetItemsOwner(this);
        if (owner == null) return default;
        var width = double.IsInfinity(available.Width) ? Math.Max(ActualWidth, 320) : Math.Max(1, available.Width);
        var height = double.IsInfinity(available.Height) ? 480 : Math.Max(0, available.Height);
        viewport = new Size(width, height);
        if (dirty || Math.Abs(layoutWidth - width) > .5 || bounds.Length != owner.Items.Count)
        {
            var layout = MasonryLayout.Calculate(owner.Items, width, TargetWidth, 10, Compact);
            bounds = layout.Bounds;
            extent = new Size(width, layout.Height);
            layoutWidth = width;
            dirty = false;
        }
        offset = Math.Clamp(offset, 0, Math.Max(0, extent.Height - viewport.Height));
        ScrollOwner?.InvalidateScrollInfo();
        var generator = ItemContainerGenerator;
        var cacheTop = offset - height / 2;
        var cacheBottom = offset + height * 1.5;
        for (var child = InternalChildren.Count - 1; child >= 0; child--)
        {
            var index = generator.IndexFromGeneratorPosition(new GeneratorPosition(child, 0));
            if (index >= 0 && index < bounds.Length && bounds[index].Bottom >= cacheTop && bounds[index].Top <= cacheBottom) continue;
            var position = new GeneratorPosition(child, 0);
            if (generator is IRecyclingItemContainerGenerator recycling) recycling.Recycle(position, 1);
            else generator.Remove(position, 1);
            RemoveInternalChildRange(child, 1);
        }
        for (var index = 0; index < bounds.Length; index++)
        {
            var rect = bounds[index];
            if (rect.Bottom < cacheTop || rect.Top > cacheBottom) continue;
            var position = generator.GeneratorPositionFromIndex(index);
            var childIndex = position.Offset == 0 ? position.Index : position.Index + 1;
            using (generator.StartAt(position, GeneratorDirection.Forward, true))
            {
                var element = (UIElement)generator.GenerateNext(out var generated);
                if (generated)
                {
                    if (childIndex >= InternalChildren.Count) AddInternalChild(element);
                    else InsertInternalChild(childIndex, element);
                    generator.PrepareItemContainer(element);
                }
                element.Measure(rect.Size);
            }
        }
        return viewport;
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        for (var child = 0; child < InternalChildren.Count; child++)
        {
            var index = ItemContainerGenerator.IndexFromGeneratorPosition(new GeneratorPosition(child, 0));
            if (index < 0 || index >= bounds.Length) continue;
            var rect = bounds[index];
            rect.Offset(0, -offset);
            InternalChildren[child].Arrange(rect);
        }
        return finalSize;
    }

    protected override void OnItemsChanged(object sender, ItemsChangedEventArgs args)
    {
        base.OnItemsChanged(sender, args);
        // 时间标题增删后重新生成可见容器，避免旧图片与新位置错配；选中状态由列表保留。
        ItemContainerGenerator.RemoveAll();
        RemoveInternalChildRange(0, InternalChildren.Count);
        dirty = true;
        InvalidateMeasure();
    }

    public bool CanHorizontallyScroll { get; set; }
    public bool CanVerticallyScroll { get; set; }
    public double ExtentWidth => extent.Width;
    public double ExtentHeight => extent.Height;
    public double ViewportWidth => viewport.Width;
    public double ViewportHeight => viewport.Height;
    public double HorizontalOffset => 0;
    public double VerticalOffset => offset;
    public ScrollViewer? ScrollOwner { get; set; }
    public void SetHorizontalOffset(double value) { }
    public void SetVerticalOffset(double value)
    {
        var next = Math.Clamp(value, 0, Math.Max(0, ExtentHeight - ViewportHeight));
        if (Math.Abs(next - offset) < .01) return;
        offset = next;
        ScrollOwner?.InvalidateScrollInfo();
        InvalidateMeasure();
    }
    public void LineUp() => SetVerticalOffset(offset - 40);
    public void LineDown() => SetVerticalOffset(offset + 40);
    public void PageUp() => SetVerticalOffset(offset - viewport.Height * .9);
    public void PageDown() => SetVerticalOffset(offset + viewport.Height * .9);
    public void MouseWheelUp() => SetVerticalOffset(offset - WheelDistance);
    public void MouseWheelDown() => SetVerticalOffset(offset + WheelDistance);
    private double WheelDistance => SystemParameters.WheelScrollLines < 0 ? viewport.Height : Math.Max(1, SystemParameters.WheelScrollLines) * 40;
    public void LineLeft() { }
    public void LineRight() { }
    public void PageLeft() { }
    public void PageRight() { }
    public void MouseWheelLeft() { }
    public void MouseWheelRight() { }

    public Rect MakeVisible(Visual visual, Rect rectangle)
    {
        DependencyObject child = visual;
        while (VisualTreeHelper.GetParent(child) is DependencyObject parent && parent != this) child = parent;
        var position = child is UIElement element ? InternalChildren.IndexOf(element) : -1;
        if (position < 0) return Rect.Empty;
        var index = ItemContainerGenerator.IndexFromGeneratorPosition(new GeneratorPosition(position, 0));
        if (index < 0 || index >= bounds.Length) return Rect.Empty;
        var rect = bounds[index];
        if (rect.Top < offset) SetVerticalOffset(rect.Top);
        else if (rect.Bottom > offset + viewport.Height) SetVerticalOffset(rect.Bottom - viewport.Height);
        rect.Offset(0, -offset);
        return Rect.Intersect(rect, new Rect(viewport));
    }
}

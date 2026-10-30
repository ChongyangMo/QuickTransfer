using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;

namespace QuickTransfer.Controls;

internal sealed class SelectionAdorner(UIElement owner) : Adorner(owner)
{
    public Rect Selection { get; set; }

    protected override void OnRender(DrawingContext context)
    {
        var accent = (Brush)((FrameworkElement)AdornedElement).FindResource("AccentBrush");
        context.PushClip(new RectangleGeometry(new Rect(AdornedElement.RenderSize)));
        context.PushOpacity(.15);
        context.DrawRectangle(accent, null, Selection);
        context.Pop();
        context.DrawRectangle(null, new Pen(accent, 1), Selection);
        context.Pop();
    }
}

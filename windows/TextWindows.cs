using System.Windows;
using QuickTransfer.Views;

namespace QuickTransfer;

public partial class MainWindow
{
    private TextComposeWindow? textEditor;

    private void OpenTextEditor(object sender, RoutedEventArgs args) => ShowTextEditor();

    private void ShowTextEditor()
    {
        if (textEditor == null)
        {
            textEditor = new TextComposeWindow(this);
            textEditor.Closed += (_, _) => textEditor = null;
        }
        textEditor.Show();
        if (textEditor.WindowState == WindowState.Minimized) textEditor.WindowState = WindowState.Normal;
        textEditor.Activate();
        textEditor.FocusEditor();
    }

    private void ShowReceivedText(string alias, string text)
    {
        if (((App)Application.Current).Exiting) return;
        var window = new ReceivedTextWindow(this, alias, text);
        window.Show();
        window.Activate();
    }
}

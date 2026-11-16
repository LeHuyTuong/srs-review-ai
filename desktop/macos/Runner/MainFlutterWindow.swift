import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // The stock template takes whatever frame `MainMenu.xib` happens to carry
    // and never constrains it, so the app opened at an arbitrary size and could
    // be dragged down to a sliver where the 228px rail plus a content column no
    // longer fit. A `window_manager`-style plugin is not an option: the app
    // must keep compiling for web, so `dart:io` and every desktop-window
    // package are off the table. AppKit is the honest place for this — a few
    // lines, no dependency, and the window server enforces the minimum instead
    // of a Dart rebuild having to.
    //
    // These are FRAME sizes (including the 28pt title bar), which is what
    // `NSWindow.minSize` measures — the same quantity Windows'
    // WM_GETMINMAXINFO measures, so both platforms agree by construction.
    let initialSize = NSSize(width: 1280, height: 860)
    self.minSize = NSSize(width: 960, height: 680)

    // Window size AND POSITION persistence (P1-5, macOS half).
    //
    // One line, because AppKit owns the whole feature: naming the frame makes
    // the window server write it to the app's preferences on every resize and
    // move, and restore it on the next launch. Nothing in Dart has to run, so
    // nothing here can desync from the widget tree.
    //
    // The name is set BEFORE the frame so a stored one wins: `setFrameUsingName`
    // returns false exactly when there is nothing stored — the first launch, or
    // a wiped preference domain — which is precisely when the P0 default frame
    // below should apply. Reversing these two lines would make the stored frame
    // dead code, since `setFrame` would overwrite it immediately.
    //
    // Windows is NOT covered: persisting a `WINDOWPLACEMENT` means C++ in
    // `windows/runner/`, which cannot be compiled or run on this machine while
    // CI's `desktop-verify` job is a real gate. See
    // docs/desktop/P1-DESKTOP-POLISH-2026-09-12.md.
    self.contentViewController = flutterViewController
    self.setFrameAutosaveName("MainWindow")
    if !self.setFrameUsingName("MainWindow") {
      // `setFrame` uses a zero origin and `center()` does the placement: it
      // accounts for the visible frame of the screen the window lands on, which
      // a hand-computed rect does not.
      self.setFrame(NSRect(origin: .zero, size: initialSize), display: true)
      self.center()
    }
    self.title = "SRS Review AI"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

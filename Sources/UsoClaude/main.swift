import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// App comum: aparece no Dock e no Command-Tab.
app.setActivationPolicy(.regular)
app.run()

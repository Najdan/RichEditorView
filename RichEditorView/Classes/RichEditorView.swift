//  RichEditor.swift
//
//  Created by Caesar Wirth on 4/1/15.
//  Copyright (c) 2015 Caesar Wirth. All rights reserved.
//

import UIKit
import WebKit

/// The value we hold in order to be able to set the line height before the JS completely loads.
private let DefaultInnerLineHeight: Int = 21

/// RichEditorView is a UIView that displays richly styled text, and allows it to be edited in a WYSIWYG fashion.
@objcMembers open class RichEditorView: UIView, UIScrollViewDelegate, WKNavigationDelegate, UIGestureRecognizerDelegate {
    /// The delegate that will receive callbacks when certain actions are completed.
    open weak var delegate: RichEditorDelegate?

    /// Input accessory view to display over they keyboard.
    /// Defaults to nil
    open override var inputAccessoryView: UIView? {
        get { return webView.accessoryView }
        set { webView.accessoryView = newValue }
    }

    /// The internal WKWebView that is used to display the text.
    open private(set) lazy var webView: RichEditorWebView = {
        guard let scriptPath = Bundle(for: RichEditorView.self).path(forResource: "rich_editor", ofType: "js"),
            let script = try? String(contentsOfFile: scriptPath, encoding: String.Encoding.utf8)
        else { fatalError("Unable to find javscript/html for rich text editor") }

        let configuration = WKWebViewConfiguration()

        configuration.userContentController.addUserScript(
            WKUserScript(source: script,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true
            )
        )

        ["windowSizeDidChange"].forEach {
            configuration.userContentController.add(WeakScriptMessageHandler(delegate: self), name: $0)
        }

        let webView = RichEditorWebView(frame: .zero, configuration: configuration)
        // configure webview
        webView.frame = bounds
        webView.keyboardDisplayRequiresUserAction = false
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.configuration.dataDetectorTypes = WKDataDetectorTypes()
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = false
        webView.scrollView.delegate = self
        webView.scrollView.clipsToBounds = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        return webView
    }()

    /// Whether or not scroll is enabled on the view.
    open var isScrollEnabled: Bool = true {
        didSet {
            webView.setScrollEnabled(enabled: isScrollEnabled)
        }
    }

    /// Whether or not to allow user input in the view.
    open var editingEnabled: Bool = false {
        didSet { contentEditable = editingEnabled }
    }

    /// The content HTML of the text being displayed.
    /// Is continually updated as the text is being edited.
    open private(set) var contentHTML: String = "" {
        didSet {
            delegate?.richEditor(self, contentDidChange: contentHTML)
        }
    }

    /// The internal height of the text being displayed.
    /// Is continually being updated as the text is edited.
    open private(set) var editorHeight: CGFloat = 0 {
        didSet {
            if editorHeight != oldValue {
                delegate?.richEditor(self, heightDidChange: editorHeight)
            }
        }
    }

    /// If content width (horizontal scroll) is wider than width of frame then content will be scalled
    private var scale: CGFloat = 1.0

    /// The line height of the editor. Defaults to 21.
    open private(set) var lineHeight: Int = DefaultInnerLineHeight {
        didSet {
            runJS("RE.setLineHeight('\(lineHeight)px')")
        }
    }

    /// Whether or not the editor has finished loading or not yet.
    private var isEditorLoaded = false

    /// Value that stores whether or not the content should be editable when the editor is loaded.
    /// Is basically `isEditingEnabled` before the editor is loaded.
    private var editingEnabledVar = true

    /// The HTML that is currently loaded in the editor view, if it is loaded. If it has not been loaded yet, it is the
    /// HTML that will be loaded into the editor view once it finishes initializing.
    public var html: String = "" {
        didSet {
            setHTML(html)
        }
    }

    /// Private variable that holds the placeholder text, so you can set the placeholder before the editor loads.
    private var placeholderText: String = ""
    /// The placeholder text that should be shown when there is no user input.
    open var placeholder: String {
        get { return placeholderText }
        set {
            placeholderText = newValue
            if isEditorLoaded {
                runJS("RE.setPlaceholderText('\(newValue.escaped)')")
            }
        }
    }

    // MARK: Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup() {
        addSubview(webView)

        if let filePath = Bundle(for: RichEditorView.self).path(forResource: "rich_editor", ofType: "html") {
            let url = URL(fileURLWithPath: filePath, isDirectory: false)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    // MARK: - Rich Text Editing

    open func isEditingEnabled(handler: @escaping (Bool) -> Void) {
        isContentEditable(handler: handler)
    }

    private func getLineHeight(handler: @escaping (Int) -> Void) {
        if isEditorLoaded {
            runJS("RE.getLineHeight()") { r in
                if let r = Int(r) {
                    handler(r)
                } else {
                    handler(DefaultInnerLineHeight)
                }
            }
        } else {
            handler(DefaultInnerLineHeight)
        }
    }

    private func setHTML(_ value: String) {
        if isEditorLoaded {
            runJS("RE.setHtml('\(value.escaped)')")
        }
    }

    /// The inner height of the editor div.
    /// Fetches it from JS every time, so might be slow!
    private func getClientHeight(handler: @escaping (Int) -> Void) {
        runJS("document.getElementById('re-editor').clientHeight") { r in
            if let r = Int(r) {
                handler(r)
            } else {
                handler(0)
            }
        }
    }

    public func getHtml(handler: @escaping (String) -> Void) {
        runJS("RE.getHtml()") { r in
            handler(r)
        }
    }

    /// Text representation of the data that has been input into the editor view, if it has been loaded.
    public func getText(handler: @escaping (String) -> Void) {
        runJS("RE.getText()") { r in
            handler(r)
        }
    }

    /// The href of the current selection, if the current selection's parent is an anchor tag.
    /// Will be nil if there is no href, or it is an empty string.
    public func getSelectedHref(handler: @escaping (String?) -> Void) {
        hasRangeSelection(handler: { r in
            if !r {
                handler(nil)
                return
            }
            self.runJS("RE.getSelectedHref()") { r in
                if r == "" {
                    handler(nil)
                } else {
                    handler(r)
                }
            }
        })
    }

    /// Whether or not the selection has a type specifically of "Range".
    public func hasRangeSelection(handler: @escaping (Bool) -> Void) {
        runJS("RE.rangeSelectionExists()") { r in
            handler(r == "true" ? true : false)
        }
    }

    /// Whether or not the selection has a type specifically of "Range" or "Caret".
    public func hasRangeOrCaretSelection(handler: @escaping (Bool) -> Void) {
        runJS("RE.rangeOrCaretSelectionExists()") { r in
            handler(r == "true" ? true : false)
        }
    }

    // MARK: Methods

    public func removeFormat() {
        runJS("RE.removeFormat()")
    }

    public func setFontSize(_ size: Int) {
        runJS("RE.setFontSize('\(size)px')")
    }

    public var editorBackgroundColor: UIColor = .white {
        didSet {
            if isEditorLoaded {
                _setEditorBackgroundColor(editorBackgroundColor)
            }
        }
    }

    private func _setEditorBackgroundColor(_ color: UIColor) {
        runJS("RE.setBackgroundColor('\(editorBackgroundColor.hex)')")
    }

    public func undo() {
        runJS("RE.undo()")
    }

    public func redo() {
        runJS("RE.redo()")
    }

    private var isBoldActive = false
    public func bold() {
        isBoldActive.toggle()
        delegate?.richEditor(self, mode: .bold, isActive: isBoldActive)
        runJS("RE.setBold()")
    }

    private var isItalicActive = false
    public func italic() {
        isItalicActive.toggle()
        delegate?.richEditor(self, mode: .italic, isActive: isItalicActive)
        runJS("RE.setItalic()")
    }

    // "superscript" is a keyword
    public func subscriptText() {
        runJS("RE.setSubscript()")
    }

    public func superscript() {
        runJS("RE.setSuperscript()")
    }

    public func strikethrough() {
        runJS("RE.setStrikeThrough()")
    }

    public func underline() {
        runJS("RE.setUnderline()")
    }

    public func setTextColor(_ color: UIColor) {
        runJS("RE.prepareInsert()")
        runJS("RE.setTextColor('\(color.hex)')")
    }

    public var editorFontColor: UIColor = .black {
        didSet {
            if isEditorLoaded {
                _setEditorFontColor(editorFontColor)
            }
        }
    }

    private func _setEditorFontColor(_ color: UIColor) {
        runJS("RE.setBaseTextColor('\(color.hex)')")
    }

    public func setTextBackgroundColor(_ color: UIColor) {
        runJS("RE.prepareInsert()")
        runJS("RE.setTextBackgroundColor('\(color.hex)')")
    }

    public func header(_ h: Int) {
        runJS("RE.setHeading('\(h)')")
    }

    public func indent() {
        runJS("RE.setIndent()")
    }

    public func outdent() {
        runJS("RE.setOutdent()")
    }

    public func orderedList() {
        runJS("RE.setOrderedList()")
    }

    public func unorderedList() {
        runJS("RE.setUnorderedList()")
    }

    public func blockquote() {
        runJS("RE.setBlockquote()");
    }

    public func alignLeft() {
        runJS("RE.setJustifyLeft()")
    }

    public func alignCenter() {
        runJS("RE.setJustifyCenter()")
    }

    public func alignRight() {
        runJS("RE.setJustifyRight()")
    }

    public func insertImage(_ url: String, alt: String) {
        runJS("RE.prepareInsert()")
        runJS("RE.insertImage('\(url.escaped)', '\(alt.escaped)')")
    }

    public func insertLink(_ href: String, title: String) {
        runJS("RE.prepareInsert()")
        runJS("RE.insertLink('\(href.escaped)', '\(title.escaped)')")
    }

    private var shouldFocus: Bool = false

    public func focus() {
        shouldFocus = true
        runJS("RE.focus()")
    }

    public func focus(at: CGPoint) {
        runJS("RE.focusAtPoint(\(at.x), \(at.y))")
    }

    public func blur() {
        runJS("RE.blurFocus()")
    }

    /// Runs some JavaScript on the WKWebView and returns the result
    /// If there is no result, returns an empty string
    /// - parameter js: The JavaScript string to be run
    /// - returns: The result of the JavaScript that was run
    public func runJS(_ js: String, handler: ((String) -> Void)? = nil) {
        webView.evaluateJavaScript(js) { (result, error) in
            if let error = error {
                print("WKWebViewJavascriptBridge Error: \(String(describing: error)) - JS: \(js)")
                handler?("")
                return
            }

            guard let handler = handler else {
                return
            }

            if let resultInt = result as? Int {
                handler("\(resultInt)")
                return
            }

            if let resultBool = result as? Bool {
                handler(resultBool ? "true" : "false")
                return
            }

            if let resultStr = result as? String {
                handler(resultStr)
                return
            }

            // no result
            handler("")
        }
    }

    // MARK: - Delegate Methods

    // MARK: UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // We use this to keep the scroll view from changing its offset when the keyboard comes up
        if !isScrollEnabled {
            scrollView.bounds = webView.bounds
        }
    }

    // MARK: WKWebViewDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // empy
        _setEditorFontColor(editorFontColor)
        _setEditorBackgroundColor(editorBackgroundColor)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Handle pre-defined editor actions
        let callbackPrefix = "re-callback://"
        if navigationAction.request.url?.absoluteString.hasPrefix(callbackPrefix) == true {
            // When we get a callback, we need to fetch the command queue to run the commands
            // It comes in as a JSON array of commands that we need to parse
            runJS("RE.getCommandQueue()") { commands in
                if let data = commands.data(using: .utf8) {

                    let jsonCommands: [String]
                    do {
                        jsonCommands = try JSONSerialization.jsonObject(with: data) as? [String] ?? []
                    } catch {
                        jsonCommands = []
                        NSLog("RichEditorView: Failed to parse JSON Commands")
                    }

                    jsonCommands.forEach(self.performCommand)
                }
            }
            return decisionHandler(WKNavigationActionPolicy.cancel);
        }

        // User is tapping on a link, so we should react accordingly
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url {
                if delegate?.richEditor(self, shouldInteractWith: url) ?? false {
                    return decisionHandler(WKNavigationActionPolicy.allow);
                } else {
                    return decisionHandler(WKNavigationActionPolicy.cancel)
                }
            }
        }

        return decisionHandler(WKNavigationActionPolicy.allow);
    }

    // MARK: UIGestureRecognizerDelegate

    /// Delegate method for our UITapGestureDelegate.
    /// Since the internal web view also has gesture recognizers, we have to make sure that we actually receive our taps.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    // MARK: - Private Implementation Details

    private var contentEditable: Bool = false {
        didSet {
            editingEnabledVar = contentEditable
            if isEditorLoaded {
                let value = (contentEditable ? "true" : "false")
                runJS("RE.editor.contentEditable = \(value)")
            }
        }
    }
    private func isContentEditable(handler: @escaping (Bool) -> Void) {
        if isEditorLoaded {
            // to get the "editable" value is a different property, than to disable it
            // https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/contentEditable
            runJS("RE.editor.isContentEditable") { value in
                self.editingEnabledVar = Bool(value) ?? false
            }
        }
    }

    /// The position of the caret relative to the currently shown content.
    /// For example, if the cursor is directly at the top of what is visible, it will return 0.
    /// This also means that it will be negative if it is above what is currently visible.
    /// Can also return 0 if some sort of error occurs between JS and here.
    private func relativeCaretYPosition(handler: @escaping (Int) -> Void) {
        runJS("RE.getRelativeCaretYPosition()") { r in
            handler(Int(r) ?? 0)
        }
    }

    func update(html: String, withScale scale: CGFloat) -> String {
        guard let body = html.slice(from: "<body", to: ">") else {
            return html
        }

        if body.contains("style=") {
            let styleString = body.replacingOccurrences(of: "style=\"", with: "style=\"position: fixed; top: 0px; left: 0px; transform: scale(\(scale)); transform-origin: 0% 0%; ")
            return html.replacingOccurrences(of: body, with: styleString)
        } else {
            return html.replacingOccurrences(of: "<body", with: "<body style=\" position: fixed; top: 0px; left: 0px; transform: scale(\(scale)); transform-origin: 0% 0%;\"")
        }
    }

    /// Scrolls the editor to a position where the caret is visible.
    /// Called repeatedly to make sure the caret is always visible when inputting text.
    /// Works only if the `lineHeight` of the editor is available.
    private func scrollCaretToVisible() {
        let scrollView = self.webView.scrollView

        getClientHeight(handler: { clientHeight in
            let contentHeight = clientHeight > 0 ? CGFloat(clientHeight) : scrollView.frame.height
            scrollView.contentSize = CGSize(width: scrollView.frame.width, height: contentHeight)

            // XXX: Maybe find a better way to get the cursor height
            self.getLineHeight(handler: { lh in
                let lineHeight = CGFloat(lh)
                let cursorHeight = lineHeight - 4
                self.relativeCaretYPosition(handler: { r in
                    let visiblePosition = CGFloat(r)
                    var offset: CGPoint?

                    if visiblePosition + cursorHeight > scrollView.bounds.size.height {
                        // Visible caret position goes further than our bounds
                        offset = CGPoint(x: 0, y: (visiblePosition + lineHeight) - scrollView.bounds.height + scrollView.contentOffset.y)
                    } else if visiblePosition < 0 {
                        // Visible caret position is above what is currently visible
                        var amount = scrollView.contentOffset.y + visiblePosition
                        amount = amount < 0 ? 0 : amount
                        offset = CGPoint(x: scrollView.contentOffset.x, y: amount)
                    }

                    if let offset = offset {
                        scrollView.setContentOffset(offset, animated: true)
                    }
                })
            })
        })
    }

    /// Called when actions are received from JavaScript
    /// - parameter method: String with the name of the method and optional parameters that were passed in
    private func performCommand(_ method: String) {
        if method.hasPrefix("ready") {
            // If loading for the first time, we have to set the content HTML to be displayed
            if !isEditorLoaded {
                isEditorLoaded = true
                if shouldFocus {
                    focus()
                }
                setHTML(html)
                contentHTML = html
                contentEditable = editingEnabledVar
                placeholder = placeholderText
                lineHeight = DefaultInnerLineHeight
                delegate?.richEditorDidLoad(self)
            }
        }
        else if method.hasPrefix("input") {
            scrollCaretToVisible()
            runJS("RE.getHtml()") { content in
                self.contentHTML = content
            }
        }
        else if method.hasPrefix("focus") {
            delegate?.richEditorTookFocus(self)
        }
        else if method.hasPrefix("blur") {
            delegate?.richEditorLostFocus(self)
        }
        else if method.hasPrefix("action/") {
            runJS("RE.getHtml()") { content in
                self.contentHTML = content

                // If there are any custom actions being called
                // We need to tell the delegate about it
                let actionPrefix = "action/"
                let range = method.range(of: actionPrefix)!
                let action = method.replacingCharacters(in: range, with: "")

                self.delegate?.richEditor(self, handle: action)
            }
        }
    }

    // MARK: - Responder Handling

    override open func becomeFirstResponder() -> Bool {
        if !webView.isFirstResponder {
            focus()
            return true
        } else {
            return false
        }
    }

    open override func resignFirstResponder() -> Bool {
        blur()
        return true
    }

}

extension RichEditorView: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "windowSizeDidChange":
            guard let data = message.body as? [String: CGFloat],
                let width = data["width"],
                let height = data["height"] else { return }

            let newScale = self.frame.width / width
            if newScale != self.scale {
                self.scale = newScale
                self.runJS("document.documentElement.outerHTML") {
                    self.webView.loadHTMLString(self.update(html: $0, withScale: self.scale), baseURL: nil)
                }
            }

            let scaledHeight = height * self.scale
            if self.editorHeight != scaledHeight || self.editorHeight == 0 {
                self.editorHeight = scaledHeight
            }
        default:
            break
        }
    }
}

typealias OldClosureType =  @convention(c) (Any, Selector, UnsafeRawPointer, Bool, Bool, Any?) -> Void
typealias NewClosureType =  @convention(c) (Any, Selector, UnsafeRawPointer, Bool, Bool, Bool, Any?) -> Void

extension WKWebView {
    var keyboardDisplayRequiresUserAction: Bool? {
        get {
            return self.keyboardDisplayRequiresUserAction
        }
        set {
            self.setKeyboardRequiresUserInteraction(newValue ?? true)
        }
    }

    func setKeyboardRequiresUserInteraction( _ value: Bool) {
        guard let WKContentView: AnyClass = NSClassFromString("WKContentView") else {
            print("keyboardDisplayRequiresUserAction extension: Cannot find the WKContentView class")
            return
        }
        // For iOS 10, *
        let sel_10: Selector = sel_getUid("_startAssistingNode:userIsInteracting:blurPreviousNode:userObject:")
        // For iOS 11.3, *
        let sel_11_3: Selector = sel_getUid("_startAssistingNode:userIsInteracting:blurPreviousNode:changingActivityState:userObject:")
        // For iOS 12.2, *
        let sel_12_2: Selector = sel_getUid("_elementDidFocus:userIsInteracting:blurPreviousNode:changingActivityState:userObject:")
        // For iOS 13.0, *
        let sel_13_0: Selector = sel_getUid("_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:")

        if let method = class_getInstanceMethod(WKContentView, sel_10) {
            let originalImp: IMP = method_getImplementation(method)
            let original: OldClosureType = unsafeBitCast(originalImp, to: OldClosureType.self)
            let block : @convention(block) (Any, UnsafeRawPointer, Bool, Bool, Any?) -> Void = { (me, arg0, arg1, arg2, arg3) in
                original(me, sel_10, arg0, !value, arg2, arg3)
            }
            let imp: IMP = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
        }

        if let method = class_getInstanceMethod(WKContentView, sel_11_3) {
            let originalImp: IMP = method_getImplementation(method)
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let block : @convention(block) (Any, UnsafeRawPointer, Bool, Bool, Bool, Any?) -> Void = { (me, arg0, arg1, arg2, arg3, arg4) in
                original(me, sel_11_3, arg0, !value, arg2, arg3, arg4)
            }
            let imp: IMP = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
        }

        if let method = class_getInstanceMethod(WKContentView, sel_12_2) {
            let originalImp: IMP = method_getImplementation(method)
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let block : @convention(block) (Any, UnsafeRawPointer, Bool, Bool, Bool, Any?) -> Void = { (me, arg0, arg1, arg2, arg3, arg4) in
                original(me, sel_12_2, arg0, !value, arg2, arg3, arg4)
            }
            let imp: IMP = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
        }

        if let method = class_getInstanceMethod(WKContentView, sel_13_0) {
            let originalImp: IMP = method_getImplementation(method)
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let block : @convention(block) (Any, UnsafeRawPointer, Bool, Bool, Bool, Any?) -> Void = { (me, arg0, arg1, arg2, arg3, arg4) in
                original(me, sel_13_0, arg0, !value, arg2, arg3, arg4)
            }
            let imp: IMP = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
        }
    }
}

extension WKWebView {

  func setScrollEnabled(enabled: Bool) {
    self.scrollView.isScrollEnabled = enabled
    self.scrollView.panGestureRecognizer.isEnabled = enabled
    self.scrollView.bounces = enabled

    for subview in self.subviews {
        if let subview = subview as? UIScrollView {
            subview.isScrollEnabled = enabled
            subview.bounces = enabled
            subview.panGestureRecognizer.isEnabled = enabled
        }

        for subScrollView in subview.subviews {
            if type(of: subScrollView) == NSClassFromString("WKContentView")! {
                for gesture in subScrollView.gestureRecognizers! {
                    subScrollView.removeGestureRecognizer(gesture)
                }
            }
        }
    }
  }
}

extension String {
    func slice(from: String, to: String) -> String? {
        return (range(of: from)?.upperBound).flatMap { substringFrom in
            (range(of: to, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }
}

fileprivate class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        self.delegate?.userContentController(userContentController, didReceive: message)
    }
}

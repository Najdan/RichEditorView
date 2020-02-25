//
//  RichEditorDelegate.swift
//  RichEditorView
//
//  Created by Najdan Tomic on 25/02/2020.
//

import Foundation

/// RichEditorDelegate defines callbacks for the delegate of the RichEditorView
public protocol RichEditorDelegate: class {
    /// Called when the inner height of the text being displayed changes
    /// Can be used to update the UI
    func richEditor(_ editor: RichEditorView, heightDidChange height: Int)

    /// Called whenever the content inside the view changes
    func richEditor(_ editor: RichEditorView, contentDidChange content: String)

    /// Called when the rich editor starts editing
    func richEditorTookFocus(_ editor: RichEditorView)

    /// Called when the rich editor stops editing or loses focus
    func richEditorLostFocus(_ editor: RichEditorView)

    /// Called when the RichEditorView has become ready to receive input
    /// More concretely, is called when the internal WKWebView loads for the first time, and contentHTML is set
    func richEditorDidLoad(_ editor: RichEditorView)

    /// Called when the internal WKWebView begins loading a URL that it does not know how to respond to
    /// For example, if there is an external link, and then the user taps it
    func richEditor(_ editor: RichEditorView, shouldInteractWith url: URL) -> Bool

    /// Called when custom actions are called by callbacks in the JS
    /// By default, this method is not used unless called by some custom JS that you add
    func richEditor(_ editor: RichEditorView, handle action: String)

    /// Called when text formatting input mode changes
    func richEditor(_ editor: RichEditorView, mode: RichEditorDefaultOption, isActive: Bool)
}

public extension RichEditorDelegate {

    func richEditor(_ editor: RichEditorView, heightDidChange height: Int) { }

    func richEditor(_ editor: RichEditorView, contentDidChange content: String) { }

    func richEditorTookFocus(_ editor: RichEditorView) { }

    func richEditorLostFocus(_ editor: RichEditorView) { }

    func richEditorDidLoad(_ editor: RichEditorView) { }

    func richEditor(_ editor: RichEditorView, shouldInteractWith url: URL) -> Bool { return true }

    func richEditor(_ editor: RichEditorView, handle action: String) { }

    func richEditor(_ editor: RichEditorView, mode: RichEditorDefaultOption, isActive: Bool) { }
}

//
// WKKeyboard.swift
// RichEditorView	
//
// Created by Najdan Tomic on 09/05/2020.
//

import Foundation
import WebKit

class WKKeyboard: NSObject {
    static var keyboardStyle: UIKeyboardAppearance = .default

    @objc func keyboardAppearance() -> UIKeyboardAppearance {
        return WKKeyboard.keyboardStyle
    }

    class func setStyle(with style: UIKeyboardAppearance, on webView: WKWebView) {
        for view in webView.scrollView.subviews {
            if view.self.description.contains("WKContent") {
                let content = view
                var className: String? = nil
                if let superclass = content.self.superclass {
                    className = "\(superclass)_\(type(of: self))"
                }
                var newClass: AnyClass? = NSClassFromString(className ?? "")
                if newClass == nil {
                    newClass = objc_allocateClassPair(object_getClass(content), className ?? "", 0)
                    if let method = class_getInstanceMethod(WKKeyboard.self, #selector(self.keyboardAppearance)) {
                        class_addMethod(newClass, #selector(self.keyboardAppearance), method_getImplementation(method), method_getTypeEncoding(method))
                        objc_registerClassPair(newClass!)
                    }
                }
                object_setClass(content, newClass!)
                keyboardStyle = style
                return
            }
        }
    }
}
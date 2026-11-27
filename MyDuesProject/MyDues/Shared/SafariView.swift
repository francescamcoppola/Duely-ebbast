//
//  SafariView.swift
//  MyDues
//
//  Shows a web page inside the app (Safari's own view controller): used to look at a service's
//  plans without leaving MyDues. Pages where the user must be signed in (cancelling) open in
//  Safari instead, where their sign-ins are.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    /// Presents `page` in an in-app Safari sheet while it's set.
    func safariSheet(_ page: Binding<WebPage?>) -> some View {
        sheet(item: page) { page in
            SafariView(url: page.url)
                .ignoresSafeArea()
        }
    }
}

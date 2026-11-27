//
//  SharedColor.swift
//  MyDues (app, widgets)
//
//  Subscription colors by name, so the widgets can draw them from the snapshot.
//

import SwiftUI

nonisolated enum SharedColor {
    static func color(named name: String) -> Color {
        switch name {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        default: .gray
        }
    }
}

import SwiftUI

enum Tokens {
    enum Color {
        static let bg = SwiftUI.Color(nsColor: .windowBackgroundColor)
        static let surface = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let surfaceRaised = SwiftUI.Color(nsColor: .textBackgroundColor)
        static let border = SwiftUI.Color(nsColor: .separatorColor)
        static let text = SwiftUI.Color(nsColor: .labelColor)
        static let textDim = SwiftUI.Color(nsColor: .secondaryLabelColor)
        static let textFaint = SwiftUI.Color(nsColor: .tertiaryLabelColor)
        static let accent = SwiftUI.Color.primary
        static let ok = SwiftUI.Color(red: 0.20, green: 0.62, blue: 0.30)
        static let warn = SwiftUI.Color(red: 0.82, green: 0.55, blue: 0.10)
        static let err = SwiftUI.Color(red: 0.78, green: 0.24, blue: 0.24)
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let xl: CGFloat = 32
    }

    enum Font {
        static let display = SwiftUI.Font.system(size: 22, weight: .semibold, design: .default)
        static let title = SwiftUI.Font.system(size: 16, weight: .semibold, design: .default)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular, design: .default)
        static let mono = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
    }
}

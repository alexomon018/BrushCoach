import SwiftUI

struct ToothShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.1))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.31),
            control1: CGPoint(x: rect.width * 0.34, y: rect.height * 0.01),
            control2: CGPoint(x: rect.width * 0.12, y: rect.height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.29, y: rect.height * 0.91),
            control1: CGPoint(x: rect.width * 0.1, y: rect.height * 0.58),
            control2: CGPoint(x: rect.width * 0.19, y: rect.height * 0.92)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.65),
            control1: CGPoint(x: rect.width * 0.38, y: rect.height * 0.91),
            control2: CGPoint(x: rect.width * 0.38, y: rect.height * 0.69)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.71, y: rect.height * 0.91),
            control1: CGPoint(x: rect.width * 0.62, y: rect.height * 0.69),
            control2: CGPoint(x: rect.width * 0.62, y: rect.height * 0.91)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.31),
            control1: CGPoint(x: rect.width * 0.81, y: rect.height * 0.92),
            control2: CGPoint(x: rect.width * 0.9, y: rect.height * 0.58)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.1),
            control1: CGPoint(x: rect.width * 0.88, y: rect.height * 0.08),
            control2: CGPoint(x: rect.width * 0.66, y: rect.height * 0.01)
        )
        path.closeSubpath()
        return path
    }
}

struct RinseCupShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.width * 0.18, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.height * 1.04)
            )
            path.closeSubpath()
        }
    }
}

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.18))
            path.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.height * 0.68))
            path.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control: CGPoint(x: rect.width * 0.73, y: rect.height * 0.88)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.width * 0.14, y: rect.height * 0.68),
                control: CGPoint(x: rect.width * 0.27, y: rect.height * 0.88)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.18))
            path.closeSubpath()
        }
    }
}

struct NightcapShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.05, y: rect.height * 0.73))
            path.addQuadCurve(
                to: CGPoint(x: rect.width * 0.89, y: rect.height * 0.09),
                control: CGPoint(x: rect.width * 0.47, y: -rect.height * 0.09)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.91),
                control: CGPoint(x: rect.width * 0.87, y: rect.height * 0.55)
            )
            path.closeSubpath()
        }
    }
}

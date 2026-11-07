import FentonActivityModel
import SwiftUI

/// The severity mark behind a problem's glyph. Severity is never colour alone (HIG, Color; WCAG 1.4.1): a stopped problem
/// (critical, red) is an octagon, like a stop sign, and one that carries on (warning, amber) is a rounded triangle.
/// The file keeps its name from when both were circles.
struct SeverityCircle: View {
    let glyph: ActivityGlyph
    let severity: ActivityProblem.Severity
    var diameter: CGFloat

    var body: some View {
        SeverityShape(severity: severity)
            .fill(ActivityStyle.severity(severity).circle)
            .dimsWhenAlwaysOn()
            .frame(width: diameter, height: diameter)
            .overlay {
                ActivityGlyphImage(glyph: glyph, size: diameter * (severity == .critical ? 0.46 : 0.38), color: .white, weight: .bold)
                    // A triangle's visual centre sits below its box's centre.
                    .offset(y: severity == .critical ? 0 : diameter * 0.09)
            }
            .accessibilityHidden(true)
    }
}

/// The outline for a severity: a regular octagon (critical) or a triangle with rounded corners (warning).
struct SeverityShape: Shape {
    let severity: ActivityProblem.Severity

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = side / 2
        switch severity {
        case .critical:
            // Flat top: vertices at 22.5 degrees plus multiples of 45.
            var path = Path()
            for index in 0..<8 {
                let angle = (Double(index) * 45 + 22.5) * .pi / 180
                let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            return path
        case .warning:
            let corner = side * 0.12
            let top = CGPoint(x: center.x, y: rect.minY + side * 0.06)
            let left = CGPoint(x: rect.minX + side * 0.02, y: rect.maxY - side * 0.1)
            let right = CGPoint(x: rect.maxX - side * 0.02, y: rect.maxY - side * 0.1)
            var path = Path()
            path.move(to: CGPoint(x: (top.x + left.x) / 2, y: (top.y + left.y) / 2))
            path.addArc(tangent1End: left, tangent2End: right, radius: corner)
            path.addArc(tangent1End: right, tangent2End: top, radius: corner)
            path.addArc(tangent1End: top, tangent2End: left, radius: corner)
            path.closeSubpath()
            return path
        }
    }
}

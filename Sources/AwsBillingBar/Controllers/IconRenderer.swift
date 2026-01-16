import AppKit
import AwsBillingBarCore

/// Renders the menu bar icon with cost indicator
enum IconRenderer {
    private static let iconSize = NSSize(width: 22, height: 22)

    /// Render the menu bar icon
    static func renderIcon(
        aggregated: AggregatedBilling,
        isRefreshing: Bool,
        hasError: Bool
    ) -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { rect in
            // Draw AWS logo stylized icon
            drawAWSIcon(in: rect, hasError: hasError, isRefreshing: isRefreshing)

            // Draw cost indicator bar if we have data
            if !aggregated.snapshots.isEmpty {
                drawCostIndicator(in: rect, aggregated: aggregated)
            }

            return true
        }

        image.isTemplate = !hasError && aggregated.snapshots.isEmpty
        return image
    }

    private static func drawAWSIcon(in rect: NSRect, hasError: Bool, isRefreshing: Bool) {
        let iconRect = NSRect(x: 2, y: 6, width: 18, height: 12)

        // Draw AWS "smile" arc
        let smilePath = NSBezierPath()
        let centerX = iconRect.midX
        let bottomY = iconRect.minY + 2

        smilePath.move(to: NSPoint(x: iconRect.minX + 2, y: bottomY + 4))
        smilePath.curve(
            to: NSPoint(x: iconRect.maxX - 2, y: bottomY + 4),
            controlPoint1: NSPoint(x: centerX - 4, y: bottomY - 2),
            controlPoint2: NSPoint(x: centerX + 4, y: bottomY - 2)
        )

        let color: NSColor
        if hasError {
            color = .systemRed
        } else if isRefreshing {
            color = .systemOrange.withAlphaComponent(0.6)
        } else {
            color = .labelColor
        }

        color.setStroke()
        smilePath.lineWidth = 1.5
        smilePath.stroke()

        // Draw dollar sign
        let dollarRect = NSRect(x: centerX - 4, y: iconRect.midY, width: 8, height: 8)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        "$".draw(in: dollarRect, withAttributes: attributes)
    }

    private static func drawCostIndicator(in rect: NSRect, aggregated: AggregatedBilling) {
        // Draw a small bar at the bottom showing relative spend
        let barRect = NSRect(x: 3, y: 2, width: 16, height: 3)

        // Background
        NSColor.tertiaryLabelColor.withAlphaComponent(0.3).setFill()
        let bgPath = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
        bgPath.fill()

        // Calculate fill based on month progress vs spend
        let calendar = Calendar.current
        let today = Date()
        let dayOfMonth = calendar.component(.day, from: today)
        let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        let monthProgress = Double(dayOfMonth) / Double(daysInMonth)

        // If we have last month data, compare against it
        var spendRatio: Double = 0.5
        if aggregated.totalLastMonth > 0 {
            spendRatio = aggregated.totalMonthToDate / aggregated.totalLastMonth
        }

        // Color based on spending pace
        let fillColor: NSColor
        if spendRatio > monthProgress * 1.2 {
            // Spending faster than expected
            fillColor = .systemRed
        } else if spendRatio > monthProgress * 0.9 {
            // On track
            fillColor = .systemOrange
        } else {
            // Under budget
            fillColor = .systemGreen
        }

        // Fill bar
        let fillWidth = min(barRect.width * CGFloat(min(spendRatio, 1.0)), barRect.width)
        let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height)

        fillColor.setFill()
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5)
        fillPath.fill()
    }
}

import SwiftUI

/// Standard top-of-screen header. Eyebrow tag + big italic display title.
struct ScreenTitle: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(eyebrow)
                .font(Font.Soma.sectionTag)
                .tracking(3)
                .foregroundStyle(Color.inkSoft)

            Text(title)
                .font(Font.Soma.dayLine)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }
}

struct SectionHeader: View {
    let text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            InkRule(style: .wavy, color: Color.rule, weight: Theme.Stroke.hairline + 0.4)
                .frame(width: 60)
            Text(text)
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
            Spacer()
        }
    }
}

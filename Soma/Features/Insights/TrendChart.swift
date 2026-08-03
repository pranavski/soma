import Charts
import SwiftUI

/// One quiet line — the last 30 days of the body, drawn in bay (the
/// body-data color job). Weight if any readings exist, otherwise sleep
/// hours. No goal lines, no targets, no bands: the chart shows what
/// happened and stops there.
struct TrendChart: View {
    @StateObject private var vm = TrendChartViewModel()

    var body: some View {
        Group {
            // A line needs at least two points to say anything honest.
            if vm.points.count >= 2 {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text("THE BODY, LATELY")
                            .font(Font.Soma.sectionTag)
                            .tracking(2)
                            .foregroundStyle(Color.inkSoft)
                        Text("·")
                            .font(Font.Soma.sectionTag)
                            .foregroundStyle(Color.inkSoft)
                        Text("LAST 30 DAYS")
                            .font(Font.Soma.sectionTag)
                            .tracking(2)
                            .foregroundStyle(Color.inkSoft)
                        Spacer()
                    }

                    chart

                    Text(vm.metric.aside)
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                }
                .padding(Theme.Spacing.l)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                        .fill(Color.paperRaised.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                                .stroke(Color.rule.opacity(0.5), lineWidth: Theme.Stroke.hairline)
                        )
                )
            }
        }
        .task { await vm.load() }
    }

    private var chart: some View {
        Chart(vm.points) { point in
            LineMark(
                x: .value("day", point.day, unit: .day),
                y: .value(vm.metric.eyebrow, point.value)
            )
            .foregroundStyle(Color.bay)
            .lineStyle(StrokeStyle(lineWidth: Theme.Stroke.nib, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)

            if point.day == vm.points.last?.day {
                PointMark(
                    x: .value("day", point.day, unit: .day),
                    y: .value(vm.metric.eyebrow, point.value)
                )
                .foregroundStyle(Color.bay)
                .symbolSize(28)
            }
        }
        .chartYScale(domain: vm.yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 10)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Font.Soma.caloric)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                    .foregroundStyle(Color.cardLine.opacity(0.5))
                AxisValueLabel()
                    .font(Font.Soma.caloric)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .frame(height: 130)
    }
}

// MARK: - View model

@MainActor
final class TrendChartViewModel: ObservableObject {
    struct Point: Identifiable {
        var id: Date { day }
        let day: Date
        let value: Double
    }

    enum Metric {
        case weight, sleep

        var eyebrow: String {
            switch self {
            case .weight: return "weight"
            case .sleep:  return "sleep"
            }
        }

        /// Handwritten aside under the line — descriptive, never a target.
        var aside: String {
            switch self {
            case .weight: return "weight, as it came in — no target drawn."
            case .sleep:  return "hours slept, roughly — no target drawn."
            }
        }
    }

    @Published private(set) var points: [Point] = []
    @Published private(set) var metric: Metric = .sleep

    private let repository: HealthDaysRepository

    init(repository: HealthDaysRepository = HealthDaysRepository()) {
        self.repository = repository
        #if DEBUG
        if ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1" {
            metric = .weight
            points = Self.sampleWeights()
        }
        #endif
    }

    /// Padded y-range so the line breathes instead of hugging an edge.
    /// A raw 0-based axis would turn a 1 kg drift into a flat line —
    /// or a cliff — depending on the metric's magnitude.
    var yDomain: ClosedRange<Double> {
        guard let lo = points.map(\.value).min(),
              let hi = points.map(\.value).max() else { return 0...1 }
        let pad = Swift.max((hi - lo) * 0.25, 0.5)
        return (lo - pad)...(hi + pad)
    }

    func load() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1" { return }
        #endif
        do {
            let days = try await repository.fetchLastDays(30)

            let weights = days
                .compactMap { day in day.weightKg.map { Point(day: day.day, value: $0) } }
                .sorted { $0.day < $1.day }
            if !weights.isEmpty {
                metric = .weight
                points = weights
                return
            }

            metric = .sleep
            points = days
                .compactMap { day in
                    day.sleepMinutes.map { Point(day: day.day, value: Double($0) / 60.0) }
                }
                .sorted { $0.day < $1.day }
        } catch {
            // The chart is a garnish on the feed — if the body data won't
            // load, it disappears rather than surfacing an error of its own.
            points = []
        }
    }

    #if DEBUG
    private static func sampleWeights() -> [Point] {
        let cal = Calendar.current
        return (0..<30).compactMap { offset -> Point? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            // Gentle drift + wobble; a believable month, nothing dramatic.
            let drift = Double(offset) * 0.02
            let wobble = sin(Double(offset) * 0.9) * 0.25
            return Point(day: day, value: 71.4 + drift + wobble)
        }
        .sorted { $0.day < $1.day }
    }
    #endif
}

#Preview {
    ZStack {
        PaperBackground()
        TrendChart()
            .padding(Theme.Spacing.xl)
    }
}

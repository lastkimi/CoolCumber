import Foundation

/// Reduces interleaved chart data without letting a global stride alias onto a
/// single series. The returned elements retain their original ordering.
public enum SeriesDownsamplingPolicy {
    public static func evenlySpaced<Element, SeriesID: Hashable>(
        _ elements: [Element],
        maximumCount: Int,
        seriesID: (Element) -> SeriesID
    ) -> [Element] {
        guard maximumCount > 0, !elements.isEmpty else { return [] }
        guard elements.count > maximumCount else { return elements }

        var orderedSeries: [SeriesID] = []
        var indicesBySeries: [SeriesID: [Int]] = [:]
        for (index, element) in elements.enumerated() {
            let id = seriesID(element)
            if indicesBySeries[id] == nil {
                orderedSeries.append(id)
                indicesBySeries[id] = []
            }
            indicesBySeries[id, default: []].append(index)
        }

        guard !orderedSeries.isEmpty else { return [] }
        let representedSeriesCount = min(orderedSeries.count, maximumCount)
        let baseBudget = maximumCount / representedSeriesCount
        let remainder = maximumCount % representedSeriesCount
        var selectedIndices: [Int] = []

        for (seriesIndex, id) in orderedSeries.prefix(representedSeriesCount).enumerated() {
            guard let indices = indicesBySeries[id] else { continue }
            let budget = min(indices.count, baseBudget + (seriesIndex < remainder ? 1 : 0))
            selectedIndices.append(contentsOf: evenlySpaced(indices, count: budget))
        }

        selectedIndices.sort()
        return selectedIndices.map { elements[$0] }
    }

    private static func evenlySpaced(_ indices: [Int], count: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard indices.count > count else { return indices }
        guard count > 1 else { return [indices[indices.count / 2]] }

        let lastIndex = indices.count - 1
        return (0..<count).map { position in
            let offset = Int(
                (Double(position) * Double(lastIndex) / Double(count - 1)).rounded()
            )
            return indices[offset]
        }
    }
}

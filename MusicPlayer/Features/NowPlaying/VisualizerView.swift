import SwiftUI

struct VisualizerView: View {
    let spectrumData: [Float]

    var body: some View {
        Canvas { context, size in
            let barCount = spectrumData.count
            guard barCount > 0 else { return }

            let barWidth = size.width / CGFloat(barCount) * 0.7
            let gap = size.width / CGFloat(barCount) * 0.3

            for (index, value) in spectrumData.enumerated() {
                let barHeight = CGFloat(value) * size.height * 0.9
                let x = CGFloat(index) * (barWidth + gap) + gap / 2
                let y = size.height - barHeight

                let rect = CGRect(x: x, y: y, width: barWidth, height: max(barHeight, 2))

                let gradient = Gradient(colors: [
                    .blue.opacity(0.8),
                    .purple.opacity(0.8),
                    .pink.opacity(0.8)
                ])

                let startPoint = CGPoint(x: x + barWidth / 2, y: size.height)
                let endPoint = CGPoint(x: x + barWidth / 2, y: y)

                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 3),
                    with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint)
                )
            }
        }
        .animation(.easeOut(duration: 0.05), value: spectrumData)
    }
}

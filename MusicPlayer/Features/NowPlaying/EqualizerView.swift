import SwiftUI

struct EqualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var equalizer = EqualizerManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Preset picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("预设")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(EqualizerManager.EQPreset.allCases) { preset in
                                Button {
                                    equalizer.applyPreset(preset)
                                } label: {
                                    Text(preset.rawValue)
                                        .font(.subheadline)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            equalizer.currentPreset == preset
                                                ? Color.accentColor
                                                : Color.gray.opacity(0.2)
                                        )
                                        .foregroundColor(equalizer.currentPreset == preset ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Enable toggle
                Toggle("启用均衡器", isOn: $equalizer.isEnabled)
                    .padding(.horizontal)

                // EQ Sliders
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<10, id: \.self) { index in
                        VStack(spacing: 4) {
                            Text(String(format: "%.0f", equalizer.gains[index]))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospacedDigit()

                            VerticalSlider(value: Binding(
                                get: { equalizer.gains[index] },
                                set: { equalizer.adjustBand(index, gain: $0) }
                            ), range: -12...12)
                            .frame(height: 200)

                            Text(equalizer.frequencyLabels[index])
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .opacity(equalizer.isEnabled ? 1.0 : 0.4)

                // Action buttons
                HStack(spacing: 20) {
                    Button("重置") {
                        equalizer.reset()
                    }
                    .foregroundColor(.secondary)

                    if equalizer.currentPreset == .custom {
                        Button("保存自定义") {
                            equalizer.saveCustomPreset()
                        }
                        .foregroundColor(.accentColor)
                    }
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("均衡器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Vertical Slider

struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let normalizedValue = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let yPosition = height * (1 - normalizedValue)

            ZStack(alignment: .bottom) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4)

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 4, height: height - yPosition)

                // Center line
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 16, height: 1)
                    .offset(y: -height / 2)

                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(y: -(height - yPosition - 10))
            }
            .frame(maxWidth: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = 1 - Float(gesture.location.y / height)
                        let clamped = max(0, min(1, ratio))
                        value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}

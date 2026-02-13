import SwiftUI

struct LyricsView: View {
    let lyrics: [LyricLine]
    let currentIndex: Int?

    var body: some View {
        if lyrics.isEmpty {
            VStack {
                Image(systemName: "text.quote")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("暂无歌词")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                            Text(line.text)
                                .font(index == currentIndex ? .body.bold() : .body)
                                .foregroundColor(index == currentIndex ? .primary : .secondary)
                                .multilineTextAlignment(.center)
                                .id(index)
                                .animation(.easeInOut(duration: 0.3), value: currentIndex)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: currentIndex) { _, newIndex in
                    if let index = newIndex {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

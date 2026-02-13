import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                // URL Streaming
                Section("网络音乐") {
                    Button {
                        viewModel.showURLInput = true
                    } label: {
                        Label("从 URL 添加音乐", systemImage: "link")
                    }
                }

                // Sleep Timer
                Section("睡眠定时器") {
                    if viewModel.sleepTimer.isActive {
                        HStack {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.purple)
                            Text("剩余时间")
                            Spacer()
                            Text(viewModel.sleepTimer.formattedRemaining)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Button("取消定时器", role: .destructive) {
                            viewModel.sleepTimer.stop()
                        }
                    } else {
                        ForEach(SleepTimerService.presets, id: \.duration) { preset in
                            Button {
                                viewModel.sleepTimer.bind(to: PlaybackService.shared)
                                viewModel.sleepTimer.start(duration: preset.duration)
                            } label: {
                                HStack {
                                    Image(systemName: "moon")
                                        .foregroundColor(.purple)
                                    Text(preset.label)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Audio Quality
                Section("音频信息") {
                    HStack {
                        Text("支持格式")
                        Spacer()
                        Text("MP3, AAC, FLAC, WAV, ALAC, AIFF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("音频引擎")
                        Spacer()
                        Text("AVAudioEngine (原音质)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Cache Management
                Section("缓存管理") {
                    HStack {
                        Text("缓存大小")
                        Spacer()
                        Text(viewModel.cacheSize)
                            .foregroundColor(.secondary)
                    }
                    Button("清除缓存", role: .destructive) {
                        viewModel.clearCache()
                    }
                }

                // About
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("最低系统要求")
                        Spacer()
                        Text("iOS 17.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .onAppear {
                viewModel.calculateCacheSize()
            }
            .sheet(isPresented: $viewModel.showURLInput) {
                urlInputSheet
            }
        }
    }

    private var urlInputSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "link.circle")
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)

                Text("输入音频文件的 URL")
                    .font(.headline)

                TextField("https://example.com/song.flac", text: $viewModel.urlText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal)

                if let error = viewModel.downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if viewModel.isDownloading {
                    ProgressView("下载中...")
                        .progressViewStyle(.circular)
                } else {
                    Button("下载并添加") {
                        let repo = SongRepository(modelContext: modelContext)
                        viewModel.downloadFromURL(songRepository: repo)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.urlText.isEmpty)
                }

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("添加 URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        viewModel.showURLInput = false
                    }
                }
            }
        }
    }
}

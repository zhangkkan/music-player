import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var viewModel = SettingsViewModel()
    @AppStorage("enrichment.lyrics.source") private var lyricsSourceRaw = LyricsSourceOption.lrclib.rawValue
    @AppStorage("enrichment.correction.threshold") private var correctionThreshold = 0.8
    @AppStorage("enrichment.cache.hours") private var cacheHours = 24.0
    @State private var exportData: Data?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showImportConfirm = false
    @State private var pendingImportData: Data?
    @State private var showExportError = false
    private let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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

                Section("歌曲管理") {
                    NavigationLink {
                        SongManagementView()
                    } label: {
                        Label("歌曲管理", systemImage: "tray.full")
                    }
                    Text("此处删除仅移除 App 内记录，不会删除文件系统中的歌曲。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("歌词与信息纠错") {
                    Picker("歌词来源", selection: $lyricsSourceRaw) {
                        ForEach(LyricsSourceOption.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }

                    HStack {
                        Text("纠错阈值")
                        Spacer()
                        Text(String(format: "%.2f", correctionThreshold))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $correctionThreshold, in: 0.5...1.0, step: 0.01)

                    HStack {
                        Text("缓存时间(小时)")
                        Spacer()
                        Text(String(format: "%.0f", cacheHours))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $cacheHours, in: 1...168, step: 1)
                }

                Section("备份与恢复") {
                    Button("导出备份") {
                        print("[Backup] export tapped")
                        exportData = BackupService.shared.exportZip(modelContext: modelContext)
                        if exportData != nil {
                            print("[Backup] export prepared, showing exporter")
                            showExporter = true
                        } else {
                            print("[Backup] export failed, showing error")
                            showExportError = true
                        }
                    }
                    Button("导入备份") {
                        showImporter = true
                    }
                    Text("导入会覆盖当前数据与设置")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .fileExporter(
            isPresented: $showExporter,
            document: BackupDocument(data: exportData ?? Data()),
            contentType: .zip,
            defaultFilename: "OneMusic-Backup-\(backupDateFormatter.string(from: Date()))"
        ) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url):
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    pendingImportData = data
                    showImportConfirm = true
                }
            case .failure:
                break
            }
        }
        .alert("确认导入", isPresented: $showImportConfirm) {
            Button("导入并覆盖", role: .destructive) {
                NotificationCenter.default.post(name: .backupWillImport, object: nil)
                playbackService.stop()
                playbackService.playQueue.removeAll()
                playbackService.currentIndex = 0
                playbackService.showNowPlaying = false
                let importData = pendingImportData
                DispatchQueue.main.async {
                    if let data = importData {
                        _ = BackupService.shared.importZip(modelContext: modelContext, data: data)
                    }
                }
                pendingImportData = nil
            }
            Button("取消", role: .cancel) {
                pendingImportData = nil
            }
        } message: {
            Text("导入备份将覆盖当前所有数据与设置。")
        }
        .alert("导出失败", isPresented: $showExportError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("导出备份失败，请查看控制台日志后重试。")
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

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

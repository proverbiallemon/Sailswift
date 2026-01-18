import SwiftUI

/// View for browsing and downloading mods from GameBanana
struct ModBrowserView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var cache = GameBananaModCache.shared
    @State private var webViewURL: URL?
    @State private var localFilter = ""
    @State private var selectedCategory: ModCategory = .all

    var body: some View {
        if let url = webViewURL {
            GameBananaWebView(initialURL: url) {
                webViewURL = nil
            }
        } else {
            VStack(spacing: 0) {
                filterBar.padding().background(.bar)
                Divider()

                if cache.isLoading && cache.mods.isEmpty {
                    VStack {
                        ProgressView()
                        Text(cache.loadProgress.isEmpty ? "Loading mods..." : cache.loadProgress)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if cache.mods.isEmpty {
                    EmptyStateView(title: "No Mods Found", systemImage: "magnifyingglass", description: "Try adjusting your search")
                } else {
                    modGrid
                }
            }
            .task { await cache.loadAllIfNeeded() }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Fuzzy filter
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Filter mods...", text: $localFilter)
                    .textFieldStyle(.plain)
                if !localFilter.isEmpty {
                    Button(action: { localFilter = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .frame(maxWidth: 250)

            Picker("Category", selection: $selectedCategory) {
                ForEach(ModCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .frame(width: 140)

            Spacer()

            if cache.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text(cache.loadProgress).foregroundColor(.secondary).font(.caption)
                }
            }

            if !filteredMods.isEmpty {
                Text("\(filteredMods.count) of \(cache.mods.count) mods").foregroundColor(.secondary).font(.caption)
            }

            Button(action: { Task { await cache.reload() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Reload mods from GameBanana")
            .disabled(cache.isLoading)
        }
    }

    private var modGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)], spacing: 16) {
                ForEach(filteredMods) { mod in
                    ModCardView(mod: mod, onOpenInApp: { url in
                        webViewURL = url
                    })
                }
            }
            .padding()
        }
    }

    private var filteredMods: [GameBananaMod] {
        var mods = cache.mods

        // Filter by category
        if selectedCategory != .all {
            mods = mods.filter { $0.category.lowercased() == selectedCategory.rawValue.lowercased() }
        }

        // Apply fuzzy filter if there's filter text
        if !localFilter.isEmpty {
            mods = mods
                .compactMap { mod -> (mod: GameBananaMod, score: Int)? in
                    // Match against name or author
                    if let nameScore = mod.name.fuzzyMatch(localFilter) {
                        return (mod, nameScore)
                    } else if let authorScore = mod.author.fuzzyMatch(localFilter) {
                        return (mod, authorScore)
                    }
                    return nil
                }
                .sorted { $0.score > $1.score }
                .map { $0.mod }
        }

        return mods
    }
}

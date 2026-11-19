import SwiftUI

struct GoldCompanionView: View {
    let marketBasis: GoldMarketBasis
    let cloud: HoldingsCloud
    let session: AuthSession
    @State private var showLogin = false
    @State private var showChanlun = false

    var body: some View {
        NavigationStack {
            if HoldingsDesignPreview.isEnabled {
                holdings
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("金伴").font(.largeTitle.bold()).foregroundStyle(GoldTheme.text)
                            .padding(.bottom, 8)
                        NavigationLink {
                            holdings
                        } label: {
                            toolRow("记金", detail: "记录黄金、管理账本与持仓", symbol: "book.closed")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("companion.holdings")
                        if ChanlunWebConfiguration.current != nil {
                            Button {
                                if session.user == nil { showLogin = true }
                                else { showChanlun = true }
                            } label: {
                                toolRow("禅观", detail: "查看行情走势与复盘", symbol: "chart.line.uptrend.xyaxis")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("companion.chanlun")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 24)
                }
                .background(GoldTheme.background)
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .tint(GoldTheme.gold)
        .sheet(isPresented: $showLogin) { AuthenticationSheet(session: session) }
        .sheet(isPresented: $showChanlun) {
            if let configuration = ChanlunWebConfiguration.current {
                ChanlunWebPage(configuration: configuration, session: session)
            }
        }
    }

    private var holdings: some View {
        HoldingsView(marketBasis: marketBasis, cloud: cloud)
            .id(marketBasis.rawValue)
            .navigationTitle("记金")
            .navigationBarTitleDisplayMode(.inline)
    }

    private func toolRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GoldTheme.gold)
                .frame(width: 44, height: 44)
                .background(GoldTheme.background, in: GoldTheme.rangeShape)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(GoldTheme.text)
                Text(detail).font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(GoldTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .goldCard(padding: 16)
        .contentShape(Rectangle())
    }
}

import ReplayKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = GameStore()
    @StateObject private var pip = PiPController()
    @State private var confirmingReset = false
    @State private var seat = Seat.me

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                playerPicker
                summary
                seatPicker
                cardGrid
                Text("先选记给哪一家，点一下记一张，长按还原一张")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                actions
                seatPlays
                broadcastPanel
            }
            .padding(16)
        }
        .background(alignment: .bottomTrailing) {
            PiPHostView(layer: pip.displayLayer).frame(width: 1, height: 1)
        }
        .onAppear { pip.update(store.tracker) }
        .onChange(of: store.tracker) { pip.update($0) }
        .confirmationDialog("清空这一局的记录？", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("新一局", role: .destructive) { store.reset() }
        }
    }

    private var playerPicker: some View {
        Picker("人数", selection: Binding(
            get: { store.tracker.playerCount },
            set: { count in
                store.setPlayerCount(count)
                if !count.seats.contains(seat) { seat = .me }
            }
        )) {
            ForEach(PlayerCount.allCases) { count in
                Text("\(count.rawValue)人").tag(count)
            }
        }
        .pickerStyle(.segmented)
    }

    private var seatPicker: some View {
        Picker("记给", selection: $seat) {
            ForEach(store.tracker.playerCount.seats) { seat in
                Text(seat.rawValue).tag(seat)
            }
        }
        .pickerStyle(.segmented)
    }

    private var seatPlays: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.tracker.playerCount.seats) { seat in
                let cards = store.tracker.cards(of: seat)
                HStack(alignment: .top) {
                    Text(seat.rawValue).font(.subheadline.bold()).frame(width: 40, alignment: .leading)
                    Text(cards.isEmpty ? "暂无" : cards.map(\.label).joined(separator: " "))
                        .font(.subheadline)
                }
            }
        }
    }

    private var summary: some View {
        let bottom = store.tracker.playerCount.bottomCount
        return HStack {
            Text("已记 \(store.tracker.seenTotal)")
            Spacer()
            Text("未见 \(store.tracker.remainingTotal)")
            Spacer()
            Text("底牌 \(bottom)")
        }
        .font(.headline.monospacedDigit())
    }

    private var cardGrid: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 4) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(Rank.allCases) { rank in
                    Text(rank.rawValue).font(.caption.bold())
                }
                Text("余").font(.caption.bold())
            }
            ForEach(Suit.allCases) { suit in
                GridRow {
                    Text(suit.rawValue)
                        .font(.title3)
                        .foregroundStyle(suit.isRed ? Color.red : Color.primary)
                    ForEach(Rank.allCases) { rank in
                        cell(Card(suit: suit, rank: rank))
                    }
                    Text("\(store.tracker.remaining(suit: suit))")
                        .font(.caption.monospacedDigit())
                }
            }
            GridRow {
                Text("余").font(.caption.bold())
                ForEach(Rank.allCases) { rank in
                    Text("\(store.tracker.remaining(rank: rank))")
                        .font(.caption.monospacedDigit())
                }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    private func cell(_ card: Card) -> some View {
        let remaining = store.tracker.remaining(card)
        return Text("\(remaining)")
            .font(.body.monospacedDigit().bold())
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(remaining == 0 ? Color.gray.opacity(0.15) : Color.accentColor.opacity(0.15))
            .foregroundStyle(remaining == 0 ? Color.secondary : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { store.record(card, by: seat) }
            .onLongPressGesture { store.restore(card) }
            .accessibilityLabel("\(card.suit.rawValue)\(card.rank.rawValue)，剩余\(remaining)张")
    }

    private var actions: some View {
        HStack {
            Button("撤销") { store.undo() }
                .disabled(store.tracker.seenTotal == 0)
            Spacer()
            Button("新一局", role: .destructive) { confirmingReset = true }
        }
        .buttonStyle(.bordered)
    }

    private var broadcastPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.isBroadcasting ? "屏幕广播中" : "屏幕广播未开启").font(.headline)
            Text("牌面识别尚未适配游戏，目前广播不会自动记牌。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if store.rejectedCount > 0 {
                Text("有 \(store.rejectedCount) 张识别结果超过 4 张，请核对")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            HStack {
                BroadcastPicker().frame(width: 44, height: 44)
                Button(pip.isActive ? "关闭小窗" : "打开小窗") { pip.toggle() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// 系统广播按钮，只预选本 APP 的扩展。
private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        // 安装工具可能改写 Bundle ID，所以按运行时的 ID 拼接
        picker.preferredExtension = Bundle.main.bundleIdentifier.map { $0 + ".Broadcast" }
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

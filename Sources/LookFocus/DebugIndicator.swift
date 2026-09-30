import AppKit
import SwiftUI

struct DebugIndicator: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(model.debugMatched ? Color.green : Color.orange, lineWidth: 3)
            VStack(spacing: 4) {
                Label(model.debugTitle, systemImage: model.debugMatched ? "viewfinder" : "questionmark.circle")
                    .font(.headline)
                Text(model.status).font(.callout)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 32)
        }.padding(3)
    }
}


final class DebugHostingView: NSHostingView<DebugIndicator> {
    override var isOpaque: Bool { false }
}

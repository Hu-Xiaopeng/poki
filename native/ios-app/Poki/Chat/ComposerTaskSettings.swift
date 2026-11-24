import SwiftUI

/// The composer's shortcuts use the same settings as Poki's profile and Settings.
struct ComposerTaskSettings: View {
    enum Kind: String, Identifiable {
        case approval, model

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .approval: "Approvals"
            case .model: "Model"
            }
        }
    }

    struct ModelSelection: Equatable {
        let provider: ModelProvider
        let id: String

        static var simulatorPreview: Self? {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-pokiComposerModelPreview"),
               let first = ModelProvider.chatgpt.models.first {
                return Self(provider: .chatgpt, id: first.id)
            }
            #endif
            return nil
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var approvalIconWidth = 24.0
    @State private var contentHeight: CGFloat?
    @State private var modelVersion = ModelKeys.saved
    let kind: Kind
    @Binding var previewSelection: ModelSelection?
    let openModelSetup: () -> Void

    var body: some View {
        NavigationStack {
            List {
                switch kind {
                case .approval: approvalOptions
                case .model: modelOptions
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                ceil(geometry.contentSize.height + geometry.contentInsets.top)
            } action: { _, height in
                if height > 0 { contentHeight = height }
            }
            .environment(\.defaultMinListRowHeight, 44)
            .settingsPage()
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("composer.settings.close")
                }
            }
        }
        .presentationDetents([contentHeight.map { .height($0) } ?? .medium])
        .presentationDragIndicator(.visible)
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in
            modelVersion = ModelKeys.saved
        }
    }

    private var approvalOptions: some View {
        Section {
            ForEach(ApprovalClassifier.Mode.allCases) { mode in
                let selected = model.approvalMode == mode
                Button {
                    model.approvalMode = mode
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: mode.composerSymbol)
                            .foregroundStyle(mode.composerTint)
                            .frame(minWidth: approvalIconWidth)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: mode.title)
                            Text(mode.composerDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        selectionMark(selected)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("composer.approval.\(mode.rawValue)")
            }
        } footer: {
            Text(ApprovalCopy.alwaysConfirm)
        }
        .sensoryFeedback(.selection, trigger: model.approvalMode)
    }

    @ViewBuilder private var modelOptions: some View {
        let _ = modelVersion
        let storage = model.storage
        let providers = ModelProvider.allCases.filter {
            ModelAccounts.isSetUp($0, storage: storage) && ModelAccounts.canChat($0)
        }
        #if DEBUG && targetEnvironment(simulator)
        if previewSelection != nil {
            Section {
                Label("Simulated accounts", systemImage: "testtube.2")
                    .foregroundStyle(.secondary)
            }
            modelGroup(AppLocalization.text(LocalizedStringResource("ChatGPT Subscription")),
                       provider: .chatgpt, choices: ModelProvider.chatgpt.models)
            modelGroup("DeepSeek API", provider: .deepseek, choices: ModelProvider.deepseek.models)
            modelGroup("Claude API", provider: .anthropic, choices: ModelProvider.anthropic.models)
        } else {
            configuredModels(providers, storage: storage)
        }
        #else
        configuredModels(providers, storage: storage)
        #endif
        Section {
            Button(action: openModelSetup) {
                Label("Add Model", systemImage: "plus")
            }
            .accessibilityIdentifier("composer.model.setup")
        } footer: {
            if providers.isEmpty, previewSelection == nil {
                Text("Poki needs a model account before it can reply.")
            }
        }
    }

    private func configuredModels(_ providers: [ModelProvider], storage: PokiStorage) -> some View {
        ForEach(providers) { provider in
            let choices = ModelCatalog.available(provider, storage: storage)
            if provider == .custom {
                ForEach(CustomProviders.all(in: storage)) { custom in
                    let entries = choices.compactMap { choice -> ChatModelChoice? in
                        guard let selection = CustomProviders.parse(choice.id), selection.provider == custom.id else { return nil }
                        return ChatModelChoice(id: choice.id, name: selection.model)
                    }
                    modelGroup(custom.displayName, provider: provider, choices: entries)
                }
            } else {
                modelGroup(provider.name, provider: provider, choices: choices)
            }
        }
    }

    @ViewBuilder private func modelGroup(_ title: String, provider: ModelProvider, choices: [ChatModelChoice]) -> some View {
        if !choices.isEmpty {
            let storage = model.storage
            let current = previewSelection ?? ModelSelection(
                provider: ModelKeys.selectedProvider(in: storage), id: ModelKeys.selectedModel(in: storage)
            )
            Section {
                ForEach(choices) { choice in
                    let selection = ModelSelection(provider: provider, id: choice.id)
                    let selected = selection == current
                    Button {
                        guard !selected else { return }
                        if previewSelection != nil {
                            previewSelection = selection
                        } else {
                            ModelKeys.choose(provider, model: choice.id, in: storage)
                        }
                    } label: {
                        HStack {
                            Text(verbatim: choice.name)
                            Spacer(minLength: 8)
                            selectionMark(selected)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("composer.model.\(provider.rawValue).\(choice.id)")
                }
            } header: {
                Text(verbatim: title)
            }
        }
    }

    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(Tint.blueText)
            .opacity(selected ? 1 : 0)
            .accessibilityHidden(true)
    }
}

extension ApprovalClassifier.Mode {
    var composerSymbol: String {
        switch self {
        case .reply: "hand.raised"
        case .confirm: "checkmark.rectangle"
        case .off: "exclamationmark.shield"
        }
    }

    var composerTint: Color {
        self == .off ? Tint.red : .secondary
    }

    fileprivate var composerDescription: LocalizedStringKey {
        switch self {
        case .reply: "Poki asks in the chat and proceeds after you reply."
        case .confirm: "Tap Allow or Don’t Allow in the Live Activity, a notification, or Poki."
        case .off: "Optional steps run automatically without asking."
        }
    }
}

/// Front view of the brain, with two lobes and a single centre seam.
struct ComposerBrainOutline: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width / 24, y: rect.minY + y * rect.height / 24)
        }

        var outline = Path()
        outline.move(to: point(12, 3.2))
        outline.addCurve(to: point(4.9, 5.6), control1: point(8.9, 0.4), control2: point(5.5, 1.7))
        outline.addCurve(to: point(3, 10), control1: point(2, 6.1), control2: point(1.2, 8))
        outline.addCurve(to: point(4.6, 18.9), control1: point(1, 12.7), control2: point(1.5, 17.4))
        outline.addCurve(to: point(12, 20.6), control1: point(5.4, 22.6), control2: point(10.2, 23.3))
        outline.addCurve(to: point(19.3, 18.8), control1: point(14.3, 23.2), control2: point(18.7, 22.3))
        outline.addCurve(to: point(21, 10), control1: point(22.5, 17.2), control2: point(22.9, 12.8))
        outline.addCurve(to: point(19, 5.3), control1: point(22.8, 8), control2: point(21.6, 6.1))
        outline.addCurve(to: point(12, 3.2), control1: point(18.4, 1.8), control2: point(15.2, 0.9))
        outline.closeSubpath()

        outline.move(to: point(12, 3.2))
        outline.addLine(to: point(12, 20.6))
        outline.move(to: point(3, 10))
        outline.addQuadCurve(to: point(6, 9.4), control: point(4.8, 10.8))
        outline.move(to: point(12, 15.4))
        outline.addQuadCurve(to: point(8.8, 15), control: point(10.5, 16.1))
        outline.move(to: point(19, 5.3))
        outline.addQuadCurve(to: point(16.7, 8.4), control: point(19, 7.4))
        outline.move(to: point(12, 11.8))
        outline.addLine(to: point(14.5, 11.8))
        return outline
    }
}

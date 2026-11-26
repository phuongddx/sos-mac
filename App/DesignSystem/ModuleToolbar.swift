import SwiftUI

/// What a screen shows in the window toolbar (spec §3.3, OD-2 = system toolbar).
///
/// - `title`: the screen name. Also set as the `navigationTitle`, so the window
///   menu, Mission Control and VoiceOver read it; the window hides its own title
///   text (`.windowToolbarStyle(.unified(showsTitle: false))` in `SOSMacApp`) so the
///   name is drawn once, by the `.principal` item.
/// - `subtitle`: state, count or folder. Real values only; `nil` hides the line.
/// - `back`: the one-step back button for `review` and sub-screens.
/// - `tools`: trailing controls (segmented pickers, Quarantine, search). Monochrome:
///   no tinted toolbar buttons — a state's focal action lives in the dock.
struct ModuleToolbarModel {
    struct Back {
        let label: String
        let action: @MainActor () -> Void
    }

    var title: String
    var subtitle: String?
    var back: Back?
    var tools: AnyView?

    init(title: String, subtitle: String? = nil, back: Back? = nil, tools: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.tools = tools
    }
}

extension ModuleToolbarModel {
    /// The PR 2 model for each screen: title only. Subtitles, back buttons and tools
    /// arrive with each screen's own PR, from that screen's view-model state; until
    /// then the old in-content headers stay.
    static func shell(for destination: SidebarDestination) -> ModuleToolbarModel {
        ModuleToolbarModel(title: destination.rawValue)
    }
}

private struct ModuleToolbarModifier: ViewModifier {
    let model: ModuleToolbarModel

    func body(content: Content) -> some View {
        content
            .navigationTitle(model.title)
            .toolbar {
                if let back = model.back {
                    ToolbarItem(placement: .navigation) {
                        Button(action: back.action) {
                            Label(back.label, systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                        .help(back.label)
                        .accessibilityIdentifier("toolbar-back")
                    }
                }
                if #available(macOS 26, *) {
                    // The prototype draws the title as plain text, not inside a glass capsule.
                    ToolbarItem(placement: .principal) {
                        ModuleToolbarTitle(title: model.title, subtitle: model.subtitle)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) {
                        ModuleToolbarTitle(title: model.title, subtitle: model.subtitle)
                    }
                }
                if let tools = model.tools {
                    ToolbarItem(placement: .primaryAction) {
                        tools
                    }
                }
            }
    }
}

/// Title (title3) over an optional subtitle (subheadline, `textSecondary`), as the
/// prototype's `.toolbar .title` / `.subtitle`.
private struct ModuleToolbarTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Theme.Font.title3)
                .foregroundStyle(Theme.Color.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("toolbar-title")
    }
}

extension View {
    /// Applies a screen's `ModuleToolbarModel` to the window toolbar.
    func moduleToolbar(_ model: ModuleToolbarModel) -> some View {
        modifier(ModuleToolbarModifier(model: model))
    }
}

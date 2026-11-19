import Foundation

/// What clearing one section of the stream says. Each section's Clear asks first. Clearing Windows puts
/// every tucked window back where it was and never closes one; clearing Files is `ClearPlan`'s; clearing
/// Copied empties clipboard history.
public enum SectionClearing {
    /// The button and menu item: "Clear Windows", "Clear Files", "Clear Copied".
    public static func title(_ lens: StreamLens) -> String {
        "Clear \(lens.title)"
    }

    public static func windowsQuestion(count: Int) -> String {
        count == 1 ? "Put back the tucked window?" : "Put back all \(count) windows?"
    }

    public static func windowsDetail(count: Int) -> String {
        count == 1
            ? "It goes back where it was and isn't closed. If it can't come back, it stays here."
            : "Each goes back where it was, one after another, and none is closed. Any that can't come back stay here."
    }

    public static func windowsConfirmation(count: Int) -> String {
        count == 1 ? "Put Back" : "Put Back All"
    }

    public static func copiedQuestion(count: Int) -> String {
        count == 1 ? "Clear the copied item?" : "Clear all \(count) copied items?"
    }

    public static let copiedDetail = "Copies leave the history, with the images and styling Tuck kept for them. "
        + "What's on the clipboard now stays, and so does anything kept in Tuck."
}

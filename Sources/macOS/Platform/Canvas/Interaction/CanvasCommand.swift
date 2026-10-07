import Foundation

protocol CanvasCommand {
    var before: CanvasSceneDocument { get }
    var after: CanvasSceneDocument { get }
    var actionName: String { get }

    func reversed() -> any CanvasCommand
}

struct SceneMutationCommand: CanvasCommand {
    let before: CanvasSceneDocument
    let after: CanvasSceneDocument
    let actionName: String

    func reversed() -> any CanvasCommand {
        SceneMutationCommand(before: after, after: before, actionName: actionName)
    }
}

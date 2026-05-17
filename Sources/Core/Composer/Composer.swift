import Foundation

/// Errors thrown by Composer.compose.
public enum ComposerError: Error, CustomStringConvertible {
    case unknownTemplate(String)
    case emptySet

    public var description: String {
        switch self {
        case .unknownTemplate(let id): return "Unknown template: \(id)"
        case .emptySet: return "Set has no kept elements"
        }
    }
}

/// The Composer orchestrator. Stateless static API.
///
/// Pipeline:
///   1. Resolve template by ID (throws if unknown)
///   2. Build BedPlan from sustained elements via BedPlanner
///   3. Build [ObjectPlan] from non-sustained elements via Template.schedule
///   4. Cap objects at 118 (Atmos hard limit)
///   5. Package into Composition with deterministic slug
public enum Composer {

    public static func compose(
        set: SetData,
        templateID: String,
        durationSec: Double,
        seed: UInt64,
        title: String
    ) throws -> Composition {
        guard !set.keptElements.isEmpty else {
            throw ComposerError.emptySet
        }
        guard let template = TemplateRegistry.byID(templateID) else {
            throw ComposerError.unknownTemplate(templateID)
        }

        let bedPlan = BedPlanner.plan(
            set: set,
            targetDurationSec: durationSec,
            crossfadeMs: 250
        )

        var objects = template.schedule(set: set, durationSec: durationSec, seed: seed)
        if objects.count > 118 {
            objects = Array(objects.prefix(118))
        }

        let slug = makeSlug(title: title, seed: seed)

        return Composition(
            title: title,
            slug: slug,
            durationSec: durationSec,
            seed: seed,
            templateID: templateID,
            bedPlan: bedPlan,
            objects: objects
        )
    }

    /// `<sanitized-title>-<6-char-hex>` where hex is derived from seed only,
    /// so the same (title, seed) always produces the same slug.
    private static func makeSlug(title: String, seed: UInt64) -> String {
        let titleSlug = SetData.slugify(title)
        let prefix = titleSlug.isEmpty ? "world" : titleSlug
        let hex = String(format: "%06x", seed & 0xFFFFFF)
        return "\(prefix)-\(hex)"
    }
}

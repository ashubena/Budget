import SwiftUI

/// Standard sizing for modal sheets on macOS. iOS sheets fill available
/// space automatically, so this is a no-op there.
///
/// Replaces the copy-pasted `#if os(macOS) .frame(minWidth:..., minHeight:...) #endif`
/// blocks that previously lived at the bottom of every sheet view.
enum SheetSize {
    case compact   // small forms (amount entry, add category)
    case standard  // bucket create/edit, transaction edit
    case tall      // category picker (long scrolling list)

    var minWidth: CGFloat {
        switch self {
        case .compact:  return 380
        case .standard: return 420
        case .tall:     return 420
        }
    }
    var idealWidth: CGFloat {
        switch self {
        case .compact:  return 420
        case .standard: return 480
        case .tall:     return 460
        }
    }
    var minHeight: CGFloat {
        switch self {
        case .compact:  return 320
        case .standard: return 480
        case .tall:     return 520
        }
    }
    var idealHeight: CGFloat {
        switch self {
        case .compact:  return 360
        case .standard: return 560
        case .tall:     return 600
        }
    }
}

extension View {
    /// Apply standard sheet sizing on macOS; no-op on iOS.
    @ViewBuilder
    func macOSSheetSize(_ size: SheetSize = .standard) -> some View {
        #if os(macOS)
        self.frame(
            minWidth: size.minWidth,
            idealWidth: size.idealWidth,
            minHeight: size.minHeight,
            idealHeight: size.idealHeight
        )
        #else
        self
        #endif
    }
}

//
//  Item.swift
//  Budget
//
//  Created by Ayesha Zulfiqar on 01/05/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

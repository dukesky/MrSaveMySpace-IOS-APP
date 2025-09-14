//
//  MrSaveMySpaceApp.swift
//  MrSaveMySpace
//
//  Created by Tian Zhang on 9/13/25.
//

import SwiftUI

@main
struct MrSaveMySpaceApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

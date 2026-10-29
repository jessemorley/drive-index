//
//  DuplicateSettingsView.swift
//  DriveIndex
//
//  Duplicate detection settings view
//

import SwiftUI

struct DuplicateSettingsView: View {
    @AppStorage("enableDuplicateDetection") private var enableDuplicateDetection: Bool = true

    var body: some View {
        Form {
            Section("Duplicate Detection") {
                Toggle(isOn: $enableDuplicateDetection) {
                    Text("Enable duplicate detection")
                    Text("Duplicate detection will be disabled. File hashes will not be computed during indexing.")
                }
            }

            Section("About Duplicate Detection") {
                LabeledContent {} label: {
                    Text("Performance Impact")
                    Text("Computing file hashes requires reading file contents, which can slow down indexing for large drives.")
                }
                LabeledContent {} label: {
                    Text("Hash Algorithm")
                    Text("Uses XXHash64 for fast, non-cryptographic hashing optimized for duplicate detection.")
                }
                LabeledContent {} label: {
                    Text("Changes Take Effect")
                    Text("Changes will apply to new indexing operations. Existing hashes in the database are not affected.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Duplicates")
    }
}

#Preview {
    DuplicateSettingsView()
}

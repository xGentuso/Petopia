//
//  PetopiaApp.swift
//  Petopia
//
//  Created by ryan mota on 2025-03-20.
//

import SwiftUI

@main
struct Petopia: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: PetViewModel
    @StateObject private var onboardingViewModel = OnboardingViewModel()
    @State private var showLaunchScreen = true
    @State private var showingBackupRestoreAlert = false
    @State private var backupMessage = ""
    @State private var isBackupSuccess = true
    
    init() {
        // TESTING ONLY - Force reset onboarding flag
        #if DEBUG
        UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding")
        #endif
        
        // Perform any necessary data migrations
        DataMigrationHelper.shared.performMigrationsIfNeeded()
        
        // Initialize with saved pet data or create a new pet
        let pet = AppDataManager.shared.loadPet()
        _viewModel = StateObject(wrappedValue: PetViewModel(pet: pet))
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                #if DEBUG
                // Debug logging
                let _ = print("Onboarding complete? \(onboardingViewModel.onboardingComplete)")
                #endif
                
                if onboardingViewModel.onboardingComplete {
                    // Regular app flow
                    ContentView(viewModel: viewModel)
                        .opacity(showLaunchScreen ? 0 : 1)
                        .environment(\.openURL, OpenURLAction { url in
                            // Handle backup file opening for restores
                            if url.pathExtension == "json" {
                                handleBackupFileOpen(url)
                                return .handled
                            }
                            return .systemAction
                        })
                } else {
                    // Onboarding flow
                    OnboardingView(viewModel: onboardingViewModel)
                        .opacity(showLaunchScreen ? 0 : 1)
                        .onChange(of: onboardingViewModel.onboardingComplete) { _, completed in
                            if completed {
                                // Refresh the PetViewModel with the newly created pet
                                if let newPet = AppDataManager.shared.loadPet() {
                                    viewModel.pet = newPet
                                }
                            }
                        }
                }
                
                if showLaunchScreen {
                    LaunchScreen()
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.3), value: showLaunchScreen)
                }
            }
            .onAppear {
                // Simulate a delay for the launch screen
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        showLaunchScreen = false
                    }
                }
            }
            .alert(isPresented: $showingBackupRestoreAlert) {
                Alert(
                    title: Text(isBackupSuccess ? "Success" : "Error"),
                    message: Text(backupMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                // Save data when app goes to background or becomes inactive
                AppDataManager.shared.saveAllData(viewModel: viewModel)
                print("App state changed to \(newPhase) - Saving data")
                
                // Create auto-backup on background
                if newPhase == .background {
                    createAutoBackup()
                }
            }
        }
    }
    
    // Create an automatic backup when app goes to background
    private func createAutoBackup() {
        #if DEBUG
        print("Skipping auto-backup in debug mode")
        #else
        // In production, create a backup file in app's documents directory
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let backupURL = documentsDirectory.appendingPathComponent("petopia_autobackup.json")
            
            if let data = AppDataManager.shared.exportData() {
                do {
                    try data.write(to: backupURL)
                    print("Auto-backup created successfully")
                } catch {
                    print("Failed to create auto-backup: \(error)")
                }
            }
        }
        #endif
    }
    
    // Handle backup file opening (for restore)
    private func handleBackupFileOpen(_ url: URL) {
        let success = DataMigrationHelper.shared.restoreFromBackup(fileURL: url)
        
        backupMessage = success ?
            "Your pet data has been successfully restored. The app will now restart." :
            "There was a problem restoring the backup. Please try again with a different file."
        
        isBackupSuccess = success
        showingBackupRestoreAlert = true
        
        if success {
            // Restart the app after successful restore
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                exit(0) // Force restart to load new data
            }
        }
    }
}

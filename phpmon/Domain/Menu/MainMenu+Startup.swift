//
//  MainMenu+Startup.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 03/01/2022.
//  Copyright © 2022 Nico Verbruggen. All rights reserved.
//

import Cocoa

extension MainMenu {
    /**
     Kick off the startup of the rendering of the main menu.
     */
    func startup() {
        // Start with the icon
        setStatusBar(image: NSImage(named: NSImage.Name("StatusBarIcon"))!)
        
        // Perform environment boot checks
        DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
            Startup().checkEnvironment(success: { onEnvironmentPass() },
                                       failure: { onEnvironmentFail() }
            )
        }
    }
    
    /**
     When the environment is all clear and the app can run, let's go.
     */
    private func onEnvironmentPass() {
        PhpEnv.detectPhpVersions()
        
        if HomebrewDiagnostics.hasAliasConflict() {
            DispatchQueue.main.async {
                Alert.notify(
                    message: "alert.php_alias_conflict.title".localized,
                    info: "alert.php_alias_conflict.info".localized,
                    style: .critical
                )
            }
        }
        
        updatePhpVersionInStatusBar()
        
        Log.info("Determining broken PHP-FPM...")
        // Attempt to find out if PHP-FPM is broken
        let installation = PhpEnv.phpInstall
        installation.notifyAboutBrokenPhpFpm()
        
        // Set up the config watchers on launch (these are automatically updated via delegate methods if the user switches)
        Log.info("Setting up watchers...")
        App.shared.handlePhpConfigWatcher()
        
        // Detect applications (preset + custom)
        Log.info("Detecting applications...")
        App.shared.detectedApplications = Application.detectPresetApplications()
        let customApps = Preferences.custom.scanApps.map { appName in
            return Application(appName, .user_supplied)
        }.filter { app in
            return app.isInstalled()
        }
        App.shared.detectedApplications.append(contentsOf: customApps)
        let appNames = App.shared.detectedApplications.map { app in
            return app.name
        }
        Log.info("Detected applications: \(appNames)")
        
        // Load the global hotkey
        App.shared.loadGlobalHotkey()
        
        // Attempt to find out more info about Valet
        if Valet.shared.version != nil {
            Log.info("PHP Monitor has extracted the version number of Valet: \(Valet.shared.version!)")
        }
        
        Valet.shared.loadConfiguration()
        Valet.shared.validateVersion()
        Valet.shared.startPreloadingSites()
        
        NotificationCenter.default.post(name: Events.ServicesUpdated, object: nil)
        
        Log.info("PHP Monitor is ready to serve!")
        
        // Schedule a request to fetch the PHP version every 60 seconds
        DispatchQueue.main.async { [self] in
            App.shared.timer = Timer.scheduledTimer(
                timeInterval: 60,
                target: self,
                selector: #selector(refreshActiveInstallation),
                userInfo: nil,
                repeats: true
            )
        }
        
        Stats.incrementSuccessfulLaunchCount()
        Stats.evaluateSponsorMessageShouldBeDisplayed()
        
        // Attempt to fix Homebrew permissions
        Actions.fixHomebrewPermissions()
    }
    
    /**
     When the environment is not OK, present an alert to inform the user.
     */
    private func onEnvironmentFail() {
        DispatchQueue.main.async { [self] in
            let close = Alert.present(
                messageText: "alert.cannot_start.title".localized,
                informativeText: "alert.cannot_start.info".localized,
                buttonTitle: "alert.cannot_start.close".localized,
                secondButtonTitle: "alert.cannot_start.retry".localized
            )
            
            if (close) {
                exit(1)
            }
            
            startup()
        }
    }
}

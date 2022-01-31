//
//  MainMenu.swift
//  PHP Monitor
//
//  Copyright © 2021 Nico Verbruggen. All rights reserved.
//

import Cocoa

class MainMenu: NSObject, NSWindowDelegate, NSMenuDelegate {

    static let shared = MainMenu()
    
    weak var menuDelegate: NSMenuDelegate? = nil
    
    /**
     The status bar item with variable length.
     */
    let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    
    // MARK: - UI related
    
    /**
     Update the menu's contents, based on what's going on.
     This will rebuild the entire menu, so this can take a few moments.
     */
    func rebuild() {
        // Update the menu item on the main thread
        DispatchQueue.main.async { [self] in
            // Create a new menu
            let menu = StatusMenu()
            
            // Add the PHP versions (or error messages)
            menu.addPhpVersionMenuItems()
            menu.addItem(NSMenuItem.separator())
            
            // Add the possible actions
            menu.addPhpActionMenuItems()
            menu.addItem(NSMenuItem.separator())
            
            // Add Valet interactions
            menu.addValetMenuItems()
            menu.addItem(NSMenuItem.separator())
            
            // Add services
            menu.addPhpConfigurationMenuItems()
            menu.addItem(NSMenuItem.separator())
            
            // Add about & quit menu items
            menu.addItem(NSMenuItem(title: "mi_preferences".localized, action: #selector(openPrefs), keyEquivalent: ","))
            menu.addItem(NSMenuItem(title: "mi_about".localized, action: #selector(openAbout), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "mi_quit".localized, action: #selector(terminateApp), keyEquivalent: "q"))
            
            // Make sure every item can be interacted with
            menu.items.forEach({ (item) in
                item.target = self
            })
            
            statusItem.menu = menu
            statusItem.menu?.delegate = self
        }
    }
    
    /**
     Sets the status bar image based on a version string.
     */
    func setStatusBarImage(version: String) {
        setStatusBar(
            image: Preferences.isEnabled(.shouldDisplayPhpHintInIcon)
                ? MenuBarImageGenerator.textToImageWithIcon(text: version)
                : MenuBarImageGenerator.textToImage(text: version)
        )
    }
    
    /**
     Sets the status bar image, based on the provided NSImage.
     The image will be used as a template image.
     */
    func setStatusBar(image: NSImage) {
        if let button = statusItem.button {
            image.isTemplate = true
            button.image = image
        }
    }
    
    // MARK: - Nicer callbacks
    
    /**
     Executes a specific callback and fires the completion callback,
     while updating the UI as required. As long as the completion callback
     does not fire, the app is presumed to be busy and the UI reflects this.
     
     - Parameter execute: Callback of the work that needs to happen.
     - Parameter completion: Callback that is fired when the work is done.
     */
    private func waitAndExecute(_ execute: @escaping () -> Void, completion: @escaping () -> Void = {})
    {
        PhpEnv.shared.isBusy = true
        setBusyImage()
        DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
            execute()
            PhpEnv.shared.isBusy = false
            
            DispatchQueue.main.async { [self] in
                PhpEnv.shared.currentInstall = ActivePhpInstallation()
                updatePhpVersionInStatusBar()
                NotificationCenter.default.post(name: Events.ServicesUpdated, object: nil)
                completion()
            }
        }
    }
    
    // MARK: - User Interface
    
    @objc func refreshActiveInstallation() {
        if !PhpEnv.shared.isBusy {
            PhpEnv.shared.currentInstall = ActivePhpInstallation()
            updatePhpVersionInStatusBar()
        } else {
            Log.perf("Skipping version refresh due to busy status")
        }
    }
    
    @objc func updatePhpVersionInStatusBar() {
        refreshIcon()
        rebuild()
    }
    
    func refreshIcon() {
        DispatchQueue.main.async { [self] in
            if (App.busy) {
                setStatusBar(image: NSImage(named: NSImage.Name("StatusBarIcon"))!)
            } else {
                if Preferences.preferences[.shouldDisplayDynamicIcon] as! Bool == false {
                    // Static icon has been requested
                    setStatusBar(image: NSImage(named: NSImage.Name("StatusBarIconStatic"))!)
                } else {
                    // The dynamic icon has been requested
                    let long = Preferences.preferences[.fullPhpVersionDynamicIcon] as! Bool
                    setStatusBarImage(version: long ? PhpEnv.phpInstall.version.long  : PhpEnv.phpInstall.version.short)
                }
            }
        }
    }
    
    @objc func reloadPhpMonitorMenuInBackground() {
        waitAndExecute {
            // This automatically reloads the menu
            Log.info("Reloading information about the PHP installation (in the background)...")
        }
    }
    
    @objc func reloadPhpMonitorMenu() {
        waitAndExecute {
            // This automatically reloads the menu
            Log.info("Reloading information about the PHP installation...")
        }
    }
    
    @objc func setBusyImage() {
        DispatchQueue.main.async { [self] in
            setStatusBar(image: NSImage(named: NSImage.Name("StatusBarIcon"))!)
        }
    }
    
    // MARK: - Actions
    
    @objc func fixHomebrewPermissions() {
        Actions.fixHomebrewPermissions()
    }
    
    @objc func restartPhpFpm() {
        waitAndExecute {
            Actions.restartPhpFpm()
        }
    }
    
    @objc func restartAllServices() {
        waitAndExecute {
            Actions.restartDnsMasq()
            Actions.restartPhpFpm()
            Actions.restartNginx()
        } completion: {
            DispatchQueue.main.async {
                LocalNotification.send(
                    title: "notification.services_restarted".localized,
                    subtitle: "notification.services_restarted_desc".localized
                )
            }
        }
    }
    
    @objc func stopAllServices() {
        waitAndExecute {
            Actions.stopAllServices()
        } completion: {
            DispatchQueue.main.async {
                LocalNotification.send(
                    title: "notification.services_stopped".localized,
                    subtitle: "notification.services_stopped_desc".localized
                )
            }
        }
    }
    
    @objc func restartNginx() {
        waitAndExecute {
            Actions.restartNginx()
        }
    }
    
    @objc func restartDnsMasq() {
        waitAndExecute {
            Actions.restartDnsMasq()
        }
    }
    
    @objc func toggleExtension(sender: ExtensionMenuItem) {
        waitAndExecute {
            sender.phpExtension?.toggle()
            
            if Preferences.isEnabled(.autoServiceRestartAfterExtensionToggle) {
                Actions.restartPhpFpm()
            }
        }
    }
    
    @objc func openPhpInfo() {
        var url: URL? = nil
        
        waitAndExecute {
            url = Actions.createTempPhpInfoFile()
        } completion: {
            // When this has been completed, open the URL to the file in the browser
            NSWorkspace.shared.open(url!)
        }
    }
    
    @objc func fixMyValet() {
        // Tell the user the switch is about to occur
        if Alert.present(
            messageText: "alert.fix_my_valet.title".localized,
            informativeText: "alert.fix_my_valet.info".localized(PhpEnv.brewPhpVersion),
            buttonTitle: "alert.fix_my_valet.ok".localized,
            secondButtonTitle: "alert.fix_my_valet.cancel".localized,
            style: .warning
        ) {
            // Start the fix
            waitAndExecute {
                Actions.fixMyValet()
            } completion: {
                Alert.notify(
                    message: "alert.fix_my_valet_done.title".localized,
                    info: "alert.fix_my_valet_done.info".localized
                )
            }
        } else {
            Log.info("The user has chosen to abort Fix My Valet")
        }
    }
    
    @objc func updateGlobalComposerDependencies() {
        self.updateGlobalDependencies(notify: true, completion: { _ in })
    }
    
    @objc func openActiveConfigFolder() {
        if (PhpEnv.phpInstall.version.error) {
            // php version was not identified
            Actions.openGenericPhpConfigFolder()
            return
        }
        
        // php version was identified
        Actions.openPhpConfigFolder(version: PhpEnv.phpInstall.version.short)
    }
    
    @objc func openGlobalComposerFolder() {
        Actions.openGlobalComposerFolder()
    }
    
    @objc func openValetConfigFolder() {
        Actions.openValetConfigFolder()
    }
    
    @objc func switchToPhpVersion(sender: PhpMenuItem) {
        self.switchToPhpVersion(sender.version)
    }
    
    // TODO (5.1): Investigate if `waitAndExecute` cannot be used here
    @objc func switchToPhpVersion(_ version: String) {
        setBusyImage()
        PhpEnv.shared.isBusy = true
        
        DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
            // Update the PHP version in the status bar
            updatePhpVersionInStatusBar()
            
            // Update the menu
            rebuild()
            
            let sendLocalNotification = {
                LocalNotification.send(
                    title: String(format: "notification.version_changed_title".localized, version),
                    subtitle: String(format: "notification.version_changed_desc".localized, version)
                )
                PhpEnv.phpInstall.notifyAboutBrokenPhpFpm()
            }
        
            let completion = {
                // Fire off the delegate method
                PhpEnv.shared.delegate?.switcherDidCompleteSwitch()
                
                // Mark as no longer busy
                PhpEnv.shared.isBusy = false
                
                // Perform UI updates on main thread
                DispatchQueue.main.async { [self] in
                    updatePhpVersionInStatusBar()
                    rebuild()
                    
                    if !PhpEnv.shared.validate(version) {
                        let outcome = Alert.present(
                            messageText: "alert.php_switch_failed.title".localized(version),
                            informativeText: "alert.php_switch_failed.info".localized(version),
                            buttonTitle: "alert.php_switch_failed.confirm".localized,
                            secondButtonTitle: "alert.php_switch_failed.cancel".localized, style: .informational)
                        if outcome {
                            MainMenu.shared.fixMyValet()
                        }
                        return
                    }
                    
                    // Run composer updates
                    if Preferences.isEnabled(.autoComposerGlobalUpdateAfterSwitch) {
                        self.updateGlobalDependencies(notify: false, completion: { _ in sendLocalNotification() })
                    } else {
                        sendLocalNotification()
                    }
                    
                    // Update stats
                    Stats.incrementSuccessfulSwitchCount()
                    Stats.evaluateSponsorMessageShouldBeDisplayed()
                }
            }
            
            PhpEnv.switcher.performSwitch(
                to: version,
                completion: completion
            )
        }
    }
    
    @objc func openAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel()
    }
    
    @objc func openPrefs() {
        PrefsVC.show()
    }
    
    @objc func openSiteList() {
        SiteListVC.show()
    }
    
    @objc func terminateApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Menu Delegate
    
    func menuWillOpen(_ menu: NSMenu) {
        // Make sure the shortcut key does not trigger this when the menu is open
        App.shared.shortcutHotkey?.isPaused = true
    }
    
    func menuDidClose(_ menu: NSMenu) {
        // When the menu is closed, allow the shortcut to work again
        App.shared.shortcutHotkey?.isPaused = false
    }
    
    // MARK: - Private Methods
    
    /**
     Updates the global dependencies and runs the completion callback when done.
     */
    private func updateGlobalDependencies(notify: Bool, completion: @escaping (Bool) -> Void) {
        if !Shell.fileExists("/usr/local/bin/composer") {
            Alert.notify(
                message: "alert.composer_missing.title".localized,
                info: "alert.composer_missing.info".localized
            )
            return
        }
        
        PhpEnv.shared.isBusy = true
        setBusyImage()
        self.rebuild()
        
        let noLongerBusy = {
            PhpEnv.shared.isBusy = false
            DispatchQueue.main.async { [self] in
                self.updatePhpVersionInStatusBar()
                self.rebuild()
            }
        }
        
        var window: ProgressWindowController? = ProgressWindowController.display(
            title: "alert.composer_progress.title".localized,
            description: "alert.composer_progress.info".localized
        )
        window?.setType(info: true)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Shell.user.createTask(
                for: "/usr/local/bin/composer global update", requiresPath: true
            )
            
            DispatchQueue.main.async {
                window?.addToConsole("/usr/local/bin/composer global update\n")
            }
            
            Shell.captureOutput(
                task,
                didReceiveStdOutData: { string in
                    DispatchQueue.main.async {
                        window?.addToConsole(string)
                    }
                    Log.perf("\(string.trimmingCharacters(in: .newlines))")
                },
                didReceiveStdErrData: { string in
                    DispatchQueue.main.async {
                        window?.addToConsole(string)
                    }
                    Log.perf("\(string.trimmingCharacters(in: .newlines))")
                }
            )
            
            task.launch()
            task.waitUntilExit()
            Shell.haltCapturingOutput(task)
            
            DispatchQueue.main.async {
                if task.terminationStatus <= 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        window?.close()
                        if (notify) {
                            LocalNotification.send(
                                title: "alert.composer_success.title".localized,
                                subtitle: "alert.composer_success.info".localized
                            )
                        }
                        window = nil
                        noLongerBusy()
                        completion(true)
                    }
                } else {
                    window?.setType(info: false)
                    window?.progressView?.labelTitle.stringValue = "alert.composer_failure.title".localized
                    window?.progressView?.labelDescription.stringValue = "alert.composer_failure.info".localized
                    window = nil
                    noLongerBusy()
                    completion(false)
                }
            }
        }
    }
}

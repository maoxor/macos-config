// Zen Browser preferences owned by macos-config (tools/zen/README.md). Copied into the default profile by
// tools/zen/apply-profile.sh; Zen reads it at each start, so a value changed in Settings comes back on restart:
// change it here instead.

// Ctrl+Tab goes to the last used tab first, like Option+Tab for windows (docs/shortcuts.md).
user_pref("browser.ctrlTab.sortByRecentlyUsed", true);
// Reopen the previous session's windows and tabs (many tabs, workspaces).
user_pref("browser.startup.page", 3);
// Restored tabs stay unloaded until clicked (Firefox's default, kept explicit), pinned ones too; an unloaded tab is
// drawn faded.
user_pref("browser.sessionstore.restore_on_demand", true);
user_pref("browser.sessionstore.restore_pinned_tabs_on_demand", true);
user_pref("browser.tabs.fadeOutUnloadedTabs", true);
// Tabs unused for 10 min are unloaded by Auto Tab Discard. Zen dropped its own timed unloader in 1.12.9b, and on
// macOS Firefox's low-memory unloader never runs: browser.lowMemoryResponseMask ships as 0 because the memory watcher
// is unreliable there (zen-browser/desktop#15619). The two add-ons placed by apply-profile.sh start enabled, without
// a prompt.
user_pref("extensions.autoDisableScopes", 0);
user_pref("extensions.startupScanScopes", 1);
user_pref("browser.tabs.unloadOnLowMemory", true);
// No telemetry, no studies.
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.discovery.enabled", false);
// about:config without the warning page.
user_pref("browser.aboutConfig.showWarning", false);

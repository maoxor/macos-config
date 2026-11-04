// Zen's open tabs in a native Raycast list. Zen (Firefox) has no AppleScript: the tabs come from its session file
// (scripts/zen-tabs.py in the macos-config repo), and the jump goes through Hammerspoon (zen-tabs.lua), which drives
// Zen's own tab search. Opened by Ctrl+Space (Hammerspoon) or from Raycast.
import { Action, ActionPanel, Icon, List, closeMainWindow, showToast, Toast } from "@raycast/api";
import { getFavicon } from "@raycast/utils";
import { execFile, execFileSync } from "child_process";
import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { useMemo } from "react";

type Tab = { title: string; url: string; selected: boolean; workspace: string; pinned: boolean };

const HS = "/opt/homebrew/bin/hs";

function repoDir(): string {
  const pointer = join(homedir(), ".config/macos-config/repo");
  if (existsSync(pointer)) {
    const p = readFileSync(pointer, "utf8").trim();
    if (p) return p;
  }
  return join(homedir(), "dev/macos-config");
}

function loadTabs(): { tabs: Tab[]; error?: string } {
  try {
    const out = execFileSync("/usr/bin/python3", ["-I", join(repoDir(), "scripts/zen-tabs.py")], {
      encoding: "utf8",
      timeout: 5000,
    });
    const tabs = out
      .split("\n")
      .filter(Boolean)
      .map((l) => JSON.parse(l) as Tab);
    return { tabs };
  } catch (e) {
    return { tabs: [], error: e instanceof Error ? e.message : String(e) };
  }
}

const lua = (s: string) => "[==[" + s.replaceAll("]==]", "") + "]==]";

function bare(url: string): string {
  return url.replace(/^[a-z]+:\/\//, "").replace(/[?#].*$/, "").replace(/\/+$/, "");
}

const site = (url: string) => bare(url).split("/")[0].replace(/^www\./, "");

// Raycast collapses a title longer than the row to an ellipsis; ChatGPT titles are whole prompts.
const short = (t: string) => (t.length > 72 ? t.slice(0, 70).trimEnd() + "…" : t);

async function jump(tab: Tab) {
  await closeMainWindow({ clearRootSearch: true });
  execFile(HS, ["-c", `zenTabs.switchTo(${lua(tab.url)}, ${lua(tab.title)})`], { timeout: 8000 }, (err) => {
    if (err) showToast({ style: Toast.Style.Failure, title: "Hammerspoon ne répond pas", message: err.message });
  });
}

export default function Command() {
  const { tabs, error } = useMemo(loadTabs, []);
  return (
    <List searchBarPlaceholder="Chercher un onglet Zen…" filtering={{ keepSectionOrder: true }}>
      {error ? (
        <List.EmptyView icon={Icon.Warning} title="Impossible de lire les onglets de Zen" description={error} />
      ) : (
        <List.EmptyView icon={Icon.Globe} title="Aucun onglet" description="Zen n'a pas encore écrit sa session." />
      )}
      <List.Section title="Onglets ouverts" subtitle={`${tabs.length}`}>
        {tabs.map((tab, i) => (
          <List.Item
            key={`${i}-${tab.url}`}
            icon={getFavicon(tab.url, { fallback: Icon.Globe })}
            title={short(tab.title)}
            subtitle={site(tab.url)}
            keywords={[bare(tab.url), tab.title, tab.workspace].filter(Boolean)}
            accessories={[
              ...(tab.pinned ? [{ icon: Icon.Pin, tooltip: "Épinglé" }] : []),
              ...(tab.selected ? [{ tag: "actif" }] : []),
              ...(tab.workspace ? [{ text: tab.workspace }] : []),
            ]}
            actions={
              <ActionPanel>
                <Action title="Aller à l'onglet" icon={Icon.ArrowRight} onAction={() => jump(tab)} />
                <Action.CopyToClipboard title="Copier l'adresse" content={tab.url} />
                <Action.CopyToClipboard
                  title="Copier en lien Markdown"
                  content={`[${tab.title}](${tab.url})`}
                  shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
                />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}

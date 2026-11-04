// Zen's open tabs in a native Raycast list, opened by Ctrl+Space (Hammerspoon) or from Raycast.
// Zen (Firefox) has no AppleScript. Mozeidon (Homebrew CLI + native app + its signed Zen add-on, native messaging)
// lists the live tabs in ~30 ms and switches in ~60 ms; Zen is then brought to the front. Without Mozeidon the list
// falls back to Zen's session file (scripts/zen-tabs.py) and the jump to Hammerspoon driving Zen's tab search (~1.5 s).
import { Action, ActionPanel, Icon, List, closeMainWindow, showToast, Toast } from "@raycast/api";
import { getFavicon } from "@raycast/utils";
import { execFile, execFileSync } from "child_process";
import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { useMemo } from "react";

type Tab = { title: string; url: string; selected: boolean; workspace: string; pinned: boolean; ref?: string };

const HS = "/opt/homebrew/bin/hs";
const MOZEIDON = "/opt/homebrew/bin/mozeidon";
const ZEN = "app.zen-browser.zen";

type MozTab = { id: number; windowId: number; pinned: boolean; url: string; title: string; active: boolean; lastAccessed: number };

function mozeidonTabs(): Tab[] | null {
  if (!existsSync(MOZEIDON)) return null;
  try {
    const out = execFileSync(MOZEIDON, ["tabs", "get"], { encoding: "utf8", timeout: 2000 });
    const data = (JSON.parse(out).data ?? []) as MozTab[];
    return data
      .filter((t) => t.url && !t.url.startsWith("about:"))
      .sort((a, b) => Number(b.active) - Number(a.active) || b.lastAccessed - a.lastAccessed)
      .map((t) => ({ title: t.title || t.url, url: t.url, selected: t.active, workspace: "", pinned: t.pinned,
        ref: `${t.windowId}:${t.id}` }));
  } catch {
    return null;
  }
}

function repoDir(): string {
  const pointer = join(homedir(), ".config/macos-config/repo");
  if (existsSync(pointer)) {
    const p = readFileSync(pointer, "utf8").trim();
    if (p) return p;
  }
  return join(homedir(), "dev/macos-config");
}

function loadTabs(): { tabs: Tab[]; error?: string } {
  const live = mozeidonTabs();
  if (live) return { tabs: live };
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
  if (tab.ref) {
    execFile(MOZEIDON, ["tabs", "switch", tab.ref], { timeout: 3000 }, (err) => {
      if (err) showToast({ style: Toast.Style.Failure, title: "Mozeidon ne répond pas", message: err.message });
      else execFile("/usr/bin/open", ["-b", ZEN]);
    });
    return;
  }
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

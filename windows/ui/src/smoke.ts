import { invoke } from '@tauri-apps/api/core';
import type { Snapshot } from './model';
declare global { interface Window { __DAEVALOG_SMOKE__?: { replay: string; holdMs: number } } }

export async function runSmoke() {
  if (!window.__DAEVALOG_SMOKE__) return;
  const checks: string[] = [];
  const check = (name: string, pass: boolean) => { if (!pass) throw Error(name); checks.push(name); };
  const waitFor = async (predicate: (s: Snapshot) => boolean) => {
    const end = Date.now() + 20000;
    while (Date.now() < end) { const s = await invoke<Snapshot>('snapshot'); if (predicate(s)) return s; await new Promise(resolve => setTimeout(resolve, 100)); }
    const s = await invoke<Snapshot>('snapshot');
    throw Error('Native state timeout: ' + JSON.stringify({ running: s.running, damage: s.state.players?.map(p => p.damage), windows: s.overlayWindows, hotkey: s.overlayHotkey, error: s.error }));
  };
  const act = (action: Record<string, unknown>) => invoke('act', { action });
  try {
    await waitFor(s => s.revision > 0);
    check('React shell rendered', !!document.querySelector('.sidebar'));
    check('Selected mint theme', getComputedStyle(document.querySelector('.app')!).getPropertyValue('--accent').trim() === '#78dbcc');
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', ctrlKey: true, bubbles: true }));
    check('Keyboard command palette focuses search', document.activeElement?.getAttribute('aria-label') === 'Search pages');
    document.querySelector('dialog')?.close();
    if (window.__DAEVALOG_SMOKE__.holdMs) {
      await waitFor(s => s.overlayWindows === 4);
      await invoke('smoke_report', { report: { phase: 'idle', overlays: 4 }, complete: false });
      await new Promise(resolve => setTimeout(resolve, window.__DAEVALOG_SMOKE__!.holdMs));
    }
    await act({ action: 'start', replay: window.__DAEVALOG_SMOKE__.replay });
    await act({ action: 'target', mode: 'allTargets' });
    await act({ action: 'focus', id: 1395 });
    const live = await waitFor(s => (s.state.players ?? []).reduce((n, p) => n + p.damage, 0) === 27200);
    check('Real daemon replay damage', live.state.players![0].damage === 27200);
    check('Real pet event', !!live.pets?.levels);
    await act({ action: 'preferences', preferences: { ...live.preferences, overlayVisible: true } });
    const overlay = await waitFor(s => s.overlayHotkey && s.overlayWindows === 4);
    check('Four native overlay HWNDs', overlay.overlayWindows === 4);
    check('Click-through starts unlocked', !overlay.overlayLocked && !overlay.overlayPassthrough);
    await act({ action: 'lockOverlay', locked: true });
    await waitFor(s => s.overlayLocked && s.overlayPassthrough);
    checks.push('All native windows set WS_EX_TRANSPARENT');
    await act({ action: 'lockOverlay', locked: false });
    await waitFor(s => !s.overlayLocked && !s.overlayPassthrough);
    checks.push('All native windows unlock');
    await act({ action: 'testAlert' });
    await waitFor(s => !!s.notice?.text.includes('Test reminder'));
    checks.push('Native reminder');
    await act({ action: 'reset' });
    await act({ action: 'history' });
    const history = await waitFor(s => s.fights.length > 0);
    check('Saved fixture listed', history.fights.some(f => f.id === 'desktop_fixture'));
    await act({ action: 'fight', id: 'desktop_fixture' });
    const detail = await waitFor(s => !!s.fight?.summary.id);
    check('History drill-down', detail.fight?.skills[0].damage === 1300);
    await act({ action: 'preferences', preferences: { ...detail.preferences, overlayVisible: false, autoStart: false, petPhase: 2 } });
    await act({ action: 'stop' });
    await waitFor(s => !s.running && !s.overlayHotkey);
    checks.push('Capture and overlay shutdown');
    await invoke('smoke_report', { report: { ok: true, checks, snapshot: await invoke('snapshot') } });
  } catch (error) {
    await invoke('smoke_report', { report: { ok: false, checks, error: String(error) } });
  }
}

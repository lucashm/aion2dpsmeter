import { invoke, isTauri } from '@tauri-apps/api/core';
import { useCallback, useEffect, useRef, useState } from 'react';
import { emptySnapshot, type Preferences, type Snapshot } from './model';

export const native = isTauri();
export async function windowAction(action: string) {
  if (native) await invoke('window_action', { action });
}
export function useCompanion() {
  const [snapshot, setSnapshot] = useState<Snapshot>(emptySnapshot);
  const [preferences, setPreferences] = useState<Preferences>(emptySnapshot.preferences);
  const [error, setError] = useState('');
  const pending = useRef(0);
  const prefs = useRef(preferences);
  const queue = useRef(Promise.resolve());
  const revision = useRef(-1);
  const command = useCallback(async (action: Record<string, unknown>) => {
    if (!native) throw new Error('Capture and native overlays are available in the Windows application.');
    try { await invoke('act', { action }); setError(''); }
    catch (e) { setError(String(e)); throw e; }
  }, []);
  const updatePreferences = useCallback((patch: Partial<Preferences>) => {
    const next = { ...prefs.current, ...patch };
    prefs.current = next; setPreferences(next); pending.current++;
    queue.current = queue.current.then(() => command({ action: 'preferences', preferences: next }))
      .catch(async () => {
        if (native && pending.current === 1) {
          try {
            const actual = await invoke<Snapshot>('snapshot');
            prefs.current = actual.preferences; setPreferences(actual.preferences);
          } catch { /* The original native command error stays visible. */ }
        }
      }).finally(() => { pending.current--; });
  }, [command]);
  useEffect(() => {
    if (!native) return;
    let disposed = false, inFlight = false;
    const poll = async () => {
      if (disposed || inFlight || document.hidden) return;
      inFlight = true;
      try {
        const next = await invoke<Snapshot>('snapshot');
        if (!disposed && next.revision !== revision.current) {
          revision.current = next.revision; setSnapshot(next);
          if (!pending.current) { prefs.current = next.preferences; setPreferences(next.preferences); }
        }
      } catch (e) { if (!disposed) setError(String(e)); }
      finally { inFlight = false; }
    };
    void poll();
    const timer = setInterval(() => void poll(), 200);
    document.addEventListener('visibilitychange', poll);
    return () => { disposed = true; clearInterval(timer); document.removeEventListener('visibilitychange', poll); };
  }, []);
  return { snapshot, preferences, updatePreferences, command, error, setError };
}

export interface Player {
  id: number; name: string; job: string; jobKey?: string; dps: number;
  damage: number; share?: number; critRate: number; isLocal?: boolean;
}
export interface Skill {
  actorId?: number; code?: number; name: string; damage: number; hits: number;
  dps?: number; critRate?: number; backRate?: number; crit?: number; back?: number;
}
export interface Combat {
  capture?: { gameRunning?: boolean; locked?: boolean; error?: string | null };
  character?: string | null; pingMs?: number | null; battleTimeMs?: number;
  targetMode?: string; skillsOf?: number | null; players?: Player[]; skills?: Skill[];
  target?: { name: string; currentHp: number; maxHp: number } | null;
}
export interface Fight {
  id: string; bossName: string; startTimeMs: number; durationMs: number;
  totalDamage: number; killed: boolean; players: Player[];
}
export interface PetCollection {
  server: number; levels: Record<string, number>; points: Record<string, number>; estimated: number[];
}
export type WidgetId = 'meter' | 'boss' | 'ping' | 'alert';
export interface Widget { id: WidgetId; enabled: boolean; x: number; y: number }
export interface Preferences {
  iface: string; autoStart: boolean; overlayVisible: boolean; opacity: number; scale: number;
  widgets: Widget[]; petPhase: number; pinnedPets: string[];
  notifyShugo: boolean; notifyInvasion: boolean; eventLead: number; sound: boolean;
}
export interface Snapshot {
  revision: number; running: boolean; replay: boolean; replayComplete: boolean; state: Combat; pets: PetCollection | null;
  fights: Fight[]; fight: { summary: Fight; skills: Skill[] } | null;
  adapters: { name: string; description: string | null; addresses: string[] }[];
  preferences: Preferences; error: string | null; notice: { text: string; expires: number } | null;
  overlayLocked: boolean; overlayHotkey: boolean; overlayPassthrough: boolean; overlayWindows: number; dataDir: string;
}
export const defaultPreferences: Preferences = {
  iface: '', autoStart: true, overlayVisible: false, opacity: 90, scale: 100,
  widgets: [{ id: 'meter', enabled: true, x: .02, y: .35 }, { id: 'boss', enabled: true, x: .35, y: .05 },
    { id: 'ping', enabled: true, x: .82, y: .85 }, { id: 'alert', enabled: true, x: .65, y: .18 }],
  petPhase: 3, pinnedPets: [], notifyShugo: true, notifyInvasion: true, eventLead: 3, sound: true,
};
export const emptySnapshot: Snapshot = {
  revision: 0, running: false, replay: false, replayComplete: false, state: {}, pets: null, fights: [], fight: null,
  adapters: [], preferences: defaultPreferences, error: null, notice: null,
  overlayLocked: false, overlayHotkey: false, overlayPassthrough: false, overlayWindows: 0, dataDir: '',
};
export const number = (n: number | undefined | null) => {
  if (n == null || !Number.isFinite(n)) return '—';
  return Math.abs(n) >= 1e6 ? (n / 1e6).toFixed(2) + 'm' : Math.abs(n) >= 1000 ? (n / 1000).toFixed(1) + 'k' : Math.round(n).toLocaleString();
};
export const duration = (ms: number) => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return s >= 3600 ? Math.floor(s / 3600) + 'h ' + Math.floor(s % 3600 / 60) + 'm' : Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
};
export const nextEvent = (now: number, minute: number) => {
  const at = Math.floor(now / 3600000) * 3600000 + minute * 60000;
  return at <= now ? at + 3600000 : at;
};
export function playerShares(players: Player[]): Player[] {
  const sum = players.reduce((n, p) => n + p.damage, 0);
  return players.map(p => ({ ...p, share: sum ? p.damage / sum * 100 : 0 }));
}
export function savedSkills(skills: Skill[], actor: number, ms: number): Skill[] {
  return skills.filter(s => s.actorId === actor).map(s => ({
    ...s, dps: s.damage / Math.max(ms / 1000, 1),
    critRate: s.hits ? (s.crit ?? 0) / s.hits : 0,
    backRate: s.hits ? (s.back ?? 0) / s.hits : 0,
  })).sort((a, b) => b.damage - a.damage);
}
export interface PetDefinition {
  name: string; genus: string; unreleased: boolean;
  drops: { npc: string; region: string; level: number; spawns: number }[];
}
export function collectionRows(all: Record<string, PetDefinition>, collection: PetCollection | null, phase: number) {
  const thresholds = [5, 25, 75];
  return Object.entries(all).filter(([, p]) => !p.unreleased).map(([id, p]) => {
    const level = collection?.levels[id] ?? 0, points = collection?.points[id] ?? 0;
    const drop = [...p.drops].sort((a, b) => a.level - b.level || b.spawns - a.spawns)[0];
    return { ...p, id, level, points, drop, estimated: collection?.estimated.includes(Number(id)) ?? false,
      remaining: Math.max(0, thresholds.slice(level, phase).reduce((n, x) => n + x, 0) - points),
      needed: collection ? level < phase : false, next: thresholds[level] ?? 0 };
  });
}

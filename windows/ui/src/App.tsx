import { createContext, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Activity, ArrowLeft, ArrowRight, Bell, Check, ChevronDown, Clock3, Crosshair, History, Home,
  Layers, LayoutGrid, Lock, MapPin, Maximize2, Minus, PawPrint, Pin, Play, Radio, RotateCcw,
  Search, Settings, ShieldCheck, Signal, Sparkles, Square, Swords, Volume2, Wind, X, Zap } from 'lucide-react';
import { native, useCompanion, windowAction } from './bridge';
import { collectionRows, duration, nextEvent, number, playerShares, savedSkills, type Combat, type Player, type Skill, type Widget, type WidgetId } from './model';
import petData from '../../../overlay/data/pets.json';

const pages = [
  { id: 'home', label: 'Overview', icon: Home },
  { id: 'combat', label: 'Combat meter', icon: Swords },
  { id: 'pets', label: 'Pet collection', icon: PawPrint },
  { id: 'overlays', label: 'Overlay studio', icon: Layers },
  { id: 'history', label: 'Fight history', icon: History },
  { id: 'alerts', label: 'Event alerts', icon: Bell },
  { id: 'settings', label: 'Settings', icon: Settings },
] as const;
type Page = typeof pages[number]['id'];
type Companion = ReturnType<typeof useCompanion> & { go: (page: Page) => void; now: number };
const Context = createContext<Companion>(null!);
const useApp = () => useContext(Context);
const classes = import.meta.glob('../../../overlay/icons/*.png', { eager: true, query: '?url', import: 'default' }) as Record<string, string>;
const classColors: Record<string, string> = { CLERIC: '#79b6ed', ASSASSIN: '#b29aee', GLADIATOR: '#e8b87c', CHANTER: '#72c9ac', SORCERER: '#bd92e1', RANGER: '#a9c77c' };
const iconFor = (job: string) => classes['../../../overlay/icons/' + job + '.png'];
function Button({ children, onClick, primary = false, disabled = false }: { children: ReactNode; onClick: () => void; primary?: boolean; disabled?: boolean }) {
  return <button className={'button ' + (primary ? 'primary' : '')} onClick={onClick} disabled={disabled}>{children}</button>;
}
function Switch({ label, on, change, disabled = false }: { label: string; on: boolean; change: (on: boolean) => void; disabled?: boolean }) {
  return <button className="switch" role="switch" aria-label={label} aria-checked={on} disabled={disabled} onClick={() => change(!on)} />;
}
function Card({ title, action, children, className = '' }: { title?: string; action?: ReactNode; children: ReactNode; className?: string }) {
  return <section className={'card ' + className}>{title && <div className="card-head"><h2>{title}</h2>{action}</div>}{children}</section>;
}
function Heading({ title, note, eyebrow, action }: { title: string; note: string; eyebrow: string; action?: ReactNode }) {
  return <div className="page-heading"><div><div className="eyebrow">{eyebrow}</div><h1>{title}</h1><p>{note}</p></div>{action}</div>;
}
function Stat({ label, value, note, icon: Icon }: { label: string; value: ReactNode; note: string; icon: typeof Activity }) {
  return <div className="stat"><div className="stat-label"><Icon size={12} />{label}</div><div className="stat-value">{value}</div><div className="stat-note">{note}</div></div>;
}
function Empty({ title, note, children }: { title: string; note: string; children?: ReactNode }) {
  return <div className="empty full-empty"><div className="event-icon"><Crosshair size={23} /></div><h2>{title}</h2><p>{note}</p>{children}</div>;
}
function useClock() {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const timer = setInterval(() => { if (!document.hidden) setNow(Date.now()); }, 1000); return () => clearInterval(timer); }, []);
  return now;
}
function send(command: Companion['command'], action: Record<string, unknown>) { void command(action).catch(() => {}); }
function connection(state: Combat, running: boolean, replay: boolean, complete = false) {
  if (replay) return running && !complete ? 'Replaying capture' : 'Replay finished';
  if (!running) return 'Capture stopped';
  if (state.capture?.locked) return 'Capturing game traffic';
  return state.capture?.gameRunning ? 'Finding game traffic' : 'Waiting for AION 2';
}

export default function App() {
  const companion = useCompanion();
  const [page, setPage] = useState<Page>(() => {
    const value = new URLSearchParams(location.search).get('page');
    return pages.some(p => p.id === value) ? value as Page : 'home';
  });
  const now = useClock();
  const search = useRef<HTMLDialogElement>(null);
  const [query, setQuery] = useState('');
  const go = (next: Page) => { setPage(next); const url = new URL(location.href); url.searchParams.set('page', next); history.replaceState(null, '', url); };
  const { snapshot: s, preferences: p, error } = companion;
  const status = connection(s.state, s.running, s.replay, s.replayComplete);
  const openSearch = () => { setQuery(''); search.current?.showModal(); search.current?.querySelector('input')?.focus(); };
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openSearch(); } };
    document.addEventListener('keydown', onKey); return () => document.removeEventListener('keydown', onKey);
  }, []);
  const windowCommand = (action: string) => { void windowAction(action).catch(e => companion.setError(String(e))); };
  return <Context.Provider value={{ ...companion, go, now }}>
    <div className="app selected-layout">
      <header className="titlebar" onMouseDown={e => { if (e.button === 0 && !(e.target as HTMLElement).closest('button')) windowCommand('drag'); }}>
        <div className="brand"><span className="brand-mark"><Wind size={19} /></span>Daevalog <small>/ AION 2</small></div>
        <div className="row"><span className="connection"><i className={'dot ' + (s.state.capture?.locked ? '' : 'off')} />{status}</span>
          <div className="row"><button className="window-button" aria-label="Minimize" onClick={() => windowCommand('minimize')}><Minus size={14} /></button><button className="window-button" aria-label="Maximize or restore" onClick={() => windowCommand('maximize')}><Square size={12} /></button><button className="window-button close" aria-label="Close to tray" onClick={() => windowCommand('hide')}><X size={15} /></button></div>
        </div>
      </header>
      {!native && <div className="preview-label">Browser preview · run the Windows application for capture, persistence and native overlays.</div>}
      {(error || s.error || s.state.capture?.error) && <div className="error-banner" role="alert"><Signal size={16} /><span>{error || s.error || s.state.capture?.error}</span><button onClick={() => go('settings')}>Open settings <ArrowRight size={13} /></button></div>}
      {s.notice && s.notice.expires > now && <div className="notice-banner" role="status"><Bell size={14} /> {s.notice.text}</div>}
      <div className="shell">
        <nav className="sidebar" aria-label="App navigation">
          {pages.map(({ id, label, icon: Icon }, i) => <div key={id}>
            {i === 1 && <div className="nav-section">IN GAME</div>}{i === 4 && <div className="nav-section">YOUR JOURNEY</div>}
            <button className={'nav-item ' + (page === id ? 'active' : '')} aria-label={label} aria-current={page === id ? 'page' : undefined} title={label} onClick={() => go(id)}><Icon size={17} /><span>{label}</span>{id === 'overlays' && <span className="badge">{p.widgets.filter(w => w.enabled).length}</span>}</button>
          </div>)}
          <div className="sidebar-foot"><div className="profile"><div className="avatar"><Wind size={20} /></div><div><b>{s.state.character || 'Your character'}</b><small>{s.pets ? 'Server ' + s.pets.server : 'Waiting for game data'}</small></div></div></div>
        </nav>
        <div className="workspace">
          <div className="toolbar"><span className="breadcrumb">Companion / <b>{pages.find(p => p.id === page)?.label}</b></span><button className="search-trigger" onClick={openSearch}><Search size={13} />Quick navigation <kbd>Ctrl K</kbd></button></div>
          <main className="main" key={page}>
            {page === 'home' ? <Overview /> : page === 'combat' ? <CombatPage /> : page === 'pets' ? <PetsPage /> : page === 'overlays' ? <OverlayPage /> : page === 'history' ? <HistoryPage /> : page === 'alerts' ? <AlertsPage /> : <SettingsPage />}
          </main>
        </div>
      </div>
      <footer className="status-strip"><span><Signal size={10} /> {s.state.pingMs != null ? s.state.pingMs + ' ms' : 'No latency reading'} · {s.replay ? 'Replay' : status}</span><span>Local-first · {p.overlayVisible ? 'Overlays on' : 'Overlays off'} · Close to tray / Quit from tray</span></footer>
    </div>
    <dialog className="search-modal" ref={search}><button className="close" aria-label="Close search" onClick={() => search.current?.close()}><X size={17} /></button><h2>Go anywhere</h2><input className="input" autoFocus aria-label="Search pages" placeholder="Search pages…" value={query} onChange={e => setQuery(e.target.value)} />{pages.filter(p => p.label.toLowerCase().includes(query.toLowerCase())).map(p => <button className="result" key={p.id} onClick={() => { search.current?.close(); go(p.id); }}><p.icon size={17} />{p.label}</button>)}</dialog>
  </Context.Provider>;
}

function BossBanner({ detail = false }: { detail?: boolean }) {
  const { snapshot: s, go } = useApp(), t = s.state.target;
  const hp = t && t.maxHp > 0 && t.currentHp >= 0 ? Math.min(100, Math.max(0, t.currentHp / t.maxHp * 100)) : null;
  return <div className="boss-banner"><div className="row spread"><div><span className={'tag ' + (s.state.capture?.locked ? 'green' : '')}>{connection(s.state, s.running, s.replay, s.replayComplete)}</span><h2>{t?.name || (s.state.players?.length ? 'Current encounter' : 'Your next encounter awaits')}</h2><p>{duration(s.state.battleTimeMs ?? 0)} elapsed · {s.state.players?.length ?? 0} players</p></div>{!detail && <Button primary onClick={() => go('combat')}><ArrowRight size={14} />Open combat</Button>}</div>{t && <><div className="boss-hp"><i style={{ width: hp == null ? '0%' : hp + '%' }} /></div><div className="row spread" style={{ marginTop: 7 }}><small>{hp == null ? 'Waiting for an HP reading' : 'Boss health · ' + hp.toFixed(1) + '%'}</small><small>{hp == null ? '' : number(t.currentHp) + ' / ' + number(t.maxHp)}</small></div></>}</div>;
}
function Party({ players, select, focused }: { players: Player[]; select?: (id: number) => void; focused?: number | null }) {
  const max = Math.max(1, ...players.map(p => p.damage));
  return <Card title="Party performance" action={<span className="tag accent">{players.length} players</span>}>{players.length ? players.map((p, i) => <button className="player player-button" key={p.id} disabled={!select} aria-pressed={focused === p.id} onClick={() => select?.(p.id)}>
    <span className="player-rank">{i + 1}</span><span className="player-name">{p.jobKey && iconFor(p.jobKey) && <img className="job-icon" src={iconFor(p.jobKey)} alt="" />}<span>{p.name}{p.isLocal && <small style={{ color: 'var(--accent)' }}>YOU</small>}</span></span>
    <span className="player-bar" style={{ color: classColors[p.jobKey ?? ''] ?? '#78dbcc' }}><i style={{ width: p.damage / max * 100 + '%', background: classColors[p.jobKey ?? ''] ?? '#78dbcc' }} /><span>{number(p.damage)} · {p.job || 'Unknown class'}</span></span><span className="player-dps">{number(p.dps)}<small>DPS</small></span>
  </button>) : <p className="inline-note">Your party appears here when the game sends combat data.</p>}</Card>;
}
function SkillTable({ skills }: { skills: Skill[] }) {
  return skills.length ? <div className="table-wrap"><table className="table skill-table"><thead><tr><th>Skill</th><th>Damage</th><th>Hits</th><th>Crit</th><th>Back</th></tr></thead><tbody>{skills.map((s, i) => <tr key={(s.code ?? 'skill') + ':' + i}><td title={s.name}>{s.name}</td><td>{number(s.damage)}</td><td>{s.hits}</td><td>{s.isDot ? '–' : ((s.critRate ?? 0) * 100).toFixed(1) + '%'}</td><td>{s.isDot ? '–' : ((s.backRate ?? 0) * 100).toFixed(1) + '%'}</td></tr>)}</tbody></table></div> : <p className="inline-note">Select a player or deal damage to see the skill breakdown.</p>;
}
const events = [{ name: 'Shugo Festival', minute: 0, key: 'notifyShugo' as const, icon: Sparkles, note: 'Hourly · community schedule' },
  { name: 'Dimensional Invasion', minute: 30, key: 'notifyInvasion' as const, icon: Wind, note: 'Hourly · community schedule' }];
function Events({ compact = false }: { compact?: boolean }) {
  const { now, preferences: p, updatePreferences } = useApp();
  return <>{events.map(e => <div className="event" key={e.key}><span className="event-icon"><e.icon size={17} /></span><div><b>{e.name}</b><small>{e.note}</small></div><span className="time">{duration(nextEvent(now, e.minute) - now)}</span>{!compact && <Switch label={e.name + ' reminder'} on={p[e.key]} change={on => updatePreferences({ [e.key]: on })} />}</div>)}</>;
}
function Overview() {
  const { snapshot: s, preferences: p, go } = useApp(), players = s.state.players ?? [], me = players.find(p => p.isLocal);
  const allPets = Object.entries(petData.pets).filter(([, p]) => !p.unreleased);
  const collected = s.pets ? allPets.filter(([id]) => s.pets!.levels[id] >= 1).length : null;
  return <>
    <Heading title={s.state.character ? 'Welcome back, ' + s.state.character + '.' : 'Your companion in Atreia.'} note="A little clarity for your time in Atreia." eyebrow="YOUR COMPANION, IN SYNC" action={<Button onClick={() => go('overlays')}><Layers size={14} />Overlay studio</Button>} />
    <div className="stats"><Stat label="Your DPS" value={number(me?.dps)} note="Your current encounter" icon={Activity} /><Stat label="Party damage" value={number(players.reduce((n, p) => n + p.damage, 0))} note={players.length + ' players · damage dealt'} icon={Swords} /><Stat label="Pets collected" value={<>{collected ?? '—'} <em>/ {allPets.length}</em></>} note={s.pets ? 'Server ' + s.pets.server : 'Awaiting your collection'} icon={PawPrint} /><Stat label="Saved encounters" value={s.fights.length} note="Most recent 200 fights" icon={History} /></div>
    <BossBanner />
    <div className="grid two"><Party players={players} /><Card title="Coming up in Atreia" action={<button className="text-button" onClick={() => go('alerts')}>Manage <ArrowRight size={12} /></button>}><Events compact /><p className="inline-note">{[p.notifyShugo, p.notifyInvasion].filter(Boolean).length} reminders enabled · {p.eventLead} minutes before</p></Card></div>
    <div className="quick-actions">{[{ page: 'overlays', title: 'Make it your own', note: 'Arrange the widgets you see in game.', icon: Layers }, { page: 'pets', title: 'One soul closer', note: 'Find the next pet for your collection.', icon: PawPrint }, { page: 'history', title: 'Know your progress', note: 'Revisit your recent encounters.', icon: History }].map(q => <button className="quick" key={q.page} onClick={() => go(q.page as Page)}><q.icon size={19} /><b>{q.title} <ArrowRight size={12} /></b><small>{q.note}</small></button>)}</div>
  </>;
}
function CombatPage() {
  const { snapshot: s, command, go } = useApp(), players = s.state.players ?? [], skills = s.state.skills ?? [];
  const modes = [['allTargets', 'All targets'], ['bossTargets', 'Bosses'], ['lastHitByMe', 'My target']];
  return <>
    <Heading title="Combat meter" note="Every hit, a clearer picture." eyebrow="LIVE ENCOUNTER" action={<Button onClick={() => go('overlays')}><Layers size={14} />Overlay studio</Button>} />
    <div className="filters"><div className="segmented" aria-label="Target filter">{modes.map(([mode, label]) => <button disabled={!s.running} key={mode} className={(s.state.targetMode || 'bossTargets') === mode ? 'active' : ''} onClick={() => send(command, { action: 'target', mode })}>{label}</button>)}</div><span className="muted" style={{ fontSize: 10 }}>Party · {players.length} players</span><div style={{ marginLeft: 'auto' }}><Button disabled={!s.running} onClick={() => send(command, { action: 'reset' })}><RotateCcw size={13} />Save & reset</Button></div></div>
    {!players.length ? <Empty title={s.running ? 'Ready when you are.' : 'Capture is stopped.'} note={s.running ? 'Waiting for AION 2 and your character. Your party’s combat numbers will appear here.' : 'Start capture in Settings, or replay a saved pcap.'}><Button primary onClick={() => go('settings')}><Signal size={14} />Capture settings</Button></Empty> : <>
      <BossBanner detail /><div className="grid combat-grid"><Party players={players} focused={s.state.skillsOf} select={id => send(command, { action: 'focus', id })} /><Card title="Skill breakdown" action={<select className="input" aria-label="Player skill breakdown" value={s.state.skillsOf ?? ''} onChange={e => send(command, { action: 'focus', id: e.target.value === '' ? null : Number(e.target.value) })}><option value="">My skills</option>{players.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select>}><SkillTable skills={skills} /></Card></div>
    </>}
  </>;
}

function PetsPage() {
  const { snapshot: s, preferences: p, updatePreferences } = useApp();
  const [search, setSearch] = useState(''), [genus, setGenus] = useState('all'), [filter, setFilter] = useState('needed'), [page, setPage] = useState(0);
  const rows = useMemo(() => collectionRows(petData.pets, s.pets, p.petPhase), [s.pets, p.petPhase]);
  const filtered = rows.filter(r => (genus === 'all' || r.genus === genus) && (filter === 'all' || filter === 'pinned' ? filter === 'all' || p.pinnedPets.includes(r.id) : !s.pets || r.needed) && (r.name.toLowerCase().includes(search.toLowerCase()) || r.drops.some(d => d.npc.toLowerCase().includes(search.toLowerCase())))).sort((a, b) => a.remaining - b.remaining || a.name.localeCompare(b.name));
  const currentPage = Math.min(page, Math.max(0, Math.ceil(filtered.length / 40) - 1));
  const toggle = (id: string) => updatePreferences({ pinnedPets: p.pinnedPets.includes(id) ? p.pinnedPets.filter(x => x !== id) : [...p.pinnedPets, id] });
  const collected = s.pets ? rows.filter(r => r.level >= 1).length : null;
  return <>
    <Heading title="A growing collection." note="Your pets, your progress, your next little victory." eyebrow="PET COLLECTION" action={<span className="tag accent">{p.pinnedPets.length} pinned for farming</span>} />
    <div className="stats"><Stat label="Collected" value={<>{collected ?? '—'} <em>/ {rows.length}</em></>} note={s.pets ? 'Server ' + s.pets.server : 'Awaiting game data'} icon={PawPrint} />{[1, 2, 3].map(l => <Stat key={l} label={'Level ' + l} value={s.pets ? rows.filter(r => r.level >= l).length : '—'} note="Pets at or above this level" icon={l === 3 ? ShieldCheck : Wind} />)}</div>
    {!s.pets && <p className="inline-note" style={{ marginBottom: 15 }}>Collection progress has not arrived yet. Log in or use a Kibelisk teleport with capture running. The catalog below is reference data.</p>}
    <div className="pet-layout"><aside className="card pet-filter"><h3>Farm toward</h3>{[1, 2, 3].map(l => <label key={l}><input type="radio" name="phase" checked={p.petPhase === l} onChange={() => updatePreferences({ petPhase: l })} />Level {l}</label>)}<hr /><h3>Genus insight</h3>{['all', 'cogni', 'fera', 'natura', 'varian', 'special'].map(g => <label key={g} style={{ textTransform: 'capitalize' }}><input type="radio" name="genus" checked={genus === g} onChange={() => { setGenus(g); setPage(0); }} />{g === 'all' ? 'All genuses' : g}</label>)}<hr /><p className="inline-note">Collect every pet first, then work toward the next level. Estimated levels are marked until the game confirms them.</p></aside>
    <div><div className="pet-toolbar"><input className="input" type="search" value={search} aria-label="Search pets or monsters" placeholder="Search pets or monsters…" onChange={e => { setSearch(e.target.value); setPage(0); }} /><select className="input" aria-label="Collection filter" value={filter} onChange={e => { setFilter(e.target.value); setPage(0); }}><option value="needed">Needed for Lv. {p.petPhase}</option><option value="all">All pets</option><option value="pinned">Pinned pets</option></select></div>
      <div className="card table-wrap" style={{ padding: '6px 10px' }}><table className="table"><thead><tr><th>Pet</th><th>Level</th><th>Souls left</th><th className="region-col">Find in</th><th>Pin</th></tr></thead><tbody>{filtered.slice(currentPage * 40, currentPage * 40 + 40).map(r => <tr key={r.id}><td><div className="pet-name"><span className={'pet-orb ' + r.genus}><PawPrint size={15} /></span><div>{r.name}<small className="pet-genus" style={{ display: 'block', marginTop: 3 }}>{r.genus}</small></div></div></td><td>{s.pets ? 'Lv. ' + r.level : '—'}{r.estimated && <small> Est.</small>}</td><td>{s.pets ? number(r.remaining) : '—'}<div className="progress"><i style={{ width: (r.next ? Math.min(100, r.points / r.next * 100) : s.pets ? 100 : 0) + '%' }} /></div></td><td className="region-col muted" title={r.drop?.npc}>{r.drop?.region || 'Collection / special'}</td><td><button className={'icon-button ' + (p.pinnedPets.includes(r.id) ? 'selected' : '')} aria-label={(p.pinnedPets.includes(r.id) ? 'Unpin ' : 'Pin ') + r.name} aria-pressed={p.pinnedPets.includes(r.id)} onClick={() => toggle(r.id)}><Pin size={13} /></button></td></tr>)}</tbody></table>{!filtered.length && <p className="inline-note" style={{ padding: 20 }}>No pets match these filters.</p>}</div>
      <div className="pager"><span>{filtered.length} pets · {s.pets ? filtered.reduce((n, r) => n + r.remaining, 0).toLocaleString() + ' souls to Lv. ' + p.petPhase : 'Progress unknown'}</span><div className="row"><Button disabled={!currentPage} onClick={() => setPage(currentPage - 1)}><ArrowLeft size={12} /></Button><span>{currentPage + 1} / {Math.max(1, Math.ceil(filtered.length / 40))}</span><Button disabled={(currentPage + 1) * 40 >= filtered.length} onClick={() => setPage(currentPage + 1)}><ArrowRight size={12} /></Button></div></div>
    </div></div>
  </>;
}

const widgetInfo: Record<WidgetId, { label: string; icon: typeof Activity; width: number; height: number }> = {
  meter: { label: 'Damage meter', icon: Activity, width: 27, height: 28 },
  boss: { label: 'Boss health', icon: Crosshair, width: 32, height: 12 },
  ping: { label: 'Latency', icon: Signal, width: 12, height: 10 },
  alert: { label: 'Event reminders', icon: Bell, width: 29, height: 13 },
};
function OverlayPage() {
  const { snapshot: s, preferences: p, updatePreferences, command } = useApp();
  const canvas = useRef<HTMLDivElement>(null);
  const [drag, setDrag] = useState<Widget | null>(null);
  const [opacityDraft, setOpacity] = useState<number | null>(null), [scaleDraft, setScale] = useState<number | null>(null);
  const opacity = opacityDraft ?? p.opacity, scale = scaleDraft ?? p.scale;
  const move = (widget: Widget, clientX: number, clientY: number) => {
    const rect = canvas.current!.getBoundingClientRect(), info = widgetInfo[widget.id];
    return { ...widget, x: Math.max(0, Math.min(1, (clientX - rect.left) / (rect.width * (1 - info.width / 100)))), y: Math.max(0, Math.min(1, (clientY - rect.top) / (rect.height * (1 - info.height / 100)))) };
  };
  const saveWidget = (widget: Widget) => updatePreferences({ widgets: p.widgets.map(w => w.id === widget.id ? widget : w) });
  return <>
    <Heading title="Your game. Your layout." note="Arrange native widgets, then lock them to pass clicks through to the game." eyebrow="OVERLAY STUDIO" action={<Button onClick={() => updatePreferences({ widgets: [{ id: 'meter', enabled: true, x: .02, y: .35 }, { id: 'boss', enabled: true, x: .35, y: .05 }, { id: 'ping', enabled: true, x: .82, y: .85 }, { id: 'alert', enabled: true, x: .65, y: .18 }] })}><RotateCcw size={13} />Reset layout</Button>} />
    <div className="overlay-actions"><Switch label="Show native overlays" on={p.overlayVisible} change={overlayVisible => updatePreferences({ overlayVisible })} /><span className="muted" style={{ fontSize: 11 }}>Show overlays</span><span className="tag accent">{p.widgets.filter(w => w.enabled).length} widgets</span><div style={{ marginLeft: 'auto' }}><Button disabled={!p.overlayVisible || !s.overlayHotkey} onClick={() => send(command, { action: 'lockOverlay', locked: !s.overlayLocked })}><Lock size={13} />{s.overlayLocked ? 'Unlock overlays' : 'Lock / click-through'}</Button></div></div>
    <div className="overlay-layout"><div className="canvas" ref={canvas} aria-label="Overlay positioning canvas">
      {p.widgets.filter(w => w.enabled).map(widget => {
        const w = drag?.id === widget.id ? drag : widget, info = widgetInfo[w.id];
        return <div key={w.id} className="widget" role="group" tabIndex={0} aria-label={info.label + ' widget, drag or use arrow keys to move'}
          style={{ left: w.x * (100 - info.width) + '%', top: w.y * (100 - info.height) + '%', width: info.width + '%', height: info.height + '%', opacity: opacity / 100 }}
          onPointerDown={e => { const rect = e.currentTarget.getBoundingClientRect(); e.currentTarget.dataset.dx = String(e.clientX - rect.left); e.currentTarget.dataset.dy = String(e.clientY - rect.top); e.currentTarget.setPointerCapture(e.pointerId); setDrag(w); }}
          onPointerMove={e => { if (e.currentTarget.hasPointerCapture(e.pointerId)) setDrag(move(w, e.clientX - Number(e.currentTarget.dataset.dx), e.clientY - Number(e.currentTarget.dataset.dy))); }}
          onPointerUp={e => { if (e.currentTarget.hasPointerCapture(e.pointerId)) { e.currentTarget.releasePointerCapture(e.pointerId); if (drag) saveWidget(drag); setDrag(null); } }}
          onKeyDown={e => { const d: Record<string, [number, number]> = { ArrowLeft: [-.01, 0], ArrowRight: [.01, 0], ArrowUp: [0, -.01], ArrowDown: [0, .01] }; if (d[e.key]) { e.preventDefault(); saveWidget({ ...w, x: Math.max(0, Math.min(1, w.x + d[e.key][0])), y: Math.max(0, Math.min(1, w.y + d[e.key][1])) }); } }}>
          <strong><info.icon size={12} /> {info.label}</strong>{w.id === 'meter' ? (s.state.players?.slice(0, 3).map(p => <div key={p.id} className="mini-bar" title={p.name} style={{ width: Math.max(5, p.share ?? 0) * 2 + '%' }} />) || <small>Waiting for combat</small>) : w.id === 'boss' ? <><small>{s.state.target?.name || 'Waiting for a target'}</small><div className="mini-bar" /></> : w.id === 'ping' ? <small>{s.state.pingMs ?? '—'} ms</small> : <small>{s.notice?.text || 'Your reminders appear here'}</small>}
        </div>;
      })}<span className="canvas-hint">Primary display anchors · layout saved on this PC</span>
    </div><aside className="card overlay-settings"><div className="card-head"><h2>On this layout</h2><Layers size={14} /></div>{p.widgets.map(w => <div className="setting-row" key={w.id}><span>{widgetInfo[w.id].label}</span><Switch label={widgetInfo[w.id].label} on={w.enabled} change={enabled => saveWidget({ ...w, enabled })} /></div>)}
      <div className="range-row">Opacity<div className="row"><input aria-label="Overlay opacity" type="range" min="30" max="100" value={opacity} onChange={e => setOpacity(Number(e.target.value))} onPointerUp={() => { updatePreferences({ opacity }); setOpacity(null); }} onKeyUp={() => { updatePreferences({ opacity }); setOpacity(null); }} /><output>{opacity}%</output></div></div>
      <div className="range-row">Widget scale<div className="row"><input aria-label="Widget scale" type="range" min="75" max="150" step="5" value={scale} onChange={e => setScale(Number(e.target.value))} onPointerUp={() => { updatePreferences({ scale }); setScale(null); }} onKeyUp={() => { updatePreferences({ scale }); setScale(null); }} /><output>{scale}%</output></div></div>
      <p className="inline-note"><kbd className="kbd">Ctrl+Alt+M</kbd> unlocks click-through. {p.overlayVisible && !s.overlayHotkey ? 'Waiting for the overlay shortcut to register.' : 'Click-through starts unlocked every launch.'}</p>
    </aside></div><p className="inline-note">Use borderless or windowed game mode. Drag native widget headers while unlocked; use this studio to save anchors on the main display.</p>
  </>;
}

function HistoryPage() {
  const { snapshot: s, command } = useApp(), [selected, setSelected] = useState<string | null>(null), [actor, setActor] = useState<number | null>(null);
  const fight = selected && s.fight?.summary.id === selected ? s.fight : null;
  const focused = actor ?? fight?.summary.players[0]?.id ?? 0;
  return <>
    <Heading title="Every encounter tells a story." note="Saved on your PC. Ready when you want a closer look." eyebrow="FIGHT HISTORY" action={<Button disabled={!s.running} onClick={() => send(command, { action: 'history' })}><RotateCcw size={13} />Refresh</Button>} />
    {selected ? <><button className="history-back" onClick={() => setSelected(null)}><ArrowLeft size={14} />All encounters</button>{fight ? <><Heading title={fight.summary.bossName || 'Encounter'} eyebrow={fight.summary.killed ? 'CLEARED' : 'ENCOUNTER'} note={new Date(fight.summary.startTimeMs).toLocaleString() + ' · ' + duration(fight.summary.durationMs)} /><div className="grid combat-grid"><Party players={playerShares(fight.summary.players)} select={setActor} focused={focused} /><Card title="Skill breakdown"><SkillTable skills={savedSkills(fight.skills, focused, fight.summary.durationMs)} /></Card></div></> : <Empty title="Loading encounter…" note="Reading the saved fight from the capture daemon." />}</> :
      s.fights.length ? <Card title="Recent encounters" action={<small>Top DPS</small>}>{s.fights.map(f => <button className="history-row" key={f.id} disabled={!s.running} onClick={() => { setSelected(f.id); setActor(null); send(command, { action: 'fight', id: f.id }); }}><span className="event-icon"><Swords size={15} /></span><span><b>{f.bossName || 'Encounter'}</b><small>{new Date(f.startTimeMs).toLocaleString()} · {f.players.length} players</small></span><span className={'tag ' + (f.killed ? 'green' : '')}>{f.killed ? 'Cleared' : 'Not cleared'}</span><span className="duration muted">{duration(f.durationMs)}</span><span className="right">{number(f.players.length ? Math.max(...f.players.map(p => p.dps)) : null)}</span></button>)}</Card> :
      <Empty title="Your story starts here." note="Boss encounters are saved automatically as they end. Start capture to load your saved history." />}
  </>;
}
function AlertsPage() {
  const { preferences: p, updatePreferences, command } = useApp();
  return <>
    <Heading title="Never miss the moment." note="A gentle reminder before your next adventure." eyebrow="EVENT ALERTS" action={<Button onClick={() => send(command, { action: 'testAlert' })}><Bell size={14} />Send test alert</Button>} />
    <div className="filters"><span className="tag accent">Hourly events</span><span className="muted" style={{ fontSize: 11 }}>Remind me</span><select className="input" aria-label="Reminder lead time" value={p.eventLead} onChange={e => updatePreferences({ eventLead: Number(e.target.value) })}>{[1, 3, 5, 10].map(n => <option key={n} value={n}>{n} minutes before</option>)}</select></div>
    <Card className="alert-table"><Events /><div className="setting-row"><span><Volume2 size={14} /> Play system reminder sound</span><Switch label="Play reminder sound" on={p.sound} change={sound => updatePreferences({ sound })} /></div><div className="setting-row"><span><Layers size={14} /> Show native overlay reminders</span><Switch label="Show native overlays" on={p.overlayVisible} change={overlayVisible => updatePreferences({ overlayVisible })} /></div></Card>
    <p className="community-note">Schedules follow the existing Linux companion’s hourly community timers (:00 / :30, UTC-aligned). These are not an official server feed. Automatic reminders run while the game is open; test alerts work at any time. Nearby cube notices come from captured game data.</p>
  </>;
}
function SettingsPage() {
  const { snapshot: s, preferences: p, updatePreferences, command } = useApp();
  const [ifaceDraft, setIface] = useState<string | null>(null), [replay, setReplay] = useState('');
  const iface = ifaceDraft ?? p.iface;
  return <>
    <Heading title="A companion that fits." note="A few thoughtful controls, right where you need them." eyebrow="PREFERENCES" />
    <div className="grid settings-grid"><Card title="Game & capture" action={<Signal size={16} />}><span className={'tag ' + (s.running ? 'green' : '')}>{connection(s.state, s.running, s.replay, s.replayComplete)}</span><p>Network adapter</p><select className="input" aria-label="Capture network adapter" value={iface} onChange={e => setIface(e.target.value)}><option value="">Automatic · default IPv4 route</option>{s.adapters.map(a => <option key={a.name} value={a.name}>{a.description || a.name} {a.addresses.join(', ')}</option>)}</select><p>For a VPN, choose the adapter carrying your game traffic. Npcap must be installed separately in WinPcap API-compatible mode.</p><div className="row wrap"><Button disabled={!native} onClick={() => send(command, { action: 'refreshAdapters' })}>Refresh adapters</Button><Button primary disabled={!native} onClick={() => { updatePreferences({ iface }); }}><Check size={13} />Save adapter</Button><Button primary disabled={!native} onClick={() => send(command, { action: 'start', replay: null })}><Play size={13} />{s.running ? 'Restart capture' : 'Start capture'}</Button>{s.running && <Button onClick={() => send(command, { action: 'stop' })}>Stop capture</Button>}</div><p>Save a changed adapter before starting capture.</p></Card>
    <Card title="Window & reminders" action={<Settings size={16} />}><div className="setting-row"><span>Start capture when Daevalog opens</span><Switch label="Start capture automatically" on={p.autoStart} change={autoStart => updatePreferences({ autoStart })} /></div><div className="setting-row"><span>Show native overlays</span><Switch label="Show native overlays" on={p.overlayVisible} change={overlayVisible => updatePreferences({ overlayVisible })} /></div><div className="setting-row"><span>Reminder sound</span><Switch label="Reminder sound preference" on={p.sound} change={sound => updatePreferences({ sound })} /></div><p>Closing the companion hides it to the tray while capture and widgets continue. Choose Quit in the tray menu to save and stop everything.</p><Button onClick={() => { void windowAction('quit'); }}>Quit Daevalog</Button></Card>
    <Card title="Replay a capture" action={<Play size={16} />}><p>Replay a .pcap file through the same Rust parser. Your live capture is stopped before replay starts.</p><input className="input" aria-label="Pcap file path" placeholder="C:\Captures\encounter.pcap" value={replay} onChange={e => setReplay(e.target.value)} /><Button disabled={!native || !replay.trim()} onClick={() => send(command, { action: 'start', replay: replay.trim() })}><Play size={13} />Start replay</Button><p>Clear the replay path and use Start capture above to return to the game.</p></Card>
    <Card title="Local by design" action={<ShieldCheck size={16} />}><p>Your combat data and pet collection stay on this PC. The Rust daemon handles packet decoding and aggregation; the companion receives only its compact state.</p><h3>Data and logs</h3><p style={{ overflowWrap: 'anywhere' }}>{s.dataDir || 'Available in the Windows app'}<br />Preferences: companion.json · Capture log: capture.log</p><p>Daevalog 0.1 · Tauri / React companion · Native Rust overlays</p></Card></div>
  </>;
}

import { describe, expect, it } from 'vitest';
import { collectionRows, nextEvent, playerShares, savedSkills, type Player } from './model';

describe('engine presentation boundary', () => {
  it('derives history shares without assuming live-only fields exist', () => {
    const players = playerShares([{ id: 1, damage: 750 }, { id: 2, damage: 250 }] as Player[]);
    expect(players.map(p => p.share)).toEqual([75, 25]);
    expect(playerShares([{ damage: 0 }] as Player[])[0].share).toBe(0);
  });
  it('uses saved hit counts and actor identity for skill rates', () => {
    const skills = savedSkills([{ actorId: 7, name: 'Hit', damage: 750, hits: 4, crit: 2, back: 1 },
      { actorId: 8, name: 'Other', damage: 500, hits: 1 }], 7, 2000);
    expect(skills).toHaveLength(1);
    expect(skills[0]).toMatchObject({ dps: 375, critRate: .5, backRate: .25 });
  });
  it('keeps unknown collection state distinct from zero progress and carries souls across levels', () => {
    const all = { '1002': { name: 'Pet', genus: 'cogni', unreleased: false, drops: [] } };
    expect(collectionRows(all, null, 3)[0].needed).toBe(false);
    const c = { server: 1, levels: { '1002': 1 }, points: { '1002': 7 }, estimated: [1002] };
    expect(collectionRows(all, c, 3)[0]).toMatchObject({ remaining: 93, estimated: true });
    expect(collectionRows(all, c, 1)[0].remaining).toBe(0);
  });
  it('suppresses saved DoT crit and back rates like the live meter', () => {
    const skills = savedSkills([{ actorId: 7, name: 'DoT', damage: 100, hits: 4,
      crit: 4, back: 2, isDot: true }], 7, 2000);
    expect(skills[0]).toMatchObject({ isDot: true, dps: 50, critRate: 0, backRate: 0 });
  });
  it('rolls the hourly schedule forward at the boundary', () => {
    expect(nextEvent(0, 0)).toBe(3600000);
    expect(nextEvent(1700000, 30)).toBe(1800000);
    expect(nextEvent(1800000, 30)).toBe(5400000);
  });
});

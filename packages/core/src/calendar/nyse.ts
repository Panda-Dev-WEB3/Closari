// NYSE sessions for the Closari calendar (Backend §1, Overview §11; checked against the NYSE hours page 2026-11-18).
// DST is resolved with Intl (America/New_York). The contract only checks that sessions are well formed.
export const COVERED_FROM = "2026-11-01";
export const COVERED_TO = "2027-12-31";

export const HOLIDAYS: ReadonlySet<string> = new Set([
  "2026-11-26",
  "2026-12-25",
  "2027-01-01",
  "2027-01-18",
  "2027-02-15",
  "2027-03-26",
  "2027-05-31",
  "2027-06-18",
  "2027-07-05",
  "2027-09-06",
  "2027-11-25",
  "2027-12-24",
]);
export const EARLY_CLOSES: ReadonlySet<string> = new Set([
  "2026-11-27",
  "2026-12-24",
  "2027-11-26",
]);

export type Session = {
  dayId: number;
  iso: string;
  openTs: number;
  closeTs: number;
  early: boolean;
};

const DAY_MS = 86_400_000;

export function dayIdOf(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  if (!y || !m || !d) throw new Error(`bad date ${iso}`);
  return Date.UTC(y, m - 1, d) / DAY_MS;
}

export function isoOf(dayId: number): string {
  return new Date(dayId * DAY_MS).toISOString().slice(0, 10);
}

const OFFSET_FMT = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/New_York",
  timeZoneName: "longOffset",
});

function nyOffsetMinutes(utcMs: number): number {
  const name =
    OFFSET_FMT.formatToParts(new Date(utcMs)).find((p) => p.type === "timeZoneName")?.value ?? "";
  const m = /GMT([+-])(\d{2}):(\d{2})/.exec(name);
  if (!m) throw new Error(`unexpected offset ${name}`);
  return (m[1] === "-" ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3]));
}

/** Unix seconds of `hour:minute` America/New_York on `iso`. Exact away from the 02:00 DST jump. */
export function etToUtcSeconds(iso: string, hour: number, minute: number): number {
  const naive = dayIdOf(iso) * DAY_MS + (hour * 60 + minute) * 60_000;
  let t = naive - nyOffsetMinutes(naive) * 60_000;
  t = naive - nyOffsetMinutes(t) * 60_000;
  return t / 1000;
}

export function sessionFor(iso: string): Session | null {
  if (iso > COVERED_TO) throw new Error(`${iso} is beyond the calendar tables (${COVERED_TO})`);
  if (iso < COVERED_FROM) throw new Error(`${iso} is before the calendar tables (${COVERED_FROM})`);
  const dayId = dayIdOf(iso);
  const weekday = new Date(dayId * DAY_MS).getUTCDay();
  if (weekday === 0 || weekday === 6 || HOLIDAYS.has(iso)) return null;
  const early = EARLY_CLOSES.has(iso);
  return {
    dayId,
    iso,
    openTs: etToUtcSeconds(iso, 9, 30),
    closeTs: etToUtcSeconds(iso, early ? 13 : 16, 0),
    early,
  };
}

export function sessionsBetween(fromIso: string, toIso: string): Session[] {
  const out: Session[] = [];
  for (let d = dayIdOf(fromIso); d <= dayIdOf(toIso); d++) {
    const s = sessionFor(isoOf(d));
    if (s) out.push(s);
  }
  return out;
}

export const haltTs = (s: Session): number => s.closeTs - 600;
export const rampStartTs = (s: Session): number => s.closeTs - 600 - 1800;

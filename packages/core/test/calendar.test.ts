import { describe, expect, test } from "bun:test";
import {
  dayIdOf,
  haltTs,
  isoOf,
  rampStartTs,
  sessionFor,
  sessionsBetween,
} from "../src/calendar/nyse.ts";

describe("NYSE calendar", () => {
  test("DST edge 2026-11-01: EDT Friday vs EST Monday", () => {
    expect(() => sessionFor("2026-10-30")).toThrow(); // before COVERED_FROM
    expect(sessionFor("2026-11-02")).toEqual({
      dayId: 20759,
      iso: "2026-11-02",
      openTs: 1793629800,
      closeTs: 1793653200,
      early: false,
    });
  });

  test("DST edge 2027-03-14: EST Friday vs EDT Monday", () => {
    expect(sessionFor("2027-03-12")).toMatchObject({
      dayId: 20889,
      openTs: 1804861800,
      closeTs: 1804885200,
    });
    expect(sessionFor("2027-03-15")).toMatchObject({
      dayId: 20892,
      openTs: 1805117400,
      closeTs: 1805140800,
    });
  });

  test("early closes at 13:00 ET", () => {
    expect(sessionFor("2026-11-27")).toMatchObject({
      dayId: 20784,
      openTs: 1795789800,
      closeTs: 1795802400,
      early: true,
    });
    expect(sessionFor("2026-12-24")).toMatchObject({
      dayId: 20811,
      openTs: 1798122600,
      closeTs: 1798135200,
      early: true,
    });
  });

  test("holidays and weekends are closed", () => {
    expect(sessionFor("2026-11-26")).toBeNull();
    expect(sessionFor("2026-12-25")).toBeNull();
    expect(sessionFor("2026-11-21")).toBeNull();
    expect(sessionFor("2026-11-22")).toBeNull();
  });

  test("halt and fee-ramp start", () => {
    const s = sessionFor("2026-11-23");
    expect(s).not.toBeNull();
    if (!s) return;
    expect(s.openTs).toBe(1795444200);
    expect(haltTs(s)).toBe(1795467600 - 600);
    expect(rampStartTs(s)).toBe(1795467600 - 600 - 1800);
  });

  test("day ids round-trip and ranges are bounded", () => {
    expect(dayIdOf("2026-11-23")).toBe(20780);
    expect(isoOf(20780)).toBe("2026-11-23");
    expect(() => sessionFor("2028-01-03")).toThrow();
    const nov = sessionsBetween("2026-11-01", "2026-11-30");
    expect(nov.length).toBe(20); // 21 weekdays minus Thanksgiving
  });
});

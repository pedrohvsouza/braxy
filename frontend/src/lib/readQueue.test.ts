import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "./api";
import { queueRead, READ_WINDOW_MS, resetReadQueue } from "./readQueue";

describe("queueRead", () => {
  let calls: [number, number][];

  beforeEach(() => {
    vi.useFakeTimers();
    calls = [];
    vi.spyOn(api, "markRead").mockImplementation(async (cid, mid) => {
      calls.push([cid, mid]);
      return { ok: true };
    });
  });

  afterEach(() => {
    resetReadQueue();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("sends the first receipt at once and folds a burst into one trailing request", () => {
    queueRead(1, 10);
    expect(calls).toEqual([[1, 10]]);
    queueRead(1, 11);
    queueRead(1, 12);
    queueRead(1, 11); // older ids never go backwards
    expect(calls).toHaveLength(1);
    vi.advanceTimersByTime(READ_WINDOW_MS);
    expect(calls).toEqual([[1, 10], [1, 12]]);
    vi.advanceTimersByTime(READ_WINDOW_MS * 3);
    expect(calls).toHaveLength(2);
  });

  it("skips ids already sent and keeps conversations apart", () => {
    queueRead(1, 5);
    queueRead(2, 7);
    queueRead(1, 5);
    vi.advanceTimersByTime(READ_WINDOW_MS);
    expect(calls).toEqual([[1, 5], [2, 7]]);
    queueRead(1, 6); // window closed: goes out at once
    expect(calls).toEqual([[1, 5], [2, 7], [1, 6]]);
  });
});

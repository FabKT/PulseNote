export function textTimeoutMs(value) {
  if (value === undefined || String(value).trim() === '') return 0;
  const timeout = Number(value);
  if (!Number.isSafeInteger(timeout) || timeout < 0 || timeout > 2147483647) {
    throw new Error('TEXT_TIMEOUT_MS must be 0 (unlimited) or a valid duration in milliseconds.');
  }
  return timeout;
}

export function textTimeoutOptions(timeout) {
  return timeout > 0 ? { signal: AbortSignal.timeout(timeout) } : {};
}

export function textDeadline(timeout, now = Date.now()) {
  return timeout > 0 ? now + timeout : Infinity;
}

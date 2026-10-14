import assert from 'node:assert/strict';
import { test } from 'node:test';
import { textTimeoutMs, textTimeoutOptions, textDeadline } from './text-timeout.js';

test('default and zero disable the total generation deadline and abort signal', () => {
  assert.equal(textTimeoutMs(undefined), 0);
  assert.equal(textTimeoutMs('0'), 0);
  assert.equal(textDeadline(0), Infinity);
  assert.deepEqual(textTimeoutOptions(0), {});
});

test('operators can opt into a bounded duration without a hidden 20 minute minimum', () => {
  assert.equal(textTimeoutMs('3600000'), 3600000);
  assert.equal(textDeadline(3600000, 1000), 3601000);
  assert.equal(textTimeoutMs('500'), 500);
  for (const value of ['invalid', '-1', 'Infinity', '2147483648'])
    assert.throws(() => textTimeoutMs(value));
});

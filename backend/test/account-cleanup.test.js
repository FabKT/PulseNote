import assert from 'node:assert/strict';
import test from 'node:test';

import {
  removeStoragePaths,
  removeStoragePrefix,
} from '../src/account-cleanup.js';

function fakeStorage({ pages = new Map() } = {}) {
  const removed = [];
  return {
    removed,
    from(bucket) {
      return {
        async list(prefix, options) {
          const key = `${bucket}:${prefix}:${options.offset}`;
          return { data: pages.get(key) || [], error: null };
        },
        async remove(paths) {
          removed.push(paths);
          return { error: null };
        },
      };
    },
  };
}

test('removeStoragePrefix paginates beyond the first 1000 files', async () => {
  const firstPage = Array.from({ length: 1000 }, (_, index) => ({
    id: `id-${index}`,
    name: `audio-${index}.m4a`,
  }));
  const storage = fakeStorage({
    pages: new Map([
      ['friend-audio:user-1:0', firstPage],
      [
        'friend-audio:user-1:1000',
        [{ id: 'id-1000', name: 'audio-1000.m4a' }],
      ],
    ]),
  });

  const removed = await removeStoragePrefix(
    storage,
    'friend-audio',
    'user-1',
  );

  assert.equal(removed, 1001);
  assert.equal(storage.removed.length, 11);
  assert.equal(storage.removed.flat().length, 1001);
});

test('removeStoragePrefix also traverses nested folders', async () => {
  const storage = fakeStorage({
    pages: new Map([
      [
        'recordings-audio:user-1:0',
        [
          { id: 'root-file', name: 'root.m4a' },
          { id: null, name: 'archive' },
        ],
      ],
      [
        'recordings-audio:user-1/archive:0',
        [{ id: 'nested-file', name: 'nested.m4a' }],
      ],
    ]),
  });

  await removeStoragePrefix(storage, 'recordings-audio', 'user-1');

  assert.deepEqual(storage.removed.flat().sort(), [
    'user-1/archive/nested.m4a',
    'user-1/root.m4a',
  ]);
});

test('removeStoragePaths de-duplicates referenced message audio', async () => {
  const storage = fakeStorage();

  const removed = await removeStoragePaths(storage, 'friend-audio', [
    'friend-2/message.m4a',
    'friend-2/message.m4a',
  ]);

  assert.equal(removed, 1);
  assert.deepEqual(storage.removed, [['friend-2/message.m4a']]);
});

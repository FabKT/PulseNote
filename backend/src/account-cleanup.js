const storagePageSize = 1000;
const storageDeleteBatchSize = 100;

async function listStorageFiles(storage, bucket, prefix) {
  const files = [];
  let offset = 0;

  while (true) {
    const { data, error } = await storage.from(bucket).list(prefix, {
      limit: storagePageSize,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    });
    if (error) throw error;

    const entries = data || [];
    for (const entry of entries) {
      if (!entry?.name) continue;
      const entryPath = `${prefix}/${entry.name}`;
      if (entry.id) {
        files.push(entryPath);
      } else {
        files.push(...(await listStorageFiles(storage, bucket, entryPath)));
      }
    }

    if (entries.length < storagePageSize) break;
    offset += entries.length;
  }

  return files;
}

export async function removeStoragePaths(storage, bucket, paths) {
  const uniquePaths = [...new Set(paths.filter(Boolean))];
  for (let index = 0; index < uniquePaths.length; index += storageDeleteBatchSize) {
    const batch = uniquePaths.slice(index, index + storageDeleteBatchSize);
    const { error } = await storage.from(bucket).remove(batch);
    if (error) throw error;
  }
  return uniquePaths.length;
}

export async function removeStoragePrefix(storage, bucket, prefix) {
  const paths = await listStorageFiles(storage, bucket, prefix);
  return removeStoragePaths(storage, bucket, paths);
}

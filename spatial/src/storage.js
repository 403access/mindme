// Persist the imported library in IndexedDB. The file never leaves the
// headset; clearing storage removes it completely.

const DB_NAME = 'mindme-spatial';
const DB_VERSION = 1;
const STORE = 'library';
const KEY = 'active';

function openDB() {
  return new Promise((resolve, reject) => {
    if (!('indexedDB' in window)) {
      reject(new Error('IndexedDB is unavailable in this browser.'));
      return;
    }
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('Could not open local storage.'));
  });
}

export async function saveLibraryJSON(json, meta = {}) {
  // Ask the browser not to evict this origin's data when space is tight.
  try {
    await navigator.storage?.persist?.();
  } catch {
    // Optional API; storage still works without it.
  }
  const db = await openDB();
  await new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE, 'readwrite');
    transaction.objectStore(STORE).put({ json, savedAt: Date.now(), ...meta }, KEY);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error ?? new Error('Could not store the library.'));
  });
  db.close();
}

export async function loadLibraryJSON() {
  const db = await openDB();
  const record = await new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE, 'readonly');
    const request = transaction.objectStore(STORE).get(KEY);
    request.onsuccess = () => resolve(request.result ?? null);
    request.onerror = () => reject(request.error ?? new Error('Could not read the stored library.'));
  });
  db.close();
  return record;
}

export async function clearLibraryJSON() {
  const db = await openDB();
  await new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE, 'readwrite');
    transaction.objectStore(STORE).delete(KEY);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error ?? new Error('Could not clear stored data.'));
  });
  db.close();
}

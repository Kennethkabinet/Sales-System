const API_BASE = process.env.API_BASE || 'http://localhost:3000/api';
const TEST_USERNAME = process.env.TEST_USERNAME || 'admin';
const TEST_PASSWORD = process.env.TEST_PASSWORD || 'admin123';

async function request(method, path, body, token) {
  const response = await fetch(`${API_BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  let data = null;
  try {
    data = await response.json();
  } catch (_) {
    data = null;
  }

  return { status: response.status, data };
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function main() {
  const login = await request('POST', '/auth/login', {
    username: TEST_USERNAME,
    password: TEST_PASSWORD,
  });

  assert(login.status === 200, `Login failed: status ${login.status}`);
  const token = login.data?.token;
  assert(token, 'Login response missing token');

  const filesRoot = await request('GET', '/files?page=1&limit=200&folder_id=root', null, token);
  assert(filesRoot.status === 200, `GET /files root failed: ${filesRoot.status}`);
  const inventoryFileRoot = (filesRoot.data?.folders || []).find((folder) => folder.name === 'Inventory');
  assert(inventoryFileRoot?.id, 'Inventory folder not found in /files root');

  const validFileCreate = await request(
    'POST',
    '/files/folders',
    { name: `test-file-child-${Date.now()}`, parent_id: inventoryFileRoot.id },
    token
  );
  assert(validFileCreate.status === 201, `Valid file folder create failed: ${validFileCreate.status}`);
  assert(
    validFileCreate.data?.folder?.parent_id === inventoryFileRoot.id,
    `File folder parent mismatch. expected=${inventoryFileRoot.id}, actual=${validFileCreate.data?.folder?.parent_id}`
  );

  const invalidFileParent = await request('POST', '/files/folders', {
    name: 'bad-file-parent',
    parent_id: 'abc',
  }, token);
  assert(invalidFileParent.status === 400, `Invalid file parent should be 400, got ${invalidFileParent.status}`);

  const missingFileParent = await request('POST', '/files/folders', {
    name: 'missing-file-parent',
    parent_id: 99999999,
  }, token);
  assert(missingFileParent.status === 404, `Missing file parent should be 404, got ${missingFileParent.status}`);

  const sheetsRoot = await request('GET', '/sheets?folder_id=root&page=1&limit=200', null, token);
  assert(sheetsRoot.status === 200, `GET /sheets root failed: ${sheetsRoot.status}`);
  const inventorySheetRoot = (sheetsRoot.data?.folders || []).find((folder) => folder.name === 'Inventory');
  assert(inventorySheetRoot?.id, 'Inventory folder not found in /sheets root');

  const validSheetCreate = await request(
    'POST',
    '/sheets/folders',
    { name: `test-sheet-child-${Date.now()}`, parent_id: inventorySheetRoot.id },
    token
  );
  assert(validSheetCreate.status === 201, `Valid sheet folder create failed: ${validSheetCreate.status}`);
  assert(
    validSheetCreate.data?.folder?.parent_id === inventorySheetRoot.id,
    `Sheet folder parent mismatch. expected=${inventorySheetRoot.id}, actual=${validSheetCreate.data?.folder?.parent_id}`
  );

  const invalidSheetParent = await request('POST', '/sheets/folders', {
    name: 'bad-sheet-parent',
    parent_id: 'abc',
  }, token);
  assert(invalidSheetParent.status === 400, `Invalid sheet parent should be 400, got ${invalidSheetParent.status}`);

  const missingSheetParent = await request('POST', '/sheets/folders', {
    name: 'missing-sheet-parent',
    parent_id: 99999999,
  }, token);
  assert(missingSheetParent.status === 404, `Missing sheet parent should be 404, got ${missingSheetParent.status}`);

  console.log('folder_creation_smoke: PASS');
}

main().catch((error) => {
  console.error('folder_creation_smoke: FAIL');
  console.error(error.message || error);
  process.exit(1);
});

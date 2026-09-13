import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = process.argv[2];
const check = !source || source === '--check';
const receiptPath = 'docs/design/aim-mini-apps.receipt.json';
const receiptBytes = await readFile(check ? resolve(root, receiptPath) : resolve(source, 'aim-mini-apps.receipt.json'));
const receipt = JSON.parse(receiptBytes);
if (receipt.schema !== 'aim.mini-apps.receipt/v1') throw new Error('Unsupported design receipt');
const entries = await Promise.all(Object.entries(receipt.artifacts).map(async ([name, expected]) => {
  if (!/^[\w.-]+$/.test(name)) throw new Error('Invalid artifact name');
  const target = name === 'AIMMiniAppTokens.swift' ? `native/${name}` : `docs/design/${name}`;
  const bytes = await readFile(check ? resolve(root, target) : resolve(source, name));
  const actual = createHash('sha256').update(bytes).digest('hex');
  if (actual !== expected) throw new Error(`Design artifact mismatch: ${name}`);
  return { target, bytes };
}));
if (!check) {
  await mkdir(resolve(root, 'docs/design'), { recursive: true });
  for (const { target, bytes } of entries) await writeFile(resolve(root, target), bytes);
  await writeFile(resolve(root, receiptPath), receiptBytes);
}
console.log(`PASS: N1 ${receipt.version}; ${entries.length} verified artifacts; source ${receipt.sourceSHA256}`);

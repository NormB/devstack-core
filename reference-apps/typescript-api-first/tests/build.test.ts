/**
 * Build verification test
 *
 * Ensures that all TypeScript code compiles successfully
 * and the compiled output exists.
 */

import { existsSync } from 'fs';
import { join } from 'path';

describe('TypeScript Build', () => {
  const distPath = join(__dirname, '..', 'dist');

  test('dist directory should exist', () => {
    expect(existsSync(distPath)).toBe(true);
  });

  test('compiled index.js should exist', () => {
    expect(existsSync(join(distPath, 'index.js'))).toBe(true);
  });

  test('compiled config.js should exist', () => {
    expect(existsSync(join(distPath, 'config.js'))).toBe(true);
  });

  test('compiled types directory should exist', () => {
    expect(existsSync(join(distPath, 'types'))).toBe(true);
  });

  test('compiled routes directory should exist', () => {
    expect(existsSync(join(distPath, 'routes'))).toBe(true);
  });

  test('compiled services directory should exist', () => {
    expect(existsSync(join(distPath, 'services'))).toBe(true);
  });

  test('compiled middleware directory should exist', () => {
    expect(existsSync(join(distPath, 'middleware'))).toBe(true);
  });
});

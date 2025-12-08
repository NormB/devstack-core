/**
 * Jest Test Setup for TypeScript
 *
 * Global setup for all tests.
 */

// Set test environment
process.env.NODE_ENV = 'test';

// Increase timeout for async operations
jest.setTimeout(10000);

// Global afterAll to close any open handles
afterAll(async () => {
  await new Promise(resolve => setTimeout(resolve, 500));
});

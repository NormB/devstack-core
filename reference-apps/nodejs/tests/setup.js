/**
 * Jest Test Setup
 *
 * Global setup for all tests.
 */

// Set test environment
process.env.NODE_ENV = 'test';

// Increase timeout for async operations
jest.setTimeout(10000);

// Global afterAll to close any open handles
afterAll(async () => {
  // Give time for any async operations to complete
  await new Promise(resolve => setTimeout(resolve, 500));
});

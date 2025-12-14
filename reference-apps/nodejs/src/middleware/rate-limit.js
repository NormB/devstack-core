/**
 * Rate Limiting Middleware
 *
 * Provides IP-based rate limiting using express-rate-limit.
 * Matches FastAPI baseline rate limiting configuration.
 */

const rateLimit = require('express-rate-limit');
const config = require('../config');
const { logger } = require('./logging');

/**
 * Default rate limiter for most endpoints
 * 100 requests per minute per IP
 */
const defaultLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 100, // 100 requests per minute
  standardHeaders: true, // Return rate limit info in headers
  legacyHeaders: false, // Disable X-RateLimit-* headers
  message: {
    error: 'Too Many Requests',
    message: 'Rate limit exceeded. Please try again later.',
    retry_after_seconds: 60
  },
  handler: (req, res, next, options) => {
    logger.warn('Rate limit exceeded', {
      requestId: req.requestId,
      ip: req.ip,
      path: req.path
    });
    res.status(429).json(options.message);
  },
  // Use default key generator (handles IPv6 properly)
  validate: { xForwardedForHeader: false }
});

/**
 * Stricter rate limiter for sensitive endpoints
 * 10 requests per minute per IP
 */
const strictLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10, // 10 requests per minute
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Too Many Requests',
    message: 'Rate limit exceeded for sensitive endpoint. Please try again later.',
    retry_after_seconds: 60
  },
  handler: (req, res, next, options) => {
    logger.warn('Strict rate limit exceeded', {
      requestId: req.requestId,
      ip: req.ip,
      path: req.path
    });
    res.status(429).json(options.message);
  },
  validate: { xForwardedForHeader: false }
});

/**
 * Higher rate limiter for metrics/health endpoints
 * 1000 requests per minute per IP
 */
const highLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 1000, // 1000 requests per minute
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Too Many Requests',
    message: 'Rate limit exceeded.',
    retry_after_seconds: 60
  },
  validate: { xForwardedForHeader: false }
});

/**
 * Create a custom rate limiter with specified limits
 * @param {Object} options - Rate limit options
 * @param {number} options.windowMs - Time window in milliseconds
 * @param {number} options.max - Maximum requests per window
 * @returns {Function} Express middleware
 */
function createRateLimiter({ windowMs = 60000, max = 100 } = {}) {
  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      error: 'Too Many Requests',
      message: 'Rate limit exceeded. Please try again later.',
      retry_after_seconds: Math.ceil(windowMs / 1000)
    },
    validate: { xForwardedForHeader: false }
  });
}

module.exports = {
  defaultLimiter,
  strictLimiter,
  highLimiter,
  createRateLimiter
};

/**
 * CORS Middleware Configuration
 *
 * Configure Cross-Origin Resource Sharing for API access.
 */

const cors = require('cors');
const config = require('../config');

// CORS configuration
const corsOptions = {
  origin: config.env === 'production'
    ? process.env.ALLOWED_ORIGINS?.split(',') || []
    : '*', // Allow all origins in development
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'X-Request-ID',
    'X-Api-Key'
  ],
  exposedHeaders: ['X-Request-ID', 'X-RateLimit-Limit', 'X-RateLimit-Remaining'],
  credentials: true,
  maxAge: 86400, // 24 hours
  optionsSuccessStatus: 200
};

const corsMiddleware = cors(corsOptions);

module.exports = {
  corsMiddleware,
  corsOptions
};

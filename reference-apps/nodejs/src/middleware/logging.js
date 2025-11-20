/**
 * Logging Middleware
 *
 * Provides structured logging using Winston with request correlation IDs.
 */

const winston = require('winston');
const { v4: uuidv4 } = require('uuid');
const config = require('../config');

// Create logger instance
const logger = winston.createLogger({
  level: config.debug ? 'debug' : 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: {
    service: config.app.name,
    environment: config.env
  },
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    })
  ]
});

/**
 * Express middleware for request logging with correlation IDs
 */
function loggingMiddleware(req, res, next) {
  // Generate or extract request ID
  const requestId = req.headers['x-request-id'] || uuidv4();
  req.requestId = requestId;

  // Add request ID to response headers
  res.setHeader('X-Request-ID', requestId);

  // Log request
  const startTime = Date.now();

  logger.info('Incoming request', {
    requestId,
    method: req.method,
    path: req.path,
    ip: req.ip,
    userAgent: req.get('user-agent')
  });

  // Log response
  res.on('finish', () => {
    const duration = Date.now() - startTime;

    logger.info('Request completed', {
      requestId,
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration: `${duration}ms`
    });
  });

  next();
}

module.exports = {
  logger,
  loggingMiddleware
};

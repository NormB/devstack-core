/**
 * CORS middleware configuration
 */

import cors from 'cors';

// Default CORS origins aligned with other reference implementations
const allowedOrigins = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',')
  : [
      'http://localhost:3000',   // React/Next.js dev server
      'http://localhost:8000',   // FastAPI code-first
      'http://localhost:8001',   // FastAPI API-first
      'http://localhost:8005',   // TypeScript API-first
      'http://localhost:8080',   // Common dev port
      'http://127.0.0.1:3000',
      'http://127.0.0.1:8000',
      'http://127.0.0.1:8001',
      'http://127.0.0.1:8005',
      'http://127.0.0.1:8080',
    ];

export const corsMiddleware = cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (like mobile apps or curl requests)
    if (!origin) {
      return callback(null, true);
    }

    if (allowedOrigins.indexOf(origin) !== -1 || process.env.NODE_ENV === 'development') {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-ID']
});

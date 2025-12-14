/**
 * Request Validation Middleware
 *
 * Provides request validation patterns to match FastAPI's Pydantic validation.
 * Uses a simple schema-based approach without heavy dependencies.
 */

const { logger } = require('./logging');

/**
 * Validation error class
 */
class ValidationError extends Error {
  constructor(message, errors = []) {
    super(message);
    this.name = 'ValidationError';
    this.errors = errors;
  }
}

/**
 * Validate required fields in request body
 * @param {string[]} fields - Required field names
 * @returns {Function} Express middleware
 */
function requireFields(fields) {
  return (req, res, next) => {
    const errors = [];

    for (const field of fields) {
      if (req.body[field] === undefined || req.body[field] === null) {
        errors.push({
          field,
          message: `Field '${field}' is required`
        });
      }
    }

    if (errors.length > 0) {
      logger.warn('Validation failed: missing required fields', {
        requestId: req.requestId,
        errors
      });

      return res.status(400).json({
        error: 'Validation Error',
        message: 'Missing required fields',
        details: errors,
        requestId: req.requestId
      });
    }

    next();
  };
}

/**
 * Validate field types in request body
 * @param {Object} schema - Field type mapping { fieldName: 'string'|'number'|'boolean'|'array'|'object' }
 * @returns {Function} Express middleware
 */
function validateTypes(schema) {
  return (req, res, next) => {
    const errors = [];

    for (const [field, expectedType] of Object.entries(schema)) {
      const value = req.body[field];

      if (value !== undefined && value !== null) {
        let actualType = typeof value;

        if (Array.isArray(value)) {
          actualType = 'array';
        }

        if (actualType !== expectedType) {
          errors.push({
            field,
            message: `Field '${field}' must be of type '${expectedType}', got '${actualType}'`,
            expected: expectedType,
            actual: actualType
          });
        }
      }
    }

    if (errors.length > 0) {
      logger.warn('Validation failed: type mismatch', {
        requestId: req.requestId,
        errors
      });

      return res.status(400).json({
        error: 'Validation Error',
        message: 'Invalid field types',
        details: errors,
        requestId: req.requestId
      });
    }

    next();
  };
}

/**
 * Validate field constraints
 * @param {Object} constraints - Field constraints { fieldName: { min, max, minLength, maxLength, pattern, enum } }
 * @returns {Function} Express middleware
 */
function validateConstraints(constraints) {
  return (req, res, next) => {
    const errors = [];

    for (const [field, rules] of Object.entries(constraints)) {
      const value = req.body[field];

      if (value === undefined || value === null) {
        continue; // Skip undefined/null values (use requireFields for required validation)
      }

      // Numeric constraints
      if (typeof value === 'number') {
        if (rules.min !== undefined && value < rules.min) {
          errors.push({
            field,
            message: `Field '${field}' must be at least ${rules.min}`,
            constraint: 'min',
            value,
            limit: rules.min
          });
        }

        if (rules.max !== undefined && value > rules.max) {
          errors.push({
            field,
            message: `Field '${field}' must be at most ${rules.max}`,
            constraint: 'max',
            value,
            limit: rules.max
          });
        }
      }

      // String constraints
      if (typeof value === 'string') {
        if (rules.minLength !== undefined && value.length < rules.minLength) {
          errors.push({
            field,
            message: `Field '${field}' must be at least ${rules.minLength} characters`,
            constraint: 'minLength',
            value: value.length,
            limit: rules.minLength
          });
        }

        if (rules.maxLength !== undefined && value.length > rules.maxLength) {
          errors.push({
            field,
            message: `Field '${field}' must be at most ${rules.maxLength} characters`,
            constraint: 'maxLength',
            value: value.length,
            limit: rules.maxLength
          });
        }

        if (rules.pattern !== undefined) {
          const regex = new RegExp(rules.pattern);
          if (!regex.test(value)) {
            errors.push({
              field,
              message: `Field '${field}' does not match required pattern`,
              constraint: 'pattern',
              pattern: rules.pattern
            });
          }
        }
      }

      // Enum constraint
      if (rules.enum !== undefined && !rules.enum.includes(value)) {
        errors.push({
          field,
          message: `Field '${field}' must be one of: ${rules.enum.join(', ')}`,
          constraint: 'enum',
          value,
          allowed: rules.enum
        });
      }
    }

    if (errors.length > 0) {
      logger.warn('Validation failed: constraint violation', {
        requestId: req.requestId,
        errors
      });

      return res.status(400).json({
        error: 'Validation Error',
        message: 'Constraint validation failed',
        details: errors,
        requestId: req.requestId
      });
    }

    next();
  };
}

/**
 * Validate URL parameters
 * @param {Object} paramSchema - Parameter validation rules { paramName: { type, pattern, min, max } }
 * @returns {Function} Express middleware
 */
function validateParams(paramSchema) {
  return (req, res, next) => {
    const errors = [];

    for (const [param, rules] of Object.entries(paramSchema)) {
      const value = req.params[param];

      if (value === undefined) {
        if (rules.required) {
          errors.push({
            param,
            message: `URL parameter '${param}' is required`
          });
        }
        continue;
      }

      // Type coercion and validation
      if (rules.type === 'number') {
        const numValue = Number(value);
        if (isNaN(numValue)) {
          errors.push({
            param,
            message: `URL parameter '${param}' must be a valid number`,
            value
          });
        } else {
          req.params[param] = numValue;

          if (rules.min !== undefined && numValue < rules.min) {
            errors.push({
              param,
              message: `URL parameter '${param}' must be at least ${rules.min}`,
              value: numValue,
              limit: rules.min
            });
          }

          if (rules.max !== undefined && numValue > rules.max) {
            errors.push({
              param,
              message: `URL parameter '${param}' must be at most ${rules.max}`,
              value: numValue,
              limit: rules.max
            });
          }
        }
      }

      // Pattern validation
      if (rules.pattern !== undefined) {
        const regex = new RegExp(rules.pattern);
        if (!regex.test(value)) {
          errors.push({
            param,
            message: `URL parameter '${param}' does not match required pattern`,
            value,
            pattern: rules.pattern
          });
        }
      }

      // Enum validation
      if (rules.enum !== undefined && !rules.enum.includes(value)) {
        errors.push({
          param,
          message: `URL parameter '${param}' must be one of: ${rules.enum.join(', ')}`,
          value,
          allowed: rules.enum
        });
      }
    }

    if (errors.length > 0) {
      logger.warn('Validation failed: invalid URL parameters', {
        requestId: req.requestId,
        errors
      });

      return res.status(400).json({
        error: 'Validation Error',
        message: 'Invalid URL parameters',
        details: errors,
        requestId: req.requestId
      });
    }

    next();
  };
}

/**
 * Validate query parameters
 * @param {Object} querySchema - Query parameter validation rules
 * @returns {Function} Express middleware
 */
function validateQuery(querySchema) {
  return (req, res, next) => {
    const errors = [];

    for (const [param, rules] of Object.entries(querySchema)) {
      const value = req.query[param];

      if (value === undefined) {
        if (rules.required) {
          errors.push({
            query: param,
            message: `Query parameter '${param}' is required`
          });
        }
        continue;
      }

      // Type coercion for numbers
      if (rules.type === 'number') {
        const numValue = Number(value);
        if (isNaN(numValue)) {
          errors.push({
            query: param,
            message: `Query parameter '${param}' must be a valid number`,
            value
          });
        } else {
          req.query[param] = numValue;

          if (rules.min !== undefined && numValue < rules.min) {
            errors.push({
              query: param,
              message: `Query parameter '${param}' must be at least ${rules.min}`,
              value: numValue,
              limit: rules.min
            });
          }

          if (rules.max !== undefined && numValue > rules.max) {
            errors.push({
              query: param,
              message: `Query parameter '${param}' must be at most ${rules.max}`,
              value: numValue,
              limit: rules.max
            });
          }
        }
      }

      // Boolean coercion
      if (rules.type === 'boolean') {
        if (value === 'true' || value === '1') {
          req.query[param] = true;
        } else if (value === 'false' || value === '0') {
          req.query[param] = false;
        } else {
          errors.push({
            query: param,
            message: `Query parameter '${param}' must be a boolean (true/false)`,
            value
          });
        }
      }

      // Enum validation
      if (rules.enum !== undefined && !rules.enum.includes(value)) {
        errors.push({
          query: param,
          message: `Query parameter '${param}' must be one of: ${rules.enum.join(', ')}`,
          value,
          allowed: rules.enum
        });
      }
    }

    if (errors.length > 0) {
      logger.warn('Validation failed: invalid query parameters', {
        requestId: req.requestId,
        errors
      });

      return res.status(400).json({
        error: 'Validation Error',
        message: 'Invalid query parameters',
        details: errors,
        requestId: req.requestId
      });
    }

    next();
  };
}

/**
 * Combined validator that runs multiple validations
 * @param {Object} options - Validation options
 * @param {string[]} options.required - Required body fields
 * @param {Object} options.types - Field types
 * @param {Object} options.constraints - Field constraints
 * @param {Object} options.params - URL parameter rules
 * @param {Object} options.query - Query parameter rules
 * @returns {Function[]} Array of middleware functions
 */
function validate(options = {}) {
  const middlewares = [];

  if (options.required && options.required.length > 0) {
    middlewares.push(requireFields(options.required));
  }

  if (options.types && Object.keys(options.types).length > 0) {
    middlewares.push(validateTypes(options.types));
  }

  if (options.constraints && Object.keys(options.constraints).length > 0) {
    middlewares.push(validateConstraints(options.constraints));
  }

  if (options.params && Object.keys(options.params).length > 0) {
    middlewares.push(validateParams(options.params));
  }

  if (options.query && Object.keys(options.query).length > 0) {
    middlewares.push(validateQuery(options.query));
  }

  return middlewares;
}

module.exports = {
  ValidationError,
  requireFields,
  validateTypes,
  validateConstraints,
  validateParams,
  validateQuery,
  validate
};

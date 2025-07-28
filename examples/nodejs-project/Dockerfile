# ================================================================
# Node.js Application Dockerfile
# Multi-stage build for optimized production image
# ================================================================

# Build stage
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY yarn.lock* ./

# Install dependencies
RUN if [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
    else npm ci --only=production && npm cache clean --force; fi

# Copy source code
COPY . .

# Build application
RUN if [ -f yarn.lock ]; then yarn build; else npm run build; fi

# Production stage
FROM node:18-alpine AS production

# Add non-root user for security
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

WORKDIR /app

# Install production dependencies only
COPY package*.json ./
COPY yarn.lock* ./
RUN if [ -f yarn.lock ]; then yarn install --frozen-lockfile --production; \
    else npm ci --only=production && npm cache clean --force; fi

# Copy built application from builder stage
COPY --from=builder --chown=nextjs:nodejs /app/dist ./dist
COPY --from=builder --chown=nextjs:nodejs /app/src ./src

# Copy other necessary files
COPY --chown=nextjs:nodejs . .

# Switch to non-root user
USER nextjs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Start application
CMD ["node", "src/index.js"]
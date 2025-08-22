FROM node:20-alpine AS base

# Install dependencies only when needed
FROM base AS deps
RUN apk add --no-cache libc6-compat openssl
WORKDIR /app

# Copy entire workspace for dependency resolution
COPY . .

# Install dependencies
RUN yarn install --immutable

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app ./

# Environment variables for build
ARG NEXT_PUBLIC_WEBAPP_URL
ARG NEXT_PUBLIC_API_V2_URL
ARG NEXT_PUBLIC_LICENSE_CONSENT
ARG NEXT_PUBLIC_IS_E2E
ARG CALCOM_TELEMETRY_DISABLED
ARG DATABASE_URL
ARG NEXTAUTH_SECRET
ARG CALENDSO_ENCRYPTION_KEY

ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL
ENV NEXT_PUBLIC_API_V2_URL=$NEXT_PUBLIC_API_V2_URL  
ENV NEXT_PUBLIC_LICENSE_CONSENT=$NEXT_PUBLIC_LICENSE_CONSENT
ENV NEXT_PUBLIC_IS_E2E=$NEXT_PUBLIC_IS_E2E
ENV CALCOM_TELEMETRY_DISABLED=$CALCOM_TELEMETRY_DISABLED
ENV DATABASE_URL=$DATABASE_URL
ENV NEXTAUTH_SECRET=$NEXTAUTH_SECRET
ENV CALENDSO_ENCRYPTION_KEY=$CALENDSO_ENCRYPTION_KEY
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=8192"
ENV BUILD_STANDALONE=true
ENV NEXT_TELEMETRY_DISABLED=1
ENV SKIP_ENV_VALIDATION=1

# Generate Prisma client
RUN yarn workspace @calcom/prisma run generate-schemas

# Build dependencies first
RUN yarn workspace @calcom/trpc build

# Build the web application with reduced memory usage
RUN yarn workspace @calcom/web build --no-lint

# Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

# Install runtime dependencies for Prisma
RUN apk add --no-cache openssl

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy the built application
COPY --from=builder /app/apps/web/public ./apps/web/public
COPY --from=builder /app/apps/web/.next/standalone ./
COPY --from=builder /app/apps/web/.next/static ./apps/web/.next/static

# Copy node_modules and other necessary files
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/turbo.json ./turbo.json
COPY --from=builder /app/package.json ./package.json

USER nextjs

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["node", "apps/web/server.js"]
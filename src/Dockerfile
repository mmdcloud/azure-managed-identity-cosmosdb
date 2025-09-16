# Use official Node.js LTS image
FROM node:20-alpine AS base

# Set working directory
WORKDIR /app

# Copy only package.json and package-lock.json first (to leverage Docker caching)
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application source code
COPY . .

# Set environment variables
ENV NODE_ENV=production
ENV PORT=8080

# Expose the app port
EXPOSE 8080

# Run the application
CMD ["node", "index.js"]
FROM node:24-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY dist/ ./dist/

ENV NODE_ENV=production

EXPOSE 8080

CMD ["node", "dist/main.js"]

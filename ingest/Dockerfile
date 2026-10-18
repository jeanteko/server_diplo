# node 20 klein
FROM node:20-alpine
WORKDIR /app
# zuerst nur package.json, dann bibliotheken installieren
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force
COPY server.js ./
#nicht als admin laufen
USER node
EXPOSE 3000
CMD ["node", "server.js"]
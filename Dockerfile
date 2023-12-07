FROM node:20

USER node

COPY --chown=node:node ./vite-project /home/node/vite-project
WORKDIR /home/node/vite-project
RUN npm ci && npm run build

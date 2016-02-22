# Dockerfile for the registry
FROM node:0.12

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY package.json /usr/src/app/

RUN apt-get update
RUN apt-get install -y libicu-dev

RUN npm install
COPY . /usr/src/app

CMD [ "npm", "start" ]

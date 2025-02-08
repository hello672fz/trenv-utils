FROM jialianghuang/of-watchdog as watchdog
FROM jialianghuang/hybrid as build

COPY --from=watchdog /fwatchdog /usr/bin/fwatchdog
RUN chmod +x /usr/bin/fwatchdog

ARG ADDITIONAL_PACKAGE
# Alternatively use ADD https:// (which will not be cached by Docker builder)

RUN apt-get -qy update \
    && apt-get -qy install ${ADDITIONAL_PACKAGE} \
    && rm -rf /var/lib/apt/lists/*

# Add non root user
RUN addgroup --system app && adduser app --system --ingroup app && chmod 777 /run && chmod 777 /tmp

USER app

# Turn down the verbosity to default level.
ENV NPM_CONFIG_LOGLEVEL warn

RUN mkdir -p /home/app/function

WORKDIR /home/app/
COPY --chown=app:app index.js package.json           ./

USER root
RUN npm i
USER app

WORKDIR /home/app/function/
COPY --chown=app:app function/*.json	.
USER root
RUN npm i
USER app
COPY --chown=app:app function/   .

##############################################
# Another step to copy the /home/app out

# docker build --build-arg http_proxy=http://172.17.0.1:7890 \
#   --build-arg https_proxy=http://172.17.0.1:7890 \
#   --target=package --output type=local,dest=/some/path .
##############################################
FROM scratch as package
COPY --from=build /home/app /

##############################################
# Start test
##############################################

FROM build as test

WORKDIR /home/app/function
RUN npm test

##############################################
# Finish test
# Start final
##############################################

FROM build as ship
WORKDIR /home/app/

USER app

ARG UPSTREAM_PORT=3000

# Set up of-watchdog for HTTP mode
ENV fprocess="node index.js"
ENV cgi_headers="true"
ENV mode="http"
ENV upstream_url="http://127.0.0.1:${UPSTREAM_PORT}"
ENV upstream_port=${UPSTREAM_PORT}

ENV exec_timeout="10s"
ENV write_timeout="15s"
ENV read_timeout="15s"

ENV prefix_logs="false"

HEALTHCHECK --interval=5s CMD [ -e /tmp/.lock ] || exit 1

CMD ["fwatchdog"]

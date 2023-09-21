FROM --platform=${TARGETPLATFORM:-linux/amd64} ghcr.io/openfaas/of-watchdog:0.9.10 as watchdog
FROM jialianghuang/hybrid as build

COPY --from=watchdog /fwatchdog /usr/bin/fwatchdog
RUN chmod +x /usr/bin/fwatchdog

ARG ADDITIONAL_PACKAGE
# Alternatively use ADD https:// (which will not be cached by Docker builder)

RUN apt-get -qy update \
    && apt-get -qy install ${ADDITIONAL_PACKAGE} \
    && rm -rf /var/lib/apt/lists/*

# Add non root user
RUN addgroup --system app && adduser app --system --ingroup app

USER app

ENV PATH=$PATH:/home/app/.local/bin

SHELL ["/bin/bash", "-c"]
WORKDIR /home/app/

COPY --chown=app:app index.py           .
USER app

RUN mkdir -p function
RUN touch ./function/__init__.py
WORKDIR /home/app/function/
COPY --chown=app:app function/requirements.txt	.
RUN source /home/app/faas/bin/activate && pip install --no-cache-dir -r requirements.txt
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

ARG TEST_COMMAND=tox
WORKDIR /home/app/function
SHELL ["/bin/sh", "-c"]
ARG TEST_ENABLED=true
RUN [ "$TEST_ENABLED" = "false" ] && echo "skipping tests" || (source faas/bin/activate && eval "$TEST_COMMAND")

##############################################
# Finish test
# Start final
##############################################

FROM build as ship
WORKDIR /home/app/

USER app

# Set up of-watchdog for HTTP mode
ENV fprocess="python index.py"
ENV cgi_headers="true"
ENV mode="http"
ENV upstream_url="http://127.0.0.1:5000"

HEALTHCHECK --interval=5s CMD [ -e /tmp/.lock ] || exit 1

CMD ["fwatchdog"]

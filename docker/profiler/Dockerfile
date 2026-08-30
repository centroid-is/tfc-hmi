# Reads the Dart VM Service of the `flutter` container and reports on what the
# app is spending its time on. Build context is the repository root:
#
#   docker build -f docker/profiler/Dockerfile -t hmi-profiler .
#
# The script is stdlib-only on purpose — no pip install, so this image is a
# base image plus one file, and it builds in seconds.
FROM python:3.13-alpine

# psql is the only thing added beyond the interpreter. The database section
# shells out to it rather than taking a driver dependency: ~2 MB here against a
# wheel that has to match the interpreter, and it keeps hmi_profiler.py
# importable from a plain checkout with no install step.
RUN apk add --no-cache postgresql17-client

RUN adduser -D -u 1000 profiler \
    && mkdir -p /reports \
    && chown profiler:profiler /reports

COPY tools/hmi_profiler.py /usr/local/bin/hmi_profiler.py
RUN chmod 0555 /usr/local/bin/hmi_profiler.py

USER profiler
WORKDIR /reports

# The compose service shares the flutter container's network namespace, so the
# app's VM service is on this container's own loopback.
ENV HMI_VM_SERVICE_URI=ws://127.0.0.1:8181/ws
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["python3", "/usr/local/bin/hmi_profiler.py"]
CMD ["watch"]

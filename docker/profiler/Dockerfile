# Reads the Dart VM Service of the `flutter` container and reports on what the
# app is spending its time on. Build context is the repository root:
#
#   docker build -f docker/profiler/Dockerfile -t hmi-profiler .
#
# The script is stdlib-only on purpose — no pip install, so this image is a
# base image plus one file, and it builds in seconds.
FROM python:3.13-alpine

RUN adduser -D -u 1000 profiler \
    && mkdir -p /reports \
    && chown profiler:profiler /reports

COPY tools/hmi_profiler.py /usr/local/bin/hmi_profiler.py
RUN chmod 0555 /usr/local/bin/hmi_profiler.py

USER profiler
WORKDIR /reports

# Overridden by compose; the default is what you want when running the image
# by hand against the compose network.
ENV HMI_VM_SERVICE_URI=ws://flutter:8181/ws
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["python3", "/usr/local/bin/hmi_profiler.py"]
CMD ["watch"]

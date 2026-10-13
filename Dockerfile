# One image per commit, run unchanged on staging and production. It holds the
# code and the locked dependencies, and no setting: each environment passes its
# own at run time. .env.example lists them all. To try it locally:
#
#     docker build -t mathutrice .
#     docker run --env-file .env -p 8000:8000 mathutrice
FROM python:3.14.7-slim

COPY --from=ghcr.io/astral-sh/uv:0.12.22 /uv /bin/uv

# The base image is already the Python of .python-version: uv uses it rather
# than downloading another.
ENV UV_PYTHON_DOWNLOADS=never \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# The dependencies first, in a layer of their own, so that a commit touching
# only the code reuses it. The dev group (tach) stays out. The project itself
# is not installed: uvicorn imports mathutrice from the working directory, as
# it does on a contributor's machine.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --locked --no-dev --no-install-project

COPY mathutrice ./mathutrice

# At run time the application writes the SQLite file in the working directory
# and uploaded PDFs in mathutrice/rag_documents. The process runs as an
# unprivileged user that owns these two directories and nothing else.
RUN useradd --system --no-create-home app \
    && mkdir -p mathutrice/rag_documents \
    && chown app /app mathutrice/rag_documents
USER app

# The commit the image is built from (`--build-arg REVISION=…`). The application
# sends it back in the X-Revision header, so a deploy knows which image answers.
# Last, so that it does not invalidate the cached layers above.
ARG REVISION=unknown
ENV REVISION=$REVISION

# One process, as the README starts it: uvicorn serves the routes, and its
# lifespan creates the tables, seeds the missing rows and starts the scheduler
# that cleans old conversations up. `exec` makes uvicorn the container's main
# process, so the platform's stop signal reaches it and it shuts down cleanly.
EXPOSE 8000
CMD ["sh", "-c", "exec uvicorn mathutrice.app:app --host 0.0.0.0 --port \"${PORT:-8000}\""]

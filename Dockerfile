FROM haskell:9.6-slim

WORKDIR /app

# Install newer libpq (postgresql-libpq requires >= 14)
# Bullseye GPG signatures are stale, so we temporarily allow insecure repos
# to install curl/gnupg, then add the PostgreSQL apt repo with its own key.
RUN echo 'Acquire::AllowInsecureRepositories "true";' > /etc/apt/apt.conf.d/99insecure \
    && apt-get update \
    && apt-get install -y --allow-unauthenticated \
       curl \
       gnupg \
       lsb-release \
       pkg-config \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y libpq-dev \
    && rm /etc/apt/apt.conf.d/99insecure \
    && rm -rf /var/lib/apt/lists/*

# Copy cabal files first for dependency caching
COPY veritas.cabal cabal.project ./
RUN cabal update && cabal build --only-dependencies --enable-tests -j4 2>&1 || true

# Copy source and build
COPY . .
RUN cabal build exe:veritas

CMD ["cabal", "run", "veritas"]

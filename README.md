# Kv App

# Development

Copy `.env.example` and adjust for development:

```sh
cp .env.example .env.d
```

Source the development environment:

```sh
set -a; .env.d; set +a;
```

Start development server:

```sh
r d
```

# Test

Copy `.env.example` and adjust for test:

```sh
cp .env.example .env.t
```

Source the test environment:

```sh
set -a; .env.t; set +a;
```

Start test server:

```sh
r d
```

Run non-distributed tests:

```sh
r t
```

Run all tests including distributed tests:

Get chokidar cli (if you do not have it already):

```sh
npm install --global chokidar-cli
```

Run tests:

```sh
r t.a
```

# Production

## Storage server

Copy `.env.example` and adjust for storage server:

```sh
cp .env.example .env.p.storage
```

Ensure to change `RELEASE_NAME` to `kv_storage` (see `mix.exs`)

Start storage server:

```sh
docker compose up p
```

## Interface server

Copy `.env.example` and adjust for interface server:

```sh
cp .env.example .env.p.server
```

Ensure to change `RELEASE_NAME` to `kv_server` (see `mix.exs`)

Start interface server:

```sh
docker compose up p
```

Start telnet:

```sh
r tel
```

Send commands via telnet from interface server:

```
CREATE shopping

PUT shopping milk 1

GET shopping
```

# inpxer

OPDS 1.1 and web server for `.inpx` libraries with full-text search.

## Usage

### Standalone

Download the latest release.
Download [`inpxer-example.toml`](./inpxer-example.toml), rename to `inpxer.toml`, put next to executable (or current working directory) and edit to your liking.

Import data:
```shell
./inpxer import ./file.inpx
```

You can specify `--partial` flag to import only new records and keep old ones.
Otherwise, old index data will be deleted (the whole folder specified in `index_path`) and reindex from scratch.

Start server:
```shell
./inpxer serve
```

Web interface will be available on [http://localhost:8080/](http://localhost:8080/) and
OPDS will be on [http://localhost:8080/opds](http://localhost:8080/opds) by default.

### Docker

Download [`inpxer-example.toml`](./inpxer-example.toml), rename to `inpxer.toml` and edit to your liking.

inpxer expects config file to be at `/data/inpxer.toml`.

Images are published to GitHub Container Registry (GHCR): `ghcr.io/hedger/inpxer`.

#### Quick start: auto-import on first run

Set `INPX_FILE` to the path of your `.inpx` file (mounted inside the container). The entrypoint will:
- Check if `/data/index` exists and matches the `.inpx` version;
- Import (reindex) if missing or mismatched;
- Start the server.

```shell
docker run --rm -it \
	-e INPX_FILE=/import/flibusta_fb2_local.inpx \
	-v ./import/:/import \
	-v ./data/:/data \
	-p 8080:8080 \
	ghcr.io/hedger/inpxer:latest
	# If you built locally instead, use: inpxer:latest
```

Optional flags via env vars:
- `PARTIAL_IMPORT=true` to only add new records (do not delete old ones)
- `KEEP_DELETED=true` to keep records marked as Deleted in INP

#### Manual import, then serve

You can still run import explicitly and then start the server:

```shell
# Import (may delete existing index unless PARTIAL_IMPORT is used)
docker run --rm -it \
	-v ./import/:/import \
	-v ./data/:/data \
	ghcr.io/hedger/inpxer:latest \
	inpxer import /import/file.inpx

# Start server
docker run -it \
	-p 8080:8080 \
	-v ./data/:/data \
	ghcr.io/hedger/inpxer:latest
```

#### Data volumes and layout

The container expects a single writable volume mounted at `/data` that contains:

- `/data/inpxer.toml` — configuration file. See `inpxer-example.toml` for all options. Key fields:
	- `index_path = "/data/index"` (default in example)
	- `library_path = "/data/library"` — where your actual book files are stored
- `/data/index` — the index directory created by `inpxer` (bleve and badger/bolt subfolders). This can be large.
- `/data/library` — your library files (fb2, fb2.zip, epub, etc.). Required for downloads to work via OPDS/web.

Additionally, for first-run auto-import, mount a read-only helper volume at `/import` pointing to the directory that contains your `.inpx` file and set `INPX_FILE=/import/yourfile.inpx`.

On subsequent runs (when you don’t want to re-index), you can omit the `/import` volume and the `INPX_FILE` environment variable.

#### Permissions note

- The container runs as a non-root user (`app`) and will ensure `/data/index` is writable at startup. If `/data` is a bind mount owned by root on the host, the entrypoint will adjust ownership/permissions of `/data/index` inside the container.
- To avoid a chown on startup (useful with large existing indexes), you can pre-chown the host directory to UID/GID `10000:10000` or run with an explicit user:

```shell
docker run -it -p 8080:8080 \
	--user 10000:10000 \
	-v <path to data storage>:/data \
	ghcr.io/hedger/inpxer:latest
```

#### docker-compose example (optional)

```yaml
services:
	inpxer:
		image: ghcr.io/hedger/inpxer:latest
		environment:
			INPX_FILE: /import/file.inpx
			# PARTIAL_IMPORT: "true"
			# KEEP_DELETED: "true"
		ports:
			- "8080:8080"
		volumes:
				- ./data:/data # contains inpxer.toml, index/, and library/ (as configured)
				- ./import:/import # folder with your .inpx file (for first run)
		# Uncomment to avoid chown inside container if host dir is pre-owned by 10000:10000
		# user: "10000:10000"
```

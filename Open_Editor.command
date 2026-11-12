#!/bin/sh
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec /usr/bin/open -a Cursor "$project_dir"

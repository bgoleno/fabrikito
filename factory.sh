#!/usr/bin/env bash
# Deprecated name of fabrikito, kept for one release (#261) so a pinned checkout or a script that
# calls factory.sh still works. Remove this file when that release has passed.
# $0 may be a symlink, called from any folder: resolve it before looking for fabrikito next to it.
src=${BASH_SOURCE[0]}
while [ -L "$src" ]; do
  d=$(cd "$(dirname "$src")" && pwd)
  src=$(readlink "$src")
  case $src in /*) ;; *) src=$d/$src ;; esac
done
HERE=$(cd "$(dirname "$src")" && pwd)
echo "factory.sh is deprecated; use fabrikito" >&2
exec "$HERE/fabrikito" "$@"

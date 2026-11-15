#!/bin/bash
. $(dirname $0)/config.sh

# Source of the peaks isolation data (osm_id;lon;lat;isolation per line, '#' = comment).
# The upstream file was replaced by a stub of comments only (2026-10-31): when the
# download gives no data, fall back to the archived copy kept in this repository.
url=https://geo.dianacht.de/topo/topographic_isolation_viefinderpanoramas.txt
archive=$(dirname $0)/archives/topographic_isolation_viefinderpanoramas.txt.gz

echo "creating the otm_isolation column to hold isolation information of peaks..."
psql -d $db -c "ALTER TABLE planet_osm_point ADD COLUMN IF NOT EXISTS otm_isolation integer;" || exit 1

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

echo "Downloading isolation data..."
wget -q $url -O - \
    | grep -v '^#' \
    | awk -F';' '{print $1";"$NF}' > "$TMPFILE"

if [ ! -s "$TMPFILE" ]; then
    echo "WARNING: nothing downloaded from $url, using the archived copy $archive" >&2
    zcat "$archive" \
        | grep -v '^#' \
        | awk -F';' '{print $1";"$NF}' > "$TMPFILE"
fi

if [ ! -s "$TMPFILE" ]; then
    echo "ERROR: no peak isolation data (download and archive both empty)" >&2
    exit 1
fi
echo "$(wc -l < "$TMPFILE") peaks to import"

# Note: psql does not interpolate :'variables' inside \copy, so the file name is
# expanded by the shell (unquoted here-document: no other $ must appear below).
echo "Bulk import via temp table + single UPDATE JOIN..."
psql -d $db -v ON_ERROR_STOP=1 << ENDSQL || exit 1
CREATE TEMP TABLE _iso_import (osm_id bigint, isolation integer);
\copy _iso_import FROM '$TMPFILE' WITH (FORMAT CSV, DELIMITER ';')
UPDATE planet_osm_point p
    SET otm_isolation = i.isolation
    FROM _iso_import i
    WHERE p.osm_id = i.osm_id;
DROP TABLE _iso_import;
ENDSQL
echo "done"

echo "Creating index on otm_isolation..."
psql -d $db -c "CREATE INDEX IF NOT EXISTS idx_peaks_isolation ON planet_osm_point (otm_isolation) WHERE \"natural\" IN ('peak', 'volcano') or amenity = 'parking';"
echo "done"

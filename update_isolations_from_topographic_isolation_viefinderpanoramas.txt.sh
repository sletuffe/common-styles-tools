#Alternatively, if the isolations calculation is too long, you can download the computed dominance from :
# https://geo.dianacht.de/topo/topographic_isolation_viefinderpanoramas.txt

. $(dirname $0)/config.sh

echo "creating the otm_isolation column to hold isolation information of peaks..."
psql -d $db -c "ALTER TABLE planet_osm_point ADD COLUMN IF NOT EXISTS otm_isolation integer;"

echo "Downloading isolation data..."
TMPFILE=$(mktemp)
wget -q https://geo.dianacht.de/topo/topographic_isolation_viefinderpanoramas.txt -O - \
    | grep -v '^#' \
    | awk -F';' '{print $1";"$NF}' > "$TMPFILE"
echo "$(wc -l < $TMPFILE) peaks to import"

echo "Bulk import via temp table + single UPDATE JOIN..."
psql -d $db -v tmpfile="$TMPFILE" << 'ENDSQL'
CREATE TEMP TABLE _iso_import (osm_id bigint, isolation integer);
\copy _iso_import FROM :'tmpfile' WITH (FORMAT CSV, DELIMITER ';')
UPDATE planet_osm_point p
    SET otm_isolation = i.isolation
    FROM _iso_import i
    WHERE p.osm_id = i.osm_id;
DROP TABLE _iso_import;
ENDSQL

rm "$TMPFILE"
echo "done"

echo "Creating index on otm_isolation..."
psql -d $db -c "CREATE INDEX IF NOT EXISTS idx_peaks_isolation ON planet_osm_point (otm_isolation) WHERE \"natural\" IN ('peak', 'volcano') or amenity = 'parking';"
echo "done"

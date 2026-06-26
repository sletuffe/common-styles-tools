#!/bin/bash

cd $(dirname $0)
. $(dirname $0)/config.sh

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== run-everything START ==="

log "arealabel.sql..."
cat arealabel.sql | psql $db
log "arealabel.sql OK"

log "pitchicon.sql..."
cat pitchicon.sql | psql $db
log "pitchicon.sql OK"

log "stationdirection.sql..."
cat stationdirection.sql | psql $db
log "stationdirection.sql OK"

log "viewpointdirection.sql..."
cat viewpointdirection.sql | psql $db
log "viewpointdirection.sql OK"

log "update_isolations_from_topographic_isolation_viefinderpanoramas.txt.sh..."
./update_isolations_from_topographic_isolation_viefinderpanoramas.txt.sh
log "update_isolations OK"

log "update_lowzoom_in_gis.sh..."
./update_lowzoom_in_gis.sh
log "update_lowzoom_in_gis OK"

log "update_parking.sh..."
./update_parking.sh
log "update_parking OK"

log "=== run-everything DONE ==="

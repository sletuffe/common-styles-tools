#!/bin/bash

# IDEA for 2026 : I'm unsure about its performances : Only add a simplified_way column to planet_osm_polygon and populate it with ?
# UPDATE planet_osm_polygon SET simplified_way=ST_SimplifyPreserveTopology(way,150) WHERE (\"natural\" = 'water' OR waterway = 'riverbank' OR water='lake' OR landuse IN ('basin','reservoir')) AND way_area > 50000;
#
# OR 2025-11-15, maybe even better, let the work of simplified geometries done by osm2pgsql on import with the flex output
# FIXME sly 2023-07-15 all of this has to be tested first !


# Configuration
. $(dirname $0)/config.sh

# 1. WATER
echo "Processing water polygons..."
psql -d $db -c "DROP TABLE IF EXISTS water;"
psql -d $db -c "CREATE TABLE water AS 
    SELECT ST_SimplifyPreserveTopology(way,150) AS way, name, \"natural\", waterway, way_area 
    FROM planet_osm_polygon 
    WHERE (\"natural\" = 'water' OR waterway = 'riverbank' OR water='lake' OR landuse IN ('basin','reservoir')) 
    AND way_area > 50000;"
psql -d $db -c "CREATE INDEX water_way_idx ON water USING GIST (way);"

# 2. LANDUSE
echo "Processing landuse polygons..."
psql -d $db -c "DROP TABLE IF EXISTS landuse;"
psql -d $db -c "CREATE TABLE landuse AS 
    SELECT ST_SimplifyPreserveTopology(way,150) AS way, landuse, \"natural\" 
    FROM planet_osm_polygon 
    WHERE (landuse = 'forest' OR \"natural\" = 'wood') 
    AND way_area > 50000;"
psql -d $db -c "CREATE INDEX landuse_way_idx ON landuse USING GIST (way);"

   
# 3. ROADS
echo "Processing roads..."
psql -d $db -c "DROP TABLE IF EXISTS roads;"
psql -d $db -c "CREATE TABLE roads AS 
    SELECT ST_SimplifyPreserveTopology(way,100) AS way, highway, ref 
    FROM planet_osm_line 
    WHERE highway IN ('motorway','trunk','primary','secondary','tertiary','motorway_link','trunk_link','primary_link','secondary_link','tertiary_link');"
psql -d $db -c "CREATE INDEX roads_way_idx ON roads USING GIST (way);"

# 4. BORDERS
echo "Processing borders..."
psql -d $db -c "DROP TABLE IF EXISTS borders;"
psql -d $db -c "CREATE TABLE borders AS 
    SELECT ST_SimplifyPreserveTopology(way,150) AS way, boundary, admin_level 
    FROM planet_osm_line 
    WHERE boundary = 'administrative' AND admin_level IN ('2','4','5','6');"
psql -d $db -c "CREATE INDEX borders_way_idx ON borders USING GIST (way);"

# 5. RAILWAYS
echo "Processing railways..."
psql -d $db -c "DROP TABLE IF EXISTS railways;"
psql -d $db -c "CREATE TABLE railways AS 
    SELECT ST_SimplifyPreserveTopology(way,50) AS way, railway, \"service\", tunnel 
    FROM planet_osm_line 
    WHERE (\"service\" IS NULL AND railway IN ('rail','light_rail'));"
psql -d $db -c "CREATE INDEX railways_way_idx ON railways USING GIST (way);"
    
# 6. CITIES
echo "Processing cities and towns..."
psql -d $db -c "DROP TABLE IF EXISTS cities;"
psql -d $db -c "CREATE TABLE cities AS 
    SELECT way, admin_level, name, capital, place, population::integer 
    FROM planet_osm_point 
    WHERE place IN ('city','town') 
    AND (population IS NULL OR population SIMILAR TO '[[:digit:]]+') 
    AND (population IS NULL OR population::integer > 5000);"
psql -d $db -c "CREATE INDEX cities_way_idx ON cities USING GIST (way);"

# 7. WATER LABELS (Union de plusieurs sources)
echo "Processing water labels..."
psql -d $db -c "DROP TABLE IF EXISTS lakelabels;"
psql -d $db -c "CREATE TABLE lakelabels AS 
    SELECT arealabel(osm_id,way) AS way, name, 'lakeaxis'::text AS label, way_area FROM planet_osm_polygon WHERE (\"natural\" = 'water' OR water='lake' OR landuse IN ('basin','reservoir')) AND name IS NOT NULL
    UNION ALL
    SELECT arealabel(osm_id,way) AS way, name, 'bayaxis'::text AS label, way_area FROM planet_osm_polygon WHERE \"natural\" = 'bay' AND name IS NOT NULL
    UNION ALL
    SELECT arealabel(osm_id,way) AS way, name, 'straitaxis'::text AS label, way_area FROM planet_osm_polygon WHERE \"natural\" = 'strait' AND name IS NOT NULL
    UNION ALL
    SELECT ST_LineMerge(ST_Collect(way)) AS way, MAX(name) AS name, 'straitaxis'::text AS label, (SUM(ST_Length(way))*SUM(ST_Length(way))/10)::real AS way_area FROM planet_osm_line WHERE \"natural\"='strait' AND name IS NOT NULL GROUP BY osm_id
    UNION ALL
    SELECT arealabel(osm_id,way) AS way, name, 'glacieraxis'::text AS label, way_area FROM planet_osm_polygon WHERE \"natural\" = 'glacier' AND name IS NOT NULL;"
psql -d $db -c "CREATE INDEX lakelabels_way_idx ON lakelabels USING GIST (way);"

# 8. NATURAL AREA LABELS
echo "Processing natural labels..."
# On garde les index sur les tables sources pour la performance de la requête complexe
psql -d $db -c "CREATE INDEX IF NOT EXISTS planet_osm_polygon_osm_id ON planet_osm_polygon (osm_id);" &
psql -d $db -c "CREATE INDEX IF NOT EXISTS planet_osm_line_osm_id ON planet_osm_line (osm_id);" &
wait

psql -d $db -c "DROP TABLE IF EXISTS naturalarealabels;"
psql -d $db -c "CREATE TABLE naturalarealabels AS 
    SELECT * FROM (
        SELECT natural_arealabel(osm_id,way) as way, name, areatype, way_area, (hierarchicregions).nextregionsize, (hierarchicregions).subregionsize 
        FROM (
            SELECT osm_id, way, name, (CASE WHEN \"natural\" IS NOT NULL THEN \"natural\" ELSE \"region:type\" END) AS areatype, way_area, OTM_Next_Natural_Area_Size(osm_id,way_area,way) AS hierarchicregions 
            FROM planet_osm_polygon 
            WHERE (\"region:type\" IN ('natural_area','mountain_area') OR \"natural\" IN ('massif', 'mountain_range', 'valley','couloir','ridge','arete','gorge','canyon')) 
            AND name IS NOT NULL
        ) AS areas
        UNION ALL
        SELECT way, name, \"natural\" AS areatype, (ST_Length(way)*ST_Length(way)/10)::real as way_area, (OTM_Next_Natural_Area_Size(osm_id,0.0,way)).nextregionsize, (OTM_Next_Natural_Area_Size(osm_id,0.0,way)).subregionsize 
        FROM planet_osm_line AS li 
        WHERE \"natural\" IN ('massif', 'mountain_range', 'valley','couloir','ridge','arete','gorge','canyon') 
        AND name IS NOT NULL 
        AND NOT EXISTS (SELECT 1 FROM planet_osm_polygon AS po WHERE po.osm_id=li.osm_id)
    ) AS combined_natural;"
psql -d $db -c "CREATE INDEX naturalarealabels_way_idx ON naturalarealabels USING GIST (way);"

echo "Done!"

#!/bin/bash
# rollen mit kennwort aus der .env anlegen
set -e #bei fehler abbrechen

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
-- rolle fuer schnittstelle
CREATE ROLE akku_ingest LOGIN PASSWORD '$DB_INGEST_PASSWORD';
GRANT CONNECT ON DATABASE akku TO akku_ingest; -- darf verbinden
GRANT USAGE ON SCHEMA public TO akku_ingest;
GRANT INSERT ON messwerte, auth_events TO akku_ingest; --nur schreiben
GRANT USAGE ON SEQUENCE auth_events_id_seq TO akku_ingest; -- fuer laufende nummer
GRANT SELECT ON geraete TO akku_ingest; -- geraete nur lesen

-- rolle fuer grafana
CREATE ROLE grafana_ro LOGIN PASSWORD '$DB_GRAFANA_PASSWORD';
GRANT CONNECT ON DATABASE akku TO grafana_ro;
GRANT USAGE ON SCHEMA public TO grafana_ro;
GRANT SELECT ON messwerte, messwerte_stunde, geraete TO grafana_ro; --nur lesen, kein auth_events
EOSQL
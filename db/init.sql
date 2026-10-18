-- timescaledb einschalten
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- tabelle geraete
CREATE TABLE geraete (
  geraet_id TEXT PRIMARY KEY, -- z.b. akku-001 gleich wie cn im zertifikat
  token_hash TEXT NOT NULL, --nur der hash vom token
  standort TEXT, -- wo das geraet ist
  akku_typ TEXT, --z.b. PS-1270
  akku_kapazitaet_ah NUMERIC(6,2), -- nennkapazitaet
  inbetriebnahme DATE, -- datum einbau
  aktiv BOOLEAN NOT NULL DEFAULT TRUE, --false = gesperrt
  angelegt_am TIMESTAMPTZ NOT NULL DEFAULT now() -- wann eingetragen
);

-- tabelle messwerte
CREATE TABLE messwerte (
  zeit TIMESTAMPTZ NOT NULL, -- zeit vom geraet
  geraet_id TEXT NOT NULL REFERENCES geraete(geraet_id), --muss in geraete stehen
  spannung_v NUMERIC(6,3), -- akkuspannung
  strom_ma NUMERIC(9,2), --strom durch shunt
  temperatur_c NUMERIC(5,2), -- vom bmp280
  druck_hpa NUMERIC(7,2), -- vom bmp280
  innenwiderstand_mohm NUMERIC(8,3), --aus lastpruefung
  soh_prozent NUMERIC(5,2), -- gesundheitszustand
  netzausfall BOOLEAN DEFAULT FALSE, -- unter 13v
  empfangen_am TIMESTAMPTZ NOT NULL DEFAULT now() --wann am server angekommen
);

-- messwerte zur hypertable machen abschnitte 7 tage
SELECT create_hypertable('messwerte', 'zeit', chunk_time_interval => INTERVAL '7 days');

-- index fuer abfragen nach geraet und zeit
CREATE INDEX idx_messwerte_geraet_zeit ON messwerte (geraet_id, zeit DESC);

-- tabelle anmeldeversuche
CREATE TABLE auth_events (
  id BIGSERIAL PRIMARY KEY, -- laufende nummer
  zeit TIMESTAMPTZ NOT NULL DEFAULT now(), --zeitpunkt
  geraet_id TEXT, -- leer wenn unbekannt
  cert_cn TEXT, --cn aus zertifikat
  quell_ip TEXT, -- absender
  erfolg BOOLEAN NOT NULL, -- angenommen ja nein
  grund TEXT --grund bei ablehnung
);

-- messwerte nach 2 jahren loeschen
SELECT add_retention_policy('messwerte', INTERVAL '2 years');

-- stundenwerte fuer grafana
CREATE MATERIALIZED VIEW messwerte_stunde
WITH (timescaledb.continuous) AS
SELECT
  time_bucket('1 hour', zeit) AS stunde, -- auf stunde runden
  geraet_id, --pro geraet
  AVG(spannung_v) AS spannung_mittel, -- mittelwert spannung
  MIN(spannung_v) AS spannung_min, --tiefste spannung
  AVG(strom_ma) AS strom_mittel, -- mittelwert strom
  AVG(temperatur_c) AS temperatur_mittel, -- mittelwert temperatur
  MAX(temperatur_c) AS temperatur_max, --hoechste temperatur
  AVG(soh_prozent) AS soh_mittel, -- mittelwert soh
  COUNT(*) AS anzahl_messungen --anzahl werte pro stunde
FROM messwerte
GROUP BY stunde, geraet_id
WITH NO DATA;

-- stundenwerte alle 30 min neu rechnen
SELECT add_continuous_aggregate_policy('messwerte_stunde',
  start_offset => INTERVAL '3 days', -- bis 3 tage zurueck
  end_offset => INTERVAL '1 hour', --letzte stunde noch nicht
  schedule_interval => INTERVAL '30 minutes'); -- alle 30 min
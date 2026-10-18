const express = require('express'); // webserver
const crypto = require('crypto'); //fuer hash und vergleich
const { Pool } = require('pg'); // verbindung datenbank

const app = express();
app.use(express.json({ limit: '256kb' })); // json annehmen max 256kb

const pool = new Pool({ connectionString: process.env.DATABASE_URL }); //rolle akku_ingest

// hash vom token
function tokenHash(token) {
  return crypto.createHash('sha256').update(token, 'utf8').digest('hex');
}

// cn aus den zertifikat angaben von caddy holen z.b. CN=akku-001,O=Akku-Monitor,C=CH
function cnLesen(subject) {
  if (!subject) return null; //nichts mitgeschickt
  const treffer = subject.match(/CN=([^,]+)/); // teil nach CN= bis zum komma
  return treffer ? treffer[1] : null;
}

// versuch in auth_events speichern
function logAuth(geraetId, cn, ip, erfolg, grund) {
  pool.query(
    'INSERT INTO auth_events (geraet_id, cert_cn, quell_ip, erfolg, grund) VALUES ($1, $2, $3, $4, $5)',
    [geraetId, cn, ip, erfolg, grund]
  ).catch(err => console.error('auth_events fehler:', err.message)); //fehler hier stoppt nichts
}

// messwerte annehmen
app.post('/api/v1/messwerte', async (req, res) => {
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress; // absender
  const cn = cnLesen(req.headers['x-client-subject']); //von caddy gesetzt

  // 1 cn vorhanden
  if (!cn) {
    logAuth(null, null, ip, false, 'kein CN');
    return res.status(401).json({ fehler: 'nicht authentifiziert' });
  }

  const { geraet_id, token, messwerte } = req.body || {}; // aus json holen

  // 2 alles da und 1 bis 500 werte
  if (!geraet_id || !token || !Array.isArray(messwerte) || messwerte.length === 0 || messwerte.length > 500) {
    logAuth(geraet_id || null, cn, ip, false, 'ungueltiges format');
    return res.status(400).json({ fehler: 'ungueltiges format' });
  }

  // 3 kennung gleich wie cn
  if (geraet_id !== cn) {
    logAuth(geraet_id, cn, ip, false, 'CN passt nicht');
    return res.status(403).json({ fehler: 'zertifikat passt nicht zur geraete-id' });
  }

  try {
    // 4 geraet eingetragen und aktiv
    const geraet = await pool.query('SELECT token_hash, aktiv FROM geraete WHERE geraet_id = $1', [geraet_id]);
    if (geraet.rowCount === 0) {
      logAuth(geraet_id, cn, ip, false, 'nicht registriert');
      return res.status(403).json({ fehler: 'nicht registriert' });
    }
    if (!geraet.rows[0].aktiv) {
      logAuth(geraet_id, cn, ip, false, 'gesperrt');
      return res.status(403).json({ fehler: 'geraet gesperrt' });
    }

    // 5 token pruefen immer gleich lang
    const erwartet = Buffer.from(geraet.rows[0].token_hash, 'utf8');
    const geliefert = Buffer.from(tokenHash(token), 'utf8');
    if (erwartet.length !== geliefert.length || !crypto.timingSafeEqual(erwartet, geliefert)) {
      logAuth(geraet_id, cn, ip, false, 'token ungueltig');
      return res.status(403).json({ fehler: 'token ungueltig' });
    }

    // alle pruefungen ok, werte speichern
    const client = await pool.connect();
    let anzahl = 0;
    try {
      await client.query('BEGIN'); // alles oder nichts
      for (const m of messwerte) {
        await client.query(
          `INSERT INTO messwerte (zeit, geraet_id, spannung_v, strom_ma, temperatur_c, druck_hpa,
             innenwiderstand_mohm, soh_prozent, netzausfall)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`, //werte getrennt vom befehl
          [m.zeit, geraet_id, m.spannung_v ?? null, m.strom_ma ?? null, m.temperatur_c ?? null,
           m.druck_hpa ?? null, m.innenwiderstand_mohm ?? null, m.soh_prozent ?? null, m.netzausfall ?? false]
        );
        anzahl++;
      }
      await client.query('COMMIT'); // speichern
    } catch (err) {
      await client.query('ROLLBACK'); //rueckgaengig
      throw err;
    } finally {
      client.release(); // verbindung zurueck
    }

    logAuth(geraet_id, cn, ip, true, null);
    res.status(201).json({ gespeichert: anzahl }); // geraet loescht erst jetzt
  } catch (err) {
    console.error('fehler:', err.message); //nur im log
    res.status(500).json({ fehler: 'interner fehler' }); // keine details nach aussen
  }
});

app.listen(3000, () => console.log('Schnittstelle laeuft auf Port 3000'));
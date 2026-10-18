#!/usr/bin/env bash
# =====================================================================
#  Schritt 1  -  Eigene Zertifizierungsstelle (CA) erstellen
# =====================================================================
#  Wird EINMAL ausgefuehrt. Die CA signiert spaeter alle
#  Geraete-Zertifikate.
#
#  Warum eine eigene CA und nicht Let's Encrypt?
#  Let's Encrypt stellt SERVER-Zertifikate aus, damit Browser dem
#  Server vertrauen. Hier geht es um die umgekehrte Richtung: der
#  Server soll den GERAETEN vertrauen. Dafuer gibt es keinen
#  oeffentlichen Anbieter -- man betreibt eine eigene, private CA.
#  Der Vertrauensanker ist ausschliesslich diese eine ca.crt-Datei,
#  die Caddy kennt.
# =====================================================================

set -euo pipefail   # bei jedem Fehler sofort abbrechen

# ---------------------------------------------------------------------
#  Hinweis fuer Git Bash unter Windows
# ---------------------------------------------------------------------
#  Git Bash haelt Zeichenketten, die mit einem Schraegstrich beginnen,
#  fuer Windows-Pfade und wandelt sie um. Der Subject-String eines
#  Zertifikats (/C=CH/O=...) wuerde dadurch zerstoert.
#
#  MSYS_NO_PATHCONV=1 schaltet diese Umwandlung ab. Unter Linux und
#  macOS hat die Variable keine Wirkung.
# ---------------------------------------------------------------------
export MSYS_NO_PATHCONV=1

CA_DIR="$(dirname "$0")/ca"
mkdir -p "$CA_DIR"
chmod 700 "$CA_DIR"

if [ -f "$CA_DIR/ca.key" ]; then
    echo "FEHLER: Es existiert bereits eine CA in $CA_DIR"
    echo "Zum Neuanlegen zuerst das Verzeichnis sichern und loeschen."
    echo "ACHTUNG: Alle bestehenden Geraete-Zertifikate werden damit ungueltig!"
    exit 1
fi

echo ">>> Erzeuge privaten CA-Schluessel (EC, prime256v1)"
# Warum EC statt RSA?
#   - deutlich kuerzere Schluessel bei gleicher Sicherheit
#     (256 Bit EC entsprechen etwa 3072 Bit RSA)
#   - schnellere Handshakes, weniger Rechenlast auf dem ESP32
#   - kleinerer Speicherbedarf im Flash des Mikrocontrollers
openssl ecparam -name prime256v1 -genkey -noout -out "$CA_DIR/ca.key"
chmod 600 "$CA_DIR/ca.key"

echo ">>> Erzeuge CA-Zertifikat (Gueltigkeit 10 Jahre)"
# Lange Laufzeit, weil ein CA-Wechsel bedeutet, dass ALLE Geraete
# im Feld neue Zertifikate brauchen. Das will man selten tun.
openssl req -x509 -new -key "$CA_DIR/ca.key" \
    -sha256 -days 3650 \
    -out "$CA_DIR/ca.crt" \
    -subj "/C=CH/O=Akku-Monitor/CN=Akku-Monitor Root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
    # pathlen:0  -> diese CA darf keine weiteren CAs signieren,
    #               nur Endgeraete-Zertifikate. Begrenzt den Schaden,
    #               falls der CA-Schluessel kompromittiert wird.

# Seriennummernzaehler anlegen.
echo "01" > "$CA_DIR/serial"

echo
echo "==================================================================="
echo " CA erfolgreich erstellt."
echo
echo "   $CA_DIR/ca.crt   -> oeffentlich, kommt in den Caddy-Container"
echo "   $CA_DIR/ca.key   -> GEHEIM"
echo
echo " WICHTIG:"
echo " Die Datei ca.key ist der Generalschluessel des Systems. Wer sie"
echo " besitzt, kann beliebige gueltige Geraete-Zertifikate erzeugen."
echo " Sie gehoert NICHT auf den Server, sondern auf einen getrennten,"
echo " gesicherten Rechner oder einen verschluesselten USB-Stick."
echo "==================================================================="

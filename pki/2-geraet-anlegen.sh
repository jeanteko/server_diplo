#!/usr/bin/env bash
# =====================================================================
#  Schritt 3  -  Serverzertifikat fuer den LOKALEN Betrieb
# =====================================================================
#  Aufruf:   ./3-serverzertifikat.sh 192.168.1.50
#            (die lokale IP-Adresse deines Rechners)
#
#  Im spaeteren Internetbetrieb wird dieses Skript NICHT gebraucht --
#  dort holt Caddy das Serverzertifikat automatisch von Let's Encrypt.
#
#  Warum hier ein eigenes?
#  Let's Encrypt stellt nur Zertifikate fuer oeffentliche Domainnamen
#  aus, nicht fuer 192.168.x.x. Fuer den lokalen Betrieb signieren wir
#  das Serverzertifikat daher mit unserer eigenen CA.
#
#  Eleganter Nebeneffekt:
#  Das Geraet kennt diese CA bereits (CA_CERT in certs.h). Es kann den
#  Server damit ohne jede Zusatzkonfiguration pruefen. Genau so, wie es
#  spaeter im Internetbetrieb auch funktioniert -- nur mit einem
#  anderen Aussteller.
# =====================================================================
 
set -euo pipefail
 
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
 
if [ $# -ne 1 ]; then
    echo "Aufruf: $0 <lokale-ip>"
    echo "Beispiel: $0 192.168.1.50"
    echo
    echo "Die eigene IP findest du unter Windows mit:  ipconfig"
    echo "Gesucht ist die IPv4-Adresse des aktiven Netzwerkadapters."
    exit 1
fi
 
IP="$1"
 
if ! [[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    echo "FEHLER: '$IP' sieht nicht wie eine IPv4-Adresse aus."
    exit 1
fi
 
BASE="$(dirname "$0")"
CA_DIR="$BASE/ca"
OUT="$BASE/server"
 
if [ ! -f "$CA_DIR/ca.key" ]; then
    echo "FEHLER: Keine CA gefunden. Zuerst 1-ca-erstellen.sh ausfuehren."
    exit 1
fi
 
mkdir -p "$OUT"
 
echo ">>> Erzeuge Serverschluessel"
openssl ecparam -name prime256v1 -genkey -noout -out "$OUT/server.key"
chmod 600 "$OUT/server.key"
 
echo ">>> Erzeuge Signieranfrage"
openssl req -new -key "$OUT/server.key" \
    -out "$OUT/server.csr" \
    -subj "/C=CH/O=Akku-Monitor/CN=akku-server-lokal"
 
echo ">>> Signiere mit der eigenen CA"
# subjectAltName ist entscheidend: moderne TLS-Clients pruefen NUR
# dieses Feld, nicht mehr den Common Name. Fehlt die IP hier, lehnt
# der Client die Verbindung ab -- auch wenn das Zertifikat sonst
# gueltig ist.
#
# extendedKeyUsage=serverAuth grenzt die Verwendung ab: dieses
# Zertifikat kann nicht als Client-Zertifikat missbraucht werden.
#
# Die Erweiterungen werden in eine echte temporaere Datei geschrieben.
# Die urspruengliche Prozesssubstitution -extfile <(printf ...) ist
# eine Bash-Eigenheit: Bash legt dafuer einen Dateideskriptor an und
# uebergibt den Pfad /dev/fd/63. Die unter Windows installierte
# OpenSSL-Binary ist ein natives Windows-Programm und kennt dieses
# virtuelle Dateisystem nicht -> "Can't open /dev/fd/63 for reading".
# Eine reale Datei funktioniert auf allen Plattformen gleich.
EXT_DATEI="$OUT/openssl-ext.cnf"
cat > "$EXT_DATEI" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:$IP,IP:127.0.0.1,DNS:localhost
EOF
 
openssl x509 -req -in "$OUT/server.csr" \
    -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
    -CAcreateserial \
    -out "$OUT/server.crt" \
    -days 825 -sha256 \
    -extfile "$EXT_DATEI"
 
rm -f "$OUT/server.csr" "$EXT_DATEI"
 
echo
echo "==================================================================="
echo " Serverzertifikat erstellt fuer:"
echo "   IP        $IP"
echo "   zusaetzl. 127.0.0.1, localhost"
echo
echo " Gueltig 825 Tage (Maximum, das Browser akzeptieren)."
echo
echo " Der Browser wird trotzdem warnen, weil er unsere CA nicht kennt."
echo " Das ist normal und kein Fehler. Zwei Moeglichkeiten:"
echo "   a) Warnung wegklicken (fuer die Entwicklung voellig ausreichend)"
echo "   b) pki/ca/ca.crt unter Windows als vertrauenswuerdige"
echo "      Stammzertifizierungsstelle importieren"
echo
echo " Das GERAET warnt nicht -- es kennt die CA aus certs.h."
echo "==================================================================="
 
#!/usr/bin/env bash
# schritt 3: serverzertifikat für den lokalen betrieb
# aufruf: ./3-serverzertifikat.sh 192.168.1.23
set -euo pipefail   #bei fehler abbrechen
export MSYS_NO_PATHCONV=1   # git bash soll /C=CH/... nicht umwandeln

if [ $# -ne 1 ]; then   # ip mitgegeben?
    echo "Aufruf: $0 <lokale-ip>"
    echo "Beispiel: $0 192.168.1.23"
    exit 1
fi

IP="$1"

if ! [[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then   #ist es eine ip?
    echo "FEHLER: '$IP' ist keine IPv4-Adresse"
    exit 1
fi

BASE="$(dirname "$0")"
CA_DIR="$BASE/ca"   # hier liegt die ca
OUT="$BASE/server"   #hier kommt das serverzertifikat hin

if [ ! -f "$CA_DIR/ca.key" ]; then   # ca vorhanden?
    echo "FEHLER: keine CA, zuerst 1-ca-erstellen.sh ausführen"
    exit 1
fi

mkdir -p "$OUT"

echo ">>> Serverschlüssel erstellen"
openssl ecparam -name prime256v1 -genkey -noout -out "$OUT/server.key"
chmod 600 "$OUT/server.key"   #nur ich darf lesen

echo ">>> Signieranfrage erstellen"
openssl req -new -key "$OUT/server.key" \
    -out "$OUT/server.csr" \
    -subj "/C=CH/O=Akku-Monitor/CN=akku-server-lokal"

echo ">>> Mit eigener CA unterschreiben"
# erweiterungen in eigene datei, <(...) geht mit openssl unter windows nicht
EXT_DATEI="$OUT/openssl-ext.cnf"
cat > "$EXT_DATEI" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:$IP,IP:127.0.0.1,DNS:localhost,DNS:$IP
EOF
# ip muss im zertifikat stehen sonst lehnt das gerät ab, serverAuth = nur als server

openssl x509 -req -in "$OUT/server.csr" \
    -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
    -CAcreateserial \
    -out "$OUT/server.crt" \
    -days 825 -sha256 \
    -extfile "$EXT_DATEI"

rm -f "$OUT/server.csr" "$EXT_DATEI"   # hilfsdateien weg

echo "Serverzertifikat fertig für $IP, 127.0.0.1 und localhost, 825 Tage gültig"
echo "Browser warnt weil er die eigene CA nicht kennt, das gerät kennt sie aus zertifikat.h"
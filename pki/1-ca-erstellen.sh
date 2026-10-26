#!/usr/bin/env bash
# schritt 1: eigene zertifizierungsstelle (ca) erstellen, nur einmal ausführen
set -euo pipefail   # bei fehler sofort abbrechen
export MSYS_NO_PATHCONV=1   #git bash soll /C=CH/... nicht als pfad umwandeln

CA_DIR="$(dirname "$0")/ca"   # ordner für die ca
mkdir -p "$CA_DIR"
chmod 700 "$CA_DIR"   #nur ich darf rein

if [ -f "$CA_DIR/ca.key" ]; then   # gibt es schon eine ca?
    echo "FEHLER: CA gibt es schon in $CA_DIR"
    echo "Neue CA macht alle Gerätezertifikate ungültig"
    exit 1
fi

echo ">>> CA-Schlüssel erstellen"
openssl ecparam -name prime256v1 -genkey -noout -out "$CA_DIR/ca.key"   # ec schlüssel, kürzer als rsa
chmod 600 "$CA_DIR/ca.key"   #nur ich darf lesen

echo ">>> CA-Zertifikat erstellen, 10 Jahre gültig"
openssl req -x509 -new -key "$CA_DIR/ca.key" \
    -sha256 -days 3650 \
    -out "$CA_DIR/ca.crt" \
    -subj "/C=CH/O=Akku-Monitor/CN=Akku-Monitor Root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
# pathlen:0 = ca darf nur geräte und server unterschreiben, keine weitere ca

echo "01" > "$CA_DIR/serial"   # zähler für seriennummern

echo "CA fertig"
echo "  $CA_DIR/ca.crt -> öffentlich, kommt in caddy"
echo "  $CA_DIR/ca.key -> GEHEIM, nicht auf den server"
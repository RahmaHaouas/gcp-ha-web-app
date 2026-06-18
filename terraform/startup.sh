#!/bin/bash
set -e
apt-get update
apt-get install -y nginx

INSTANCE=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/name")
ZONE=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/zone" | cut -d/ -f4)

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html lang="fr">
<head><meta charset="utf-8"><title>HA Web App</title></head>
<body style="font-family:sans-serif;text-align:center;padding-top:60px">
  <h1>Highly Available Web App sur GCP</h1>
  <p>Cette requête a été servie par :</p>
  <h2>$INSTANCE</h2>
  <p>Zone : <strong>$ZONE</strong></p>
</body>
</html>
EOF

systemctl enable nginx
systemctl restart nginx
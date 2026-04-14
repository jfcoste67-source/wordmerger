#!/bin/bash
set -e

INSTALL_DIR="/opt/wordmerger"
ENV_FILE="$INSTALL_DIR/.env"

echo "==> Creating install directory..."
mkdir -p "$INSTALL_DIR/templates"
mkdir -p "$INSTALL_DIR/schemas"

echo "==> Copying application files..."
cp -r app "$INSTALL_DIR/"
cp requirements.txt "$INSTALL_DIR/"
cp -r deploy "$INSTALL_DIR/"
cp schemas/*.json "$INSTALL_DIR/schemas/"
cp templates/*.docx "$INSTALL_DIR/templates/"

echo "==> Creating virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"

echo "==> Installing Python dependencies..."
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip --quiet
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt" --quiet

echo "==> Generating .env file (if not already present)..."
if [ ! -f "$ENV_FILE" ]; then
    KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    echo "WORDMERGER_API_KEY=$KEY" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "    Generated API key: $KEY"
    echo "    (saved to $ENV_FILE — store this key securely)"
else
    echo "    .env already exists — skipping key generation"
fi

echo "==> Setting permissions..."
chown -R www-data:www-data "$INSTALL_DIR"
chmod -R 750 "$INSTALL_DIR"
chmod 600 "$ENV_FILE"

echo "==> Installing systemd service..."
cp "$INSTALL_DIR/deploy/wordmerger.service" /etc/systemd/system/wordmerger.service
systemctl daemon-reload
systemctl enable wordmerger
systemctl restart wordmerger

echo ""
echo "==> Done! Service status:"
systemctl status wordmerger --no-pager -l

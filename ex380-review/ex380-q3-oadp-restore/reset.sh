#!/bin/bash
set -e

DIR=$(cd "$(dirname "$0")" && pwd)

echo "=== EX380 Q3 RESET ==="
echo "This reset recreates the entire exam state."
echo "The setup script is idempotent and will reuse the installed OADP operator."
echo

exec "$DIR/setup.sh"

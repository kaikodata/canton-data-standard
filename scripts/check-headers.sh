#!/usr/bin/env bash
# Copyright (c) 2026 Challenger Deep SAS. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Verify that every tracked Daml source file carries the SPDX license header.
set -euo pipefail

missing=0
while IFS= read -r f; do
  if ! head -3 "$f" | grep -q 'SPDX-License-Identifier: Apache-2.0'; then
    echo "missing SPDX header: $f"
    missing=1
  fi
done < <(git ls-files '*.daml')

if [ "$missing" -ne 0 ]; then
  echo "Some Daml files are missing the SPDX header." >&2
  exit 1
fi
echo "All Daml files carry the SPDX header."

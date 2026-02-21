# SPDX-License-Identifier: PMPL-1.0-or-later
# _pathroot entry point for xonsh (Python-powered shell)

import os
from pathlib import Path

# Detect _pathroot installation
if 'PATHROOT_HOME' in ${...}:
    pathroot_root = $PATHROOT_HOME
elif Path.home() / '.pathroot' / 'env':
    pathroot_root = str(Path.home() / '.pathroot')
else:
    xdg_data_home = ${...}.get('XDG_DATA_HOME', str(Path.home() / '.local' / 'share'))
    pathroot_root = str(Path(xdg_data_home) / 'pathroot')

$PATHROOT_ROOT = pathroot_root

# Source environment
env_file = Path(pathroot_root) / 'env.xsh'
if env_file.exists():
    source @(str(env_file))

# Run validation
deno run --allow-read --allow-env @(pathroot_root)/src/Validate.mjs @($args)

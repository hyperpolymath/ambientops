#!/usr/bin/env node
// SPDX-License-Identifier: PMPL-1.0-or-later
// Bundle nicaug CLI with all ReScript dependencies

import * as esbuild from 'esbuild';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const rootDir = join(__dirname, '..');

async function bundle() {
  try {
    const result = await esbuild.build({
      entryPoints: [join(rootDir, 'src/nicaug/NicaugCLI.mjs')],
      bundle: true,
      platform: 'node',
      format: 'esm',
      outfile: join(rootDir, 'bin/nicaug.mjs'),
      external: ['@std/*'], // Keep Deno std imports external
      banner: {
        js: '#!/usr/bin/env -S deno run --allow-read --allow-env --allow-run\n',
      },
    });

    if (result.errors.length > 0) {
      console.error('Build errors:', result.errors);
      process.exit(1);
    }

    console.log('✅ nicaug bundled successfully to bin/nicaug.mjs');
  } catch (error) {
    console.error('Bundle failed:', error);
    process.exit(1);
  }
}

bundle();

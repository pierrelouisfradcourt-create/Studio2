// e2e — click-through navigateur réel (Playwright/chromium)
import { chromium } from 'playwright';

const BASE_URL = 'http://localhost:8080';
const TIMEOUT = 30000;

export async function runE2ECheck() {
  let browser = null;
  try {
    console.log('=== ORACLE E2E ===');
    console.log('Lancement du navigateur...');

    browser = await chromium.launch();
    const context = await browser.createBrowserContext();
    const page = await context.newPage();

    console.log(`Navigation vers ${BASE_URL}...`);
    await page.goto(BASE_URL, { waitUntil: 'networkidle', timeout: TIMEOUT });

    console.log('Vérification du canvas...');
    const canvas = await page.locator('#gameCanvas');
    if (!await canvas.isVisible()) {
      throw new Error('Canvas not found or not visible');
    }

    console.log('Vérification de window.__game...');
    const gameObj = await page.evaluate(() => window.__game);
    if (!gameObj) {
      throw new Error('window.__game not exposed');
    }

    console.log('État initial:', gameObj);
    if (gameObj.score !== 0 || gameObj.lives !== 3) {
      throw new Error('Initial state incorrect');
    }

    console.log('Simulation de touches clavier...');
    for (let i = 0; i < 10; i++) {
      await page.press('#gameCanvas', 'ArrowRight');
      await page.waitForTimeout(50);
    }

    const midGameState = await page.evaluate(() => window.__game);
    console.log('État après mouvements:', midGameState);

    console.log('Test de fin de partie forcée...');
    await page.evaluate(() => window.__game_debug.loseLife());
    await page.waitForTimeout(100);

    const endGameState = await page.evaluate(() => window.__game);
    console.log('État final:', endGameState);

    if (!endGameState.over) {
      throw new Error('Game did not end when expected');
    }

    console.log('Vérification de #overlay...');
    const overlay = await page.locator('#overlay');
    if (await overlay.evaluate((el) => el.classList.contains('hidden'))) {
      throw new Error('Overlay should be visible after game over');
    }

    console.log('Vérification de #restart...');
    const restartBtn = await page.locator('#restart');
    if (!await restartBtn.isVisible()) {
      throw new Error('Restart button not visible');
    }

    console.log('Test de restart...');
    await restartBtn.click();
    await page.waitForTimeout(100);

    const restartedState = await page.evaluate(() => window.__game);
    console.log('État après restart:', restartedState);

    if (restartedState.score !== 0 || restartedState.over) {
      throw new Error('Game did not restart correctly');
    }

    console.log('\nVERDICT E2E : PASS');
    return true;
  } catch (err) {
    console.error('\nVERDICT E2E : FAIL');
    console.error('Erreur:', err.message);
    return false;
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const result = await runE2ECheck();
  process.exit(result ? 0 : 1);
}

/**
 * ==============================================================================
 * SCRIPT PENDAFTARAN 1.000+ AKUN KE TWITTERAPI.IO WEBHOOK
 * ==============================================================================
 * Jalankan script ini untuk mendaftarkan seluruh akun di trackedAccounts.ts
 * ke layanan monitoring TwitterAPI.io secara otomatis.
 *
 * Penggunaan:
 * node scripts/register_twitterapi_monitors.js [API_KEY_TWITTERAPI_IO] [WEBHOOK_URL]
 *
 * Contoh:
 * node scripts/register_twitterapi_monitors.js abc123key https://vanafamily.com/api/webhook/twitterapi
 */

const fs = require('fs');
const path = require('path');

// 1. Baca daftar akun dari trackedAccounts.ts
const tsFilePath = path.join(__dirname, '../src/config/trackedAccounts.ts');
const tsContent = fs.readFileSync(tsFilePath, 'utf-8');

const match = tsContent.match(/TRACKED_ACCOUNTS:\s*string\[\]\s*=\s*(\[[^\]]+\])/s);
if (!match) {
  console.error('Gagal membaca TRACKED_ACCOUNTS dari trackedAccounts.ts');
  process.exit(1);
}

const accounts = JSON.parse(match[1]);
console.log(`Ditemukan ${accounts.length} akun yang akan didaftarkan ke TwitterAPI.io`);

const apiKey = process.argv[2] || process.env.TWITTERAPI_IO_KEY || '';
const webhookUrl = process.argv[3] || process.env.TWITTERAPI_WEBHOOK_URL || 'https://vanafamily.com/api/webhook/twitterapi';

if (!apiKey) {
  console.log('\n=============================================================');
  console.log('PETUNJUK PENGGUNAAN:');
  console.log('Dapatkan API Key di https://twitterapi.io');
  console.log('Lalu jalankan perintah:');
  console.log(`node scripts/register_twitterapi_monitors.js YOUR_API_KEY ${webhookUrl}`);
  console.log('=============================================================\n');
  process.exit(0);
}

console.log(`Target Webhook: ${webhookUrl}`);
console.log(`Memulai pendaftaran ${accounts.length} akun... Harap tunggu.\n`);

async function registerAccount(username) {
  try {
    // Format request sesuai spesifikasi TwitterAPI.io monitor endpoint
    const res = await fetch('https://api.twitterapi.io/twitter/monitor/add', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      },
      body: JSON.stringify({
        userName: username,
        webhookUrl: webhookUrl,
      }),
    });

    const data = await res.json().catch(() => ({}));
    return { username, ok: res.ok, status: res.status, data };
  } catch (err) {
    return { username, ok: false, error: err.message };
  }
}

async function run() {
  let successCount = 0;
  let failCount = 0;

  for (let i = 0; i < accounts.length; i++) {
    const user = accounts[i];
    process.stdout.write(`[${i + 1}/${accounts.length}] Mendaftarkan @${user}... `);
    const result = await registerAccount(user);

    if (result.ok) {
      console.log('BERHASIL');
      successCount++;
    } else {
      console.log(`GAGAL (${result.status || result.error})`);
      failCount++;
    }

    // Beri jeda 100ms agar tidak terkena rate-limit pendaftaran
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  console.log('\n=============================================================');
  console.log(`Selesai! Berhasil: ${successCount}, Gagal: ${failCount}`);
  console.log('=============================================================');
}

run();

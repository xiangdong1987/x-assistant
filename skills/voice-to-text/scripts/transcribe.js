#!/usr/bin/env node
/**
 * voice-to-text skill script
 *
 * Usage:
 *   node transcribe.js <audio_file_path> [language]
 *
 * Output (stdout):
 *   HANDOFF:{"transcript":"...","language":"it-IT"}
 *
 * 只负责调用 Google Speech-to-Text，不依赖 Telegram / Claude API。
 * OpenClaw 通过 ExecuteSkill 调用本脚本，获取转录文字后交由 Italian Tutor 处理。
 *
 * 环境变量:
 *   GOOGLE_SPEECH_API_KEY  Google Cloud Speech-to-Text API Key
 */

'use strict';

const fs = require('fs');
const https = require('https');
const path = require('path');

// Load .env from skill root
const envPath = path.join(__dirname, '..', '.env');
if (fs.existsSync(envPath)) {
  const lines = fs.readFileSync(envPath, 'utf8').split('\n');
  for (const line of lines) {
    const m = line.match(/^\s*([^#=]+)=(.*)$/);
    if (m) process.env[m[1].trim()] = m[2].trim().replace(/^["']|["']$/g, '');
  }
}

const API_KEY = process.env.GOOGLE_SPEECH_API_KEY;
if (!API_KEY) {
  console.error('GOOGLE_SPEECH_API_KEY is required');
  process.exit(1);
}

const filePath = process.argv[2];
const language = process.argv[3] || 'it-IT';

if (!filePath) {
  console.error('Usage: node transcribe.js <audio_file_path> [language]');
  process.exit(1);
}

if (!fs.existsSync(filePath)) {
  console.error(`File not found: ${filePath}`);
  process.exit(1);
}

// Detect encoding from file extension
const ext = path.extname(filePath).toLowerCase();
const ENCODING_MAP = {
  '.ogg': 'OGG_OPUS',
  '.opus': 'OGG_OPUS',
  '.mp3': 'MP3',
  '.flac': 'FLAC',
  '.wav': 'LINEAR16',
  '.m4a': 'MP4',
};
const encoding = ENCODING_MAP[ext] || 'OGG_OPUS';
const sampleRate = (encoding === 'OGG_OPUS') ? 48000 : 16000;

// Model selection:
//   enhanced (default) → SKU 7247-19E1-FB4D, useEnhanced:true, model:latest_short
//   standard           → SKU 6649-62EF-CB8F, useEnhanced:false, model:default
// For short voice clips (< 1 min) enhanced is more accurate.
// For longer recordings switch to latest_long via VOICE_MODEL=long env var.
const modelMode = process.env.VOICE_MODEL || 'enhanced';
const modelConfig = modelMode === 'standard'
  ? { model: 'default',       useEnhanced: false }
  : modelMode === 'long'
  ? { model: 'latest_long',   useEnhanced: true  }
  : { model: 'latest_short',  useEnhanced: true  };  // default: enhanced

const audioBytes = fs.readFileSync(filePath).toString('base64');

const body = JSON.stringify({
  config: {
    encoding,
    sampleRateHertz: sampleRate,
    languageCode: language,
    alternativeLanguageCodes: ['zh-CN', 'en-US'],
    enableAutomaticPunctuation: true,
    ...modelConfig,
  },
  audio: { content: audioBytes },
});

const options = {
  hostname: 'speech.googleapis.com',
  path: `/v1/speech:recognize?key=${API_KEY}`,
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
  },
};

const req = https.request(options, res => {
  let data = '';
  res.on('data', c => { data += c; });
  res.on('end', () => {
    try {
      const result = JSON.parse(data);
      if (result.error) {
        console.error('Google STT error:', result.error.message);
        process.exit(1);
      }
      const transcript = (result.results || [])
        .map(r => r.alternatives?.[0]?.transcript || '')
        .filter(Boolean)
        .join(' ')
        .trim();

      // HANDOFF format — proxy's ExecuteSkill reads this line
      console.log(`HANDOFF:${JSON.stringify({ transcript, language })}`);
    } catch (e) {
      console.error('Parse error:', e.message);
      process.exit(1);
    }
  });
});

req.on('error', e => { console.error(e.message); process.exit(1); });
req.write(body);
req.end();

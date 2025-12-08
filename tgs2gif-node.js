#!/usr/bin/env node

const TGS = require('tgs-to');
const path = require('path');
const fs = require('fs');

if (process.argv.length < 3)
{
    console.log('Usage: node tgs2gif-node.js input.tgs');
    process.exit(1);
}

const input = process.argv[2];

if (!fs.existsSync(input))
{
    console.log('❌ File not found:', input);
    process.exit(1);
}

const now = new Date();
const timestamp = now.toISOString()
    .replace(/[-:]/g, '')
    .replace(/\..+/, '')
    .replace('T', '-')
    .substring(0, 15);

const basename = path.basename(input, '.tgs');
const output = path.join(path.dirname(input), `${basename}_${timestamp}.gif`);

const tgs = new TGS(input);

console.log('🎬 Converting TGS to GIF...');
tgs.convertToGif(output)
    .then(() =>
    {
        console.log(`✅ Done: ${output}`);

        // Move original to Trash
        const trashPath = path.join(process.env.HOME, '.Trash', path.basename(input));
        fs.renameSync(input, trashPath);
        console.log('🗑 Moved original to Trash');
    })
    .catch(err =>
    {
        console.error('❌ Conversion failed:', err.message);
        process.exit(1);
    });
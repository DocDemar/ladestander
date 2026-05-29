require('dotenv').config();
const { Pool } = require('pg');
const fs = require('fs');
const db = new Pool({ connectionString: process.env.DATABASE_URL });
const file = process.argv[2] || './migrations/010_bbox_operator_filter.sql';
const sql = fs.readFileSync(file, 'utf8');
db.query(sql).then(() => {
  console.log('Migration kørt OK:', file);
  db.end();
}).catch(e => { console.error('Fejl:', e.message); db.end(); });
